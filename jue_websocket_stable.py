#!/usr/bin/env python3
"""Jue WebSocket/HTTP tunnel proxy - stable edition.

ใช้ Python standard library เท่านั้น รองรับ TCP keepalive, backlog และ graceful shutdown.
"""
from __future__ import annotations

import argparse
import os
import select
import signal
import socket
import sys
import threading
from dataclasses import dataclass
from typing import Optional, Tuple

BUFFER_SIZE = 64 * 1024
MAX_HEADER_SIZE = 64 * 1024
HEADER_TIMEOUT = 15
CONNECT_TIMEOUT = 12
LISTEN_BACKLOG = 256

SWITCHING_RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Connection: Upgrade\r\n"
    b"Upgrade: websocket\r\n"
    b"\r\n"
)


def configure_socket(sock: socket.socket) -> None:
    """เปิด keepalive และตั้งค่าที่รองรับใน kernel ปัจจุบัน."""
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    if sock.family in (socket.AF_INET, socket.AF_INET6):
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        for name, value in (
            ("TCP_KEEPIDLE", 30),
            ("TCP_KEEPINTVL", 10),
            ("TCP_KEEPCNT", 6),
            ("TCP_USER_TIMEOUT", 90_000),
        ):
            option = getattr(socket, name, None)
            if option is not None:
                try:
                    sock.setsockopt(socket.IPPROTO_TCP, option, value)
                except OSError:
                    pass


def parse_host_port(value: str, default_port: int = 22) -> Tuple[str, int]:
    value = value.strip()
    if value.startswith("["):
        end = value.find("]")
        if end < 0:
            raise ValueError("รูปแบบ IPv6 ไม่ถูกต้อง")
        host = value[1:end]
        port = int(value[end + 2 :]) if value[end + 1 :].startswith(":") else default_port
        return host, port

    if value.count(":") == 1:
        host, raw_port = value.rsplit(":", 1)
        return host, int(raw_port)
    if ":" in value:  # IPv6 ที่ไม่ได้ใส่วงเล็บและไม่ได้ระบุพอร์ต
        return value, default_port
    return value, default_port


def is_loopback_host(host: str) -> bool:
    return host.lower() == "localhost" or host.startswith("127.") or host == "::1"


def read_http_headers(client: socket.socket) -> tuple[bytes, bytes]:
    client.settimeout(HEADER_TIMEOUT)
    data = bytearray()
    marker = b"\r\n\r\n"
    while marker not in data:
        chunk = client.recv(min(BUFFER_SIZE, MAX_HEADER_SIZE - len(data)))
        if not chunk:
            raise ConnectionError("ไคลเอนต์ปิดการเชื่อมต่อก่อนส่ง header ครบ")
        data.extend(chunk)
        if len(data) >= MAX_HEADER_SIZE and marker not in data:
            raise ValueError("HTTP header มีขนาดใหญ่เกินกำหนด")
    head, remainder = bytes(data).split(marker, 1)
    client.settimeout(None)
    return head, remainder


def parse_headers(raw: bytes) -> dict[str, str]:
    result: dict[str, str] = {}
    lines = raw.split(b"\r\n")
    for line in lines[1:]:
        if b":" not in line:
            continue
        key, value = line.split(b":", 1)
        result[key.decode("latin-1").strip().lower()] = value.decode("latin-1").strip()
    return result


@dataclass(frozen=True)
class ProxyConfig:
    bind: str
    port: int
    password: str
    default_host: str


