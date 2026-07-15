#!/usr/bin/env bash
# Jue WebSocket Manager - Thai v1.0
set -u

SERVICE="agn-websocket.service"
ENV_FILE="/etc/default/jue-websocket"
INSTALL_DIR="/opt/jue_websocket"
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; RESET='\033[0m'

ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
error() { echo -e "${RED}[ผิดพลาด]${RESET} $*"; }
pause_menu() { read -r -n 1 -s -p "กดปุ่มใดก็ได้เพื่อกลับเมนู..."; echo; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { error "กรุณารันด้วย sudo"; exit 1; }; }

get_value() {
    local key="$1"
    [[ -f "$ENV_FILE" ]] || return 0
    awk -F= -v key="$key" '$1==key {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE"
}

write_config() {
    local bind port password default_host tmp
    bind="${1:-$(get_value JUEWS_BIND)}"
    port="${2:-$(get_value JUEWS_PORT)}"
    password="${3-$(get_value JUEWS_PASSWORD)}"
    default_host="${4:-$(get_value JUEWS_DEFAULT_HOST)}"
    tmp="$(mktemp)"
    {
        printf 'JUEWS_BIND=%s\n' "${bind:-0.0.0.0}"
        printf 'JUEWS_PORT=%s\n' "${port:-8098}"
        printf 'JUEWS_PASSWORD=%s\n' "$password"
        printf 'JUEWS_DEFAULT_HOST=%s\n' "${default_host:-127.0.0.1:22}"
    } > "$tmp"
    install -m 0600 "$tmp" "$ENV_FILE"
    rm -f "$tmp"
}

restart_service() {
    systemctl daemon-reload
    if systemctl restart "$SERVICE"; then
        sleep 1
        systemctl is-active --quiet "$SERVICE" && ok "รีสตาร์ตบริการแล้ว" || error "service ยังไม่ทำงาน"
    else
        error "รีสตาร์ตไม่สำเร็จ"
        journalctl -u "$SERVICE" -n 20 --no-pager
    fi
}

status_service() {
    echo -e "\n${CYAN}สถานะ WebSocket${RESET}"
    systemctl --no-pager --full status "$SERVICE" || true
    echo
    ss -lntp 2>/dev/null | grep -E ":$(get_value JUEWS_PORT)([[:space:]]|$)" || warn "ยังไม่พบพอร์ตที่กำลังฟัง"
}

add_ssh_user() {
    local username password
    read -r -p "ชื่อผู้ใช้ใหม่: " username
    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { error "ชื่อผู้ใช้ใช้ได้เฉพาะ a-z, 0-9, _ และ -"; return; }
    id "$username" >/dev/null 2>&1 && { error "มีผู้ใช้นี้อยู่แล้ว"; return; }
    read -r -s -p "รหัสผ่าน: " password; echo
    [[ ${#password} -ge 6 ]] || { error "รหัสผ่านต้องยาวอย่างน้อย 6 ตัว"; return; }
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    ok "เพิ่มผู้ใช้ $username แล้ว"
}

remove_ssh_user() {
    local username confirm
    read -r -p "ชื่อผู้ใช้ที่จะลบ: " username
    [[ "$username" != "root" ]] || { error "ห้ามลบ root"; return; }
    id "$username" >/dev/null 2>&1 || { error "ไม่พบผู้ใช้"; return; }
    read -r -p "ยืนยันลบ $username พร้อม home directory? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return
    userdel -r "$username"
    ok "ลบผู้ใช้แล้ว"
}

list_ssh_users() {
    echo -e "\n${CYAN}ผู้ใช้ที่มี shell สำหรับ SSH${RESET}"
    awk -F: '($3 >= 1000) && ($7 ~ /(\/bin\/bash|\/bin\/sh)$/) {printf "- %s (UID %s)\n", $1, $3}' /etc/passwd
}

manage_users() {
    while true; do
        clear
        echo -e "${CYAN}===== จัดการผู้ใช้ SSH =====${RESET}"
        echo "1) เพิ่มผู้ใช้"
        echo "2) ลบผู้ใช้"
        echo "3) แสดงรายชื่อ"
        echo "0) กลับ"
        read -r -p "เลือกเมนู: " choice
        case "$choice" in
            1) add_ssh_user; pause_menu ;;
            2) remove_ssh_user; pause_menu ;;
            3) list_ssh_users; pause_menu ;;
            0) return ;;
            *) warn "เมนูไม่ถูกต้อง"; sleep 1 ;;
        esac
    done
}

