#!/usr/bin/env bash
# JueUDP Manager - Thai stable edition v1.0
set -u

CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
DOMAIN_FILE="$CONFIG_DIR/domain"
USER_DB="$CONFIG_DIR/udpusers.db"
SERVICE="hysteria-server.service"
STABILITY="/usr/local/sbin/juevpn-network-stability"
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; RESET='\033[0m'

ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
error() { echo -e "${RED}[ผิดพลาด]${RESET} $*"; }
pause_menu() { read -r -n 1 -s -p "กดปุ่มใดก็ได้เพื่อกลับเมนู..."; echo; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { error "กรุณารันด้วย sudo"; exit 1; }; }
sql_escape() { printf '%s' "${1//\'/\'\'}"; }
validate_username() { [[ "$1" =~ ^[A-Za-z0-9_.-]{1,32}$ ]]; }
validate_password() { [[ -n "$1" && "$1" != *:* && "$1" != *[[:space:]]* && ${#1} -le 128 ]]; }

atomic_jq() {
    local filter="$1"; shift
    local tmp backup
    tmp="$(mktemp "$CONFIG_DIR/config.XXXXXX")"
    backup="${CONFIG_FILE}.bak"
    cp -a "$CONFIG_FILE" "$backup"
    if jq "$@" "$filter" "$CONFIG_FILE" > "$tmp" && jq empty "$tmp"; then
        chmod --reference="$CONFIG_FILE" "$tmp" 2>/dev/null || chmod 0600 "$tmp"
        mv "$tmp" "$CONFIG_FILE"
    else
        rm -f "$tmp"
        error "แก้ config ไม่สำเร็จ"
        return 1
    fi
}

users_json() {
    sqlite3 -separator ':' "$USER_DB" 'SELECT username,password FROM users ORDER BY username;' \
      | jq -R -s 'split("\n") | map(select(length > 0))'
}

update_user_config() {
    local data
    data="$(users_json)" || return 1
    atomic_jq '.auth.config = $users' --argjson users "$data"
}

restart_server() {
    jq empty "$CONFIG_FILE" || { error "config JSON ไม่ถูกต้อง จึงไม่รีสตาร์ต"; return 1; }
    if systemctl restart "$SERVICE"; then
        sleep 1
        systemctl is-active --quiet "$SERVICE" && ok "รีสตาร์ตเซิร์ฟเวอร์แล้ว" || error "service ยังไม่ออนไลน์"
    else
        error "รีสตาร์ตไม่สำเร็จ"
        journalctl -u "$SERVICE" -n 30 --no-pager
        return 1
    fi
}

add_user() {
    local username password u p
    read -r -p "ชื่อผู้ใช้ใหม่: " username
    validate_username "$username" || { error "ชื่อผู้ใช้ใช้ได้เฉพาะ A-Z, a-z, 0-9, _, . และ -"; return; }
    read -r -s -p "รหัสผ่าน: " password; echo
    validate_password "$password" || { error "รหัสห้ามว่าง มีช่องว่าง หรือมีเครื่องหมาย :"; return; }
    u="$(sql_escape "$username")"; p="$(sql_escape "$password")"
    if sqlite3 "$USER_DB" "INSERT INTO users(username,password) VALUES('$u','$p');"; then
        update_user_config && restart_server
        ok "เพิ่มบัญชี $username แล้ว"
    else
        error "เพิ่มบัญชีไม่สำเร็จ อาจมีชื่อซ้ำ"
    fi
}

edit_user() {
    local username password u p changes
    read -r -p "ชื่อผู้ใช้ที่จะแก้: " username
    validate_username "$username" || { error "ชื่อผู้ใช้ไม่ถูกต้อง"; return; }
    read -r -s -p "รหัสผ่านใหม่: " password; echo
    validate_password "$password" || { error "รหัสผ่านไม่ถูกต้อง"; return; }
    u="$(sql_escape "$username")"; p="$(sql_escape "$password")"
    changes="$(sqlite3 "$USER_DB" "UPDATE users SET password='$p' WHERE username='$u'; SELECT changes();")"
    [[ "$changes" == "1" ]] || { error "ไม่พบบัญชี $username"; return; }
    update_user_config && restart_server
    ok "เปลี่ยนรหัสผ่านแล้ว"
}

delete_user() {
    local username u count confirm changes
    count="$(sqlite3 "$USER_DB" 'SELECT COUNT(*) FROM users;')"
    (( count > 1 )) || { error "ต้องเหลืออย่างน้อย 1 บัญชี"; return; }
    read -r -p "ชื่อผู้ใช้ที่จะลบ: " username
    validate_username "$username" || { error "ชื่อผู้ใช้ไม่ถูกต้อง"; return; }
    read -r -p "ยืนยันลบ $username? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return
    u="$(sql_escape "$username")"
    changes="$(sqlite3 "$USER_DB" "DELETE FROM users WHERE username='$u'; SELECT changes();")"
    [[ "$changes" == "1" ]] || { error "ไม่พบบัญชี"; return; }
    update_user_config && restart_server
    ok "ลบบัญชีแล้ว"
}

show_users() {
    echo -e "\n${CYAN}บัญชี JueUDP ทั้งหมด${RESET}"
    sqlite3 -header -column "$USER_DB" 'SELECT username AS USERNAME FROM users ORDER BY username;'
}

regenerate_cert() {
    local domain="$1" san
    openssl genrsa -out "$CONFIG_DIR/hysteria.ca.key" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 -key "$CONFIG_DIR/hysteria.ca.key" -subj "/C=TH/O=JueVPN/CN=JueVPN Root CA" -out "$CONFIG_DIR/hysteria.ca.crt" >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes -keyout "$CONFIG_DIR/hysteria.server.key" -subj "/C=TH/O=JueVPN/CN=$domain" -out "$CONFIG_DIR/hysteria.server.csr" >/dev/null 2>&1
    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then san="IP:$domain"; else san="DNS:$domain"; fi
    openssl x509 -req -days 3650 -in "$CONFIG_DIR/hysteria.server.csr" -CA "$CONFIG_DIR/hysteria.ca.crt" -CAkey "$CONFIG_DIR/hysteria.ca.key" -CAcreateserial -extfile <(printf 'subjectAltName=%s\n' "$san") -out "$CONFIG_DIR/hysteria.server.crt" >/dev/null 2>&1
    chmod 0600 "$CONFIG_DIR"/*.key
}

change_domain() {
    local domain confirm
    read -r -p "โดเมนหรือ IP ใหม่สำหรับ certificate/SNI: " domain
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || { error "รูปแบบโดเมน/IP ไม่ถูกต้อง"; return; }
    printf '%s\n' "$domain" > "$DOMAIN_FILE"
    chmod 0600 "$DOMAIN_FILE"
    read -r -p "สร้าง certificate ใหม่ให้ $domain ด้วยหรือไม่? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[nN]$ ]]; then regenerate_cert "$domain"; fi
    restart_server
}

change_obfs() {
    local obfs
    read -r -p "ค่า Obfuscation ใหม่: " obfs
    [[ -n "$obfs" && "$obfs" != *[[:space:]]* ]] || { error "ค่าไม่ถูกต้อง"; return; }
    atomic_jq 'if (.obfs|type)=="object" then .obfs.password=$obfs else .obfs=$obfs end' --arg obfs "$obfs" || return
    restart_server
}

change_speed() {
    local direction value
    direction="$1"
    read -r -p "ความเร็วใหม่ (Mbps): " value
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 100000 )) || { error "ค่าความเร็วไม่ถูกต้อง"; return; }
    if [[ "$direction" == "up" ]]; then
        atomic_jq '.up_mbps=$v | del(.up)' --argjson v "$value" || return
    else
        atomic_jq '.down_mbps=$v | del(.down)' --argjson v "$value" || return
    fi
    restart_server
}

persist_firewall() { command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true; }

change_port() {
    local old_port new_port iface
    old_port="$(jq -r '.listen' "$CONFIG_FILE" | sed 's/.*://')"
    read -r -p "พอร์ต UDP ภายในใหม่: " new_port
    [[ "$new_port" =~ ^[0-9]+$ ]] && (( new_port >= 1 && new_port <= 65535 )) || { error "พอร์ตไม่ถูกต้อง"; return; }
    iface="$(ip -4 route show default | awk 'NR==1 {print $5}')"
    [[ -n "$iface" ]] || { error "ไม่พบ interface หลัก"; return; }
    atomic_jq '.listen = (":" + ($port|tostring))' --argjson port "$new_port" || return
    while iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$old_port" 2>/dev/null; do
        iptables -w -t nat -D PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$old_port"
    done
    iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$new_port" 2>/dev/null \
      || iptables -w -t nat -A PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$new_port"
    persist_firewall
    restart_server
}

status_server() {
    systemctl --no-pager --full status "$SERVICE" || true
    echo
    ss -lunp 2>/dev/null | grep -E ":$(jq -r '.listen' "$CONFIG_FILE" | sed 's/.*://')([[:space:]]|$)" || warn "ยังไม่พบพอร์ต UDP ที่กำลังฟัง"
}

show_info() {
    echo -e "${CYAN}===== ข้อมูล JueUDP =====${RESET}"
    echo "Domain/SNI:    $(cat "$DOMAIN_FILE" 2>/dev/null || echo "-")"
    echo "Listen:        $(jq -r '.listen // "-"' "$CONFIG_FILE")"
    echo "Obfs:          $(jq -r 'if (.obfs|type)=="object" then .obfs.password else .obfs end' "$CONFIG_FILE")"
    echo "Upload:        $(jq -r '.up_mbps // "-"' "$CONFIG_FILE") Mbps"
    echo "Download:      $(jq -r '.down_mbps // "-"' "$CONFIG_FILE") Mbps"
    echo "Users:         $(sqlite3 "$USER_DB" 'SELECT COUNT(*) FROM users;')"
}

uninstall_server() {
    local confirm mode port iface
    read -r -p "ยืนยันถอน JueUDP? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return
    port="$(jq -r '.listen // empty' "$CONFIG_FILE" 2>/dev/null | sed 's/.*://')"
    iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    if [[ -n "$iface" && "$port" =~ ^[0-9]+$ ]]; then
        while iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$port" 2>/dev/null; do
            iptables -w -t nat -D PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$port"
        done
    fi
    read -r -p "พิมพ์ PURGE เพื่อลบ config/users ด้วย หรือ Enter เพื่อเก็บไว้: " mode
    systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/hysteria-server.service /usr/local/bin/hysteria /usr/local/bin/jueudp /usr/local/bin/jueudp_manager.sh
    rm -rf /etc/systemd/system/hysteria-server.service.d
    [[ "$mode" == "PURGE" ]] && rm -rf "$CONFIG_DIR"
    systemctl daemon-reload
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
    ok "ถอนการติดตั้งแล้ว"
    exit 0
}

show_menu() {
    clear
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}          JUEUDP - เมนูภาษาไทย${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    printf "สถานะ: "
    systemctl is-active --quiet "$SERVICE" && echo -e "${GREEN}ออนไลน์${RESET}" || echo -e "${RED}ออฟไลน์${RESET}"
    echo "1) เพิ่มบัญชี"
    echo "2) เปลี่ยนรหัสผ่านบัญชี"
    echo "3) ลบบัญชี"
    echo "4) ดูบัญชีทั้งหมด"
    echo "5) เปลี่ยนโดเมน/IP"
    echo "6) เปลี่ยน Obfuscation"
    echo "7) เปลี่ยน Upload speed"
    echo "8) เปลี่ยน Download speed"
    echo "9) เปลี่ยนพอร์ต UDP ภายใน"
    echo "10) ดูสถานะละเอียด"
    echo "11) รีสตาร์ตเซิร์ฟเวอร์"
    echo "12) ดู log ล่าสุด"
    echo "13) ดูข้อมูลตั้งค่า"
    echo "14) ใช้ค่าปรับเสถียรภาพอีกครั้ง"
    echo "15) ถอนการติดตั้ง"
    echo "0) ออก"
}

require_root
[[ -f "$CONFIG_FILE" && -f "$USER_DB" ]] || { error "ยังไม่ได้ติดตั้ง JueUDP"; exit 1; }
while true; do
    show_menu
    read -r -p "เลือกเมนู: " choice
    case "$choice" in
        1) add_user; pause_menu ;;
        2) edit_user; pause_menu ;;
        3) delete_user; pause_menu ;;
        4) show_users; pause_menu ;;
        5) change_domain; pause_menu ;;
        6) change_obfs; pause_menu ;;
        7) change_speed up; pause_menu ;;
        8) change_speed down; pause_menu ;;
        9) change_port; pause_menu ;;
        10) status_server; pause_menu ;;
        11) restart_server; pause_menu ;;
        12) journalctl -u "$SERVICE" -n 100 --no-pager; pause_menu ;;
        13) show_info; pause_menu ;;
        14) [[ -x "$STABILITY" ]] && "$STABILITY" || error "ไม่พบสคริปต์ปรับเสถียรภาพ"; pause_menu ;;
        15) uninstall_server ;;
        0) exit 0 ;;
        *) warn "เมนูไม่ถูกต้อง"; sleep 1 ;;
    esac
done
