#!/usr/bin/env bash
# ZIVPN Thai Manager v1.0
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="zivpn.service"
CONFIG_FILE="/etc/zivpn/config.json"
STABILITY="/usr/local/sbin/juevpn-network-stability"
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; RESET='\033[0m'

ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
error() { echo -e "${RED}[ผิดพลาด]${RESET} $*"; }
pause_menu() { read -r -n 1 -s -p "กดปุ่มใดก็ได้เพื่อกลับเมนู..."; echo; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { error "กรุณารันด้วย sudo"; exit 1; }; }

find_installer() {
    local file="$1"
    if [[ -x "$SCRIPT_DIR/$file" ]]; then printf '%s' "$SCRIPT_DIR/$file"; return; fi
    if [[ -x "/opt/juevpn-tools/$file" ]]; then printf '%s' "/opt/juevpn-tools/$file"; return; fi
    if [[ -x "/root/JueVPN_Thai_Stable_v1/$file" ]]; then printf '%s' "/root/JueVPN_Thai_Stable_v1/$file"; return; fi
    return 1
}

install_variant() {
    local variant installer
    variant="$1"
    installer="$(find_installer "ziv${variant}_stable_th.sh")" || { error "ไม่พบไฟล์ติดตั้ง ziv${variant}_stable_th.sh กรุณารันจากโฟลเดอร์ชุดติดตั้ง"; return; }
    "$installer"
}

service_action() {
    local action="$1"
    if systemctl "$action" "$SERVICE"; then ok "ดำเนินการ $action แล้ว"; else error "ดำเนินการไม่สำเร็จ"; fi
}

show_status() {
    systemctl --no-pager --full status "$SERVICE" || true
    echo
    if [[ -f "$CONFIG_FILE" ]]; then
        port="$(jq -r '.listen // "-"' "$CONFIG_FILE")"
        echo "พอร์ตภายใน: $port"
        ss -lunp 2>/dev/null | grep -F "$port" || warn "ยังไม่พบพอร์ตที่กำลังฟัง"
    fi
}

change_passwords() {
    [[ -f "$CONFIG_FILE" ]] || { error "ยังไม่ได้ติดตั้ง ZIVPN"; return; }
    local input values tmp
    read -r -p "รหัสผ่านใหม่ คั่นด้วย comma: " input
    values="$(jq -n --arg value "$input" '$value | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))')"
    [[ "$(jq 'length' <<<"$values")" -gt 0 ]] || { error "ต้องมีอย่างน้อย 1 รหัส"; return; }
    if jq -e 'any(.[]; test("[:[:space:]]"))' <<<"$values" >/dev/null; then error "รหัสห้ามมี : หรือช่องว่าง"; return; fi
    tmp="$(mktemp /etc/zivpn/config.XXXXXX)"
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    jq --argjson values "$values" '.auth.config=$values' "$CONFIG_FILE" > "$tmp" && jq empty "$tmp" && mv "$tmp" "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE"
    systemctl restart "$SERVICE" && ok "เปลี่ยนรหัสผ่านแล้ว"
}

show_info() {
    echo -e "${CYAN}===== ข้อมูล ZIVPN =====${RESET}"
    if [[ ! -f "$CONFIG_FILE" ]]; then warn "ยังไม่ได้ติดตั้ง"; return; fi
    echo "Listen:    $(jq -r '.listen' "$CONFIG_FILE")"
    echo "Obfs:      $(jq -r '.obfs' "$CONFIG_FILE")"
    echo "Passwords: $(jq '.auth.config | length' "$CONFIG_FILE") ค่า"
    echo "Binary:    $(/usr/local/bin/zivpn --version 2>/dev/null | head -1 || echo 'ไม่แสดงเวอร์ชัน')"
}

uninstall_zivpn() {
    local confirm purge iface
    read -r -p "ยืนยันถอน ZIVPN? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return
    iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    if [[ -n "$iface" ]]; then
        for spec in '20000:50000 5666' '6000:19999 5667'; do
            read -r range port <<<"$spec"
            while iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport "$range" -j DNAT --to-destination ":$port" 2>/dev/null; do
                iptables -w -t nat -D PREROUTING -i "$iface" -p udp --dport "$range" -j DNAT --to-destination ":$port"
            done
        done
    fi
    systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/zivpn.service /usr/local/bin/zivpn /usr/local/bin/zivpn-menu /usr/local/bin/JueUDP
    rm -rf /etc/systemd/system/zivpn.service.d
    rm -rf /opt/juevpn-tools
    read -r -p "พิมพ์ PURGE เพื่อลบ config/certificate หรือ Enter เพื่อเก็บไว้: " purge
    [[ "$purge" == "PURGE" ]] && rm -rf /etc/zivpn
    systemctl daemon-reload
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
    ok "ถอนการติดตั้งแล้ว"
    exit 0
}

show_menu() {
    clear
    ip="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
    iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}          ZIVPN - เมนูภาษาไทย${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo "IP: ${ip:-ไม่พบ} | Network: ${iface:-ไม่พบ}"
    printf "สถานะ: "
    systemctl is-active --quiet "$SERVICE" && echo -e "${GREEN}ออนไลน์${RESET}" || echo -e "${RED}ออฟไลน์${RESET}"
    echo "1) ติดตั้งแบบ V1 (UDP 20000-50000 -> 5666)"
    echo "2) ติดตั้งแบบ V2 (UDP 6000-19999 -> 5667) [แนะนำ]"
    echo "3) เริ่มบริการ"
    echo "4) หยุดบริการ"
    echo "5) รีสตาร์ตบริการ"
    echo "6) ดูสถานะละเอียด"
    echo "7) เปลี่ยนรหัสผ่าน UDP"
    echo "8) ดู log ล่าสุด"
    echo "9) ดูข้อมูลตั้งค่า"
    echo "10) ใช้ค่าปรับเสถียรภาพ"
    echo "11) ถอนการติดตั้ง"
    echo "0) ออก"
}

require_root
while true; do
    show_menu
    read -r -p "เลือกเมนู: " choice
    case "$choice" in
        1) install_variant 1; pause_menu ;;
        2) install_variant 2; pause_menu ;;
        3) service_action start; pause_menu ;;
        4) service_action stop; pause_menu ;;
        5) service_action restart; pause_menu ;;
        6) show_status; pause_menu ;;
        7) change_passwords; pause_menu ;;
        8) journalctl -u "$SERVICE" -n 100 --no-pager; pause_menu ;;
        9) show_info; pause_menu ;;
        10) [[ -x "$STABILITY" ]] && "$STABILITY" || error "ไม่พบสคริปต์ปรับเสถียรภาพ"; pause_menu ;;
        11) uninstall_zivpn ;;
        0) exit 0 ;;
        *) warn "เมนูไม่ถูกต้อง"; sleep 1 ;;
    esac
done