class TunnelConnection(threading.Thread):
    def __init__(self, client: socket.socket, address: tuple, server: "ProxyServer") -> None:
        super().__init__(daemon=True, name=f"tunnel-{address}")
        self.client = client
        self.address = address
        self.server = server
        self.target: Optional[socket.socket] = None
        self.closed = threading.Event()

    def close(self) -> None:
        if self.closed.is_set():
            return
        self.closed.set()
        for sock in (self.client, self.target):
            if sock is None:
                continue
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass

    def reject(self, status: str) -> None:
        try:
            body = (status + "\n").encode("utf-8")
            self.client.sendall(
                f"HTTP/1.1 {status}\r\nConnection: close\r\nContent-Length: {len(body)}\r\n\r\n".encode("ascii")
                + body
            )
        except OSError:
            pass

    def connect_target(self, host: str, port: int) -> socket.socket:
        target = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
        configure_socket(target)
        target.settimeout(None)
        return target

    def relay(self) -> None:
        assert self.target is not None
        sockets = [self.client, self.target]
        while not self.closed.is_set() and not self.server.stopping.is_set():
            readable, _, exceptional = select.select(sockets, [], sockets, 30)
            if exceptional:
                return
            if not readable:
                # ไม่ตัด session ที่ idle; kernel keepalive จะตรวจ connection ที่ตายจริง
                continue
            for source in readable:
                destination = self.target if source is self.client else self.client
                try:
                    payload = source.recv(BUFFER_SIZE)
                    if not payload:
                        return
                    destination.sendall(payload)
                except (ConnectionError, OSError):
                    return

    def run(self) -> None:
        target_text = ""
        try:
            configure_socket(self.client)
            raw_headers, remainder = read_http_headers(self.client)
            headers = parse_headers(raw_headers)
            target_text = headers.get("x-real-host", self.server.config.default_host)
            supplied_password = headers.get("x-pass", "")

            host, port = parse_host_port(target_text)
            if self.server.config.password:
                if supplied_password != self.server.config.password:
                    self.reject("401 Unauthorized")
                    return
            elif not is_loopback_host(host):
                self.reject("403 Forbidden")
                return

            self.target = self.connect_target(host, port)
            self.client.sendall(SWITCHING_RESPONSE)
            if remainder:
                self.target.sendall(remainder)

            self.server.log(f"เชื่อมต่อ {self.address[0]} -> {host}:{port}")
            self.relay()
        except (ValueError, ConnectionError, OSError) as exc:
            self.server.log(f"การเชื่อมต่อล้มเหลว {self.address} target={target_text or '-'}: {exc}")
        finally:
            self.close()
            self.server.remove(self)


class ProxyServer:
    def __init__(self, config: ProxyConfig) -> None:
        self.config = config
        self.listener: Optional[socket.socket] = None
        self.connections: set[TunnelConnection] = set()
        self.lock = threading.Lock()
        self.stopping = threading.Event()

    def log(self, message: str) -> None:
        print(f"[JueWS] {message}", flush=True)

    def add(self, connection: TunnelConnection) -> None:
        with self.lock:
            self.connections.add(connection)

    def remove(self, connection: TunnelConnection) -> None:
        with self.lock:
            self.connections.discard(connection)

    def stop(self, *_: object) -> None:
        if self.stopping.is_set():
            return
        self.stopping.set()
        self.log("กำลังหยุดบริการ...")
        if self.listener is not None:
            try:
                self.listener.close()
            except OSError:
                pass
        with self.lock:
            connections = list(self.connections)
        for connection in connections:
            connection.close()

    def serve_forever(self) -> None:
        infos = socket.getaddrinfo(
            self.config.bind,
            self.config.port,
            socket.AF_UNSPEC,
            socket.SOCK_STREAM,
            0,
            socket.AI_PASSIVE,
        )
        last_error: Optional[Exception] = None
        for family, socktype, proto, _, address in infos:
            try:
                listener = socket.socket(family, socktype, proto)
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                if family == socket.AF_INET6:
                    try:
                        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
                    except OSError:
                        pass
                listener.bind(address)
                listener.listen(LISTEN_BACKLOG)
                listener.settimeout(2)
                self.listener = listener
                break
            except OSError as exc:
                last_error = exc
                try:
                    listener.close()
                except Exception:
                    pass
        else:
            raise OSError(f"เปิดพอร์ตไม่ได้: {last_error}")

        self.log(f"กำลังฟังที่ {self.config.bind}:{self.config.port}")
        self.log("โหมดรหัสผ่าน: เปิด" if self.config.password else "โหมดรหัสผ่าน: ปิด (อนุญาตเฉพาะปลายทาง localhost)")

        while not self.stopping.is_set():
            try:
                client, address = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                if self.stopping.is_set():
                    break
                raise
            connection = TunnelConnection(client, address, self)
            self.add(connection)
            connection.start()

        self.stop()


def build_config(argv: list[str]) -> ProxyConfig:
    parser = argparse.ArgumentParser(description="Jue WebSocket tunnel proxy")
    parser.add_argument("-b", "--bind", default=os.getenv("JUEWS_BIND", "0.0.0.0"))
    parser.add_argument("-p", "--port", type=int, default=int(os.getenv("JUEWS_PORT", "8098")))
    parser.add_argument("--password", default=os.getenv("JUEWS_PASSWORD", ""))
    parser.add_argument("--default-host", default=os.getenv("JUEWS_DEFAULT_HOST", "127.0.0.1:22"))
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("พอร์ตต้องอยู่ระหว่าง 1-65535")
    return ProxyConfig(args.bind, args.port, args.password, args.default_host)


def main(argv: list[str]) -> int:
    config = build_config(argv)
    server = ProxyServer(config)
    signal.signal(signal.SIGTERM, server.stop)
    signal.signal(signal.SIGINT, server.stop)
    try:
        server.serve_forever()
    except OSError as exc:
        print(f"[JueWS] เริ่มบริการไม่สำเร็จ: {exc}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
