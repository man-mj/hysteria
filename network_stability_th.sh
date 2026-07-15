#!/usr/bin/env bash
# JueVPN Network Stability Tuning v1.0
set -Eeuo pipefail

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'

log() { echo -e "${CYAN}[JueVPN]${RESET} $*"; }
ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
die() { echo -e "${RED}[ผิดพลาด]${RESET} $*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "กรุณารันด้วยสิทธิ์ root: sudo $0"

DEFAULT_IFACE="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
[[ -n "$DEFAULT_IFACE" ]] || warn "ไม่พบ network interface หลัก จะใช้ค่าแบบรวมแทน"

log "กำลังติดตั้งค่าปรับแต่งเครือข่ายแบบถาวร..."
cat > /etc/sysctl.d/99-juevpn-stability.conf <<EOF_SYSCTL
# JueVPN stability profile
# ใช้ค่าแบบไม่สุดโต่ง เพื่อเพิ่ม buffer และลดการหลุดจากเส้นทาง/MTU
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 4096
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF_SYSCTL

sysctl --system >/dev/null
ok "ใช้ค่าปรับแต่งเครือข่ายแล้ว"

install_restart_dropin() {
    local service="$1"
    if systemctl cat "$service" >/dev/null 2>&1; then
        local dir="/etc/systemd/system/${service}.d"
        mkdir -p "$dir"
        cat > "$dir/10-juevpn-stability.conf" <<'EOF_DROPIN'
[Unit]
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=2s
TimeoutStopSec=10s
LimitNOFILE=1048576
EOF_DROPIN
        ok "เพิ่มระบบฟื้นตัวอัตโนมัติให้ $service"
    fi
}

install_restart_dropin hysteria-server.service
install_restart_dropin agn-websocket.service
install_restart_dropin zivpn.service

systemctl daemon-reload
for svc in hysteria-server.service agn-websocket.service zivpn.service; do
    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        systemctl try-restart "$svc" || warn "รีสตาร์ต $svc ไม่สำเร็จ กรุณาดู journalctl -u $svc"
    fi
done

cat <<'EOF_NOTE'

หมายเหตุ:
- ฝั่งเซิร์ฟเวอร์ไม่มีวิธีรับประกันว่าอินเทอร์เน็ตจะไม่หลุด 100%
- ชุดนี้ช่วยให้ service กลับมาทำงานเอง เพิ่ม socket buffer และเปิด TCP keepalive
- ถ้าสัญญาณมือถือ/Wi-Fi เปลี่ยนเครือข่าย ฝั่งแอปไคลเอนต์ต้องรองรับ reconnect ด้วย
EOF_NOTE