change_port() {
    local port bind password default_host
    read -r -p "พอร์ตใหม่ (1-65535): " port
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { error "พอร์ตไม่ถูกต้อง"; return; }
    bind="$(get_value JUEWS_BIND)"; password="$(get_value JUEWS_PASSWORD)"; default_host="$(get_value JUEWS_DEFAULT_HOST)"
    write_config "$bind" "$port" "$password" "$default_host"
    restart_service
}

change_password() {
    local password bind port default_host
    echo "ตั้งรหัส X-Pass เพื่ออนุญาตปลายทางภายนอก หรือเว้นว่างเพื่ออนุญาตเฉพาะ localhost"
    read -r -s -p "รหัส X-Pass ใหม่: " password; echo
    [[ "$password" =~ ^[A-Za-z0-9_.@%+=-]*$ ]] || { error "รหัสใช้ได้เฉพาะ A-Z, a-z, 0-9 และ ._@%+=-"; return; }
    bind="$(get_value JUEWS_BIND)"; port="$(get_value JUEWS_PORT)"; default_host="$(get_value JUEWS_DEFAULT_HOST)"
    write_config "$bind" "$port" "$password" "$default_host"
    restart_service
}

show_info() {
    echo -e "${CYAN}===== ข้อมูล WebSocket =====${RESET}"
    echo "Bind:         $(get_value JUEWS_BIND)"
    echo "Port:         $(get_value JUEWS_PORT)"
    echo "Default host: $(get_value JUEWS_DEFAULT_HOST)"
    if [[ -n "$(get_value JUEWS_PASSWORD)" ]]; then echo "X-Pass:       ตั้งค่าแล้ว"; else echo "X-Pass:       ไม่ได้ตั้ง (localhost เท่านั้น)"; fi
}

uninstall_service() {
    local confirm
    read -r -p "ยืนยันถอน WebSocket? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return
    systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$SERVICE" /usr/local/bin/websocket "$ENV_FILE"
    rm -rf "/etc/systemd/system/${SERVICE}.d"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    ok "ถอนการติดตั้งแล้ว"
    exit 0
}

show_menu() {
    clear
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}       JUE WEBSOCKET - เมนูภาษาไทย${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    printf "สถานะ: "
    systemctl is-active --quiet "$SERVICE" && echo -e "${GREEN}ออนไลน์${RESET}" || echo -e "${RED}ออฟไลน์${RESET}"
    echo "1) ดูสถานะละเอียด"
    echo "2) จัดการผู้ใช้ SSH"
    echo "3) เปลี่ยนพอร์ต"
    echo "4) ตั้ง/เปลี่ยนรหัส X-Pass"
    echo "5) รีสตาร์ตบริการ"
    echo "6) ดู log ล่าสุด"
    echo "7) ดูข้อมูลตั้งค่า"
    echo "8) ถอนการติดตั้ง"
    echo "0) ออก"
}

require_root
[[ "${1:-menu}" == "menu" ]] || { echo "วิธีใช้: websocket menu"; exit 0; }
while true; do
    show_menu
    read -r -p "เลือกเมนู: " choice
    case "$choice" in
        1) status_service; pause_menu ;;
        2) manage_users ;;
        3) change_port; pause_menu ;;
        4) change_password; pause_menu ;;
        5) restart_service; pause_menu ;;
        6) journalctl -u "$SERVICE" -n 80 --no-pager; pause_menu ;;
        7) show_info; pause_menu ;;
        8) uninstall_service ;;
        0) exit 0 ;;
        *) warn "เมนูไม่ถูกต้อง"; sleep 1 ;;
    esac
done
