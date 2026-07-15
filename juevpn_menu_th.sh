#!/usr/bin/env bash
# JueVPN Unified Thai Menu v1.0
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; RESET='\033[0m'

ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
error() { echo -e "${RED}[ผิดพลาด]${RESET} $*"; }
pause_menu() { read -r -n 1 -s -p "กดปุ่มใดก็ได้เพื่อกลับเมนู..."; echo; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { error "กรุณารันด้วย sudo"; exit 1; }; }
run_local() { local file="$1"; shift; [[ -x "$SCRIPT_DIR/$file" ]] || { error "ไม่พบ $file"; return 1; }; "$SCRIPT_DIR/$file" "$@"; }

service_state() {
    local service="$1"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}ออนไลน์${RESET}"
    elif systemctl cat "$service" >/dev/null 2>&1; then
        echo -e "${RED}ออฟไลน์${RESET}"
    else
        echo -e "${YELLOW}ยังไม่ติดตั้ง${RESET}"
    fi
}

show_status_all() {
    echo -e "${CYAN}===== สถานะบริการทั้งหมด =====${RESET}"
    printf '%-20s ' 'JueUDP/Hysteria:'; service_state hysteria-server.service
    printf '%-20s ' 'WebSocket:'; service_state agn-websocket.service
    printf '%-20s ' 'ZIVPN:'; service_state zivpn.service
    echo
    ss -lntup 2>/dev/null | grep -E 'hysteria|zivpn|jue_websocket|python3' || warn "ไม่พบ process ที่เกี่ยวข้องในรายการพอร์ต"
}

show_logs() {
    echo "1) JueUDP/Hysteria"
    echo "2) WebSocket"
    echo "3) ZIVPN"
    read -r -p "เลือก log: " choice
    case "$choice" in
        1) journalctl -u hysteria-server.service -n 100 --no-pager ;;
        2) journalctl -u agn-websocket.service -n 100 --no-pager ;;
        3) journalctl -u zivpn.service -n 100 --no-pager ;;
        *) warn "เมนูไม่ถูกต้อง" ;;
    esac
}

show_menu() {
    clear
    ip="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
    iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    echo -e "${CYAN}================================================${RESET}"
    echo -e "${WHITE}       JUEVPN THAI STABLE - เมนูหลัก${RESET}"
    echo -e "${CYAN}================================================${RESET}"
    echo "IP: ${ip:-ไม่พบ} | Network: ${iface:-ไม่พบ}"
    printf 'JueUDP: '; service_state hysteria-server.service
    printf 'WebSocket: '; service_state agn-websocket.service
    printf 'ZIVPN: '; service_state zivpn.service
    echo -e "${CYAN}------------------------------------------------${RESET}"
    echo "1) ติดตั้ง JueUDP / Hysteria"
    echo "2) เปิดเมนูจัดการ JueUDP"
    echo "3) ติดตั้ง WebSocket"
    echo "4) เปิดเมนูจัดการ WebSocket"
    echo "5) เปิดเมนู ZIVPN"
    echo "6) ใช้ค่าปรับเสถียรภาพเครือข่าย"
    echo "7) ดูสถานะทั้งหมด"
    echo "8) ดู log"
    echo "9) ตรวจสอบ syntax ไฟล์ในชุด"
    echo "0) ออก"
}

check_files() {
    local failed=0
    for file in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/JueUDP_th "$SCRIPT_DIR"/menuzivpn_th; do
        [[ -f "$file" ]] || continue
        if bash -n "$file"; then echo -e "${GREEN}OK${RESET} $(basename "$file")"; else echo -e "${RED}FAIL${RESET} $(basename "$file")"; failed=1; fi
    done
    if python3 -m py_compile "$SCRIPT_DIR/jue_websocket_stable.py"; then
        echo -e "${GREEN}OK${RESET} jue_websocket_stable.py"
    else
        failed=1
    fi
    return "$failed"
}

require_root
while true; do
    show_menu
    read -r -p "เลือกเมนู: " choice
    case "$choice" in
        1) run_local install_jueudp_th.sh; pause_menu ;;
        2) if command -v jueudp >/dev/null 2>&1; then jueudp; else warn "ยังไม่ได้ติดตั้ง JueUDP"; pause_menu; fi ;;
        3) run_local install_websocket_th.sh; pause_menu ;;
        4) if command -v websocket >/dev/null 2>&1; then websocket menu; else warn "ยังไม่ได้ติดตั้ง WebSocket"; pause_menu; fi ;;
        5) run_local zivpn_menu_th.sh ;;
        6) run_local network_stability_th.sh; pause_menu ;;
        7) show_status_all; pause_menu ;;
        8) show_logs; pause_menu ;;
        9) check_files; pause_menu ;;
        0) exit 0 ;;
        *) warn "เมนูไม่ถูกต้อง"; sleep 1 ;;
    esac
done
