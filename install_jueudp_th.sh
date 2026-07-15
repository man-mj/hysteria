#!/usr/bin/env bash
# JueUDP / Hysteria v1 installer - Thai stable edition v1.0
set -Eeuo pipefail

HYSTERIA_VERSION="v1.3.5"
EXECUTABLE="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
DOMAIN_FILE="$CONFIG_DIR/domain"
USER_DB="$CONFIG_DIR/udpusers.db"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
MANAGER_PATH="/usr/local/bin/jueudp_manager.sh"
STABILITY_PATH="/usr/local/sbin/juevpn-network-stability"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="eg.jueudp.com"
DOMAIN_EXPLICIT=0
UDP_PORT="36712"
OBFS="jaideevpn"
DEFAULT_USER="default"
DEFAULT_PASSWORD="jaideevpn"
LOCAL_FILE=""
PURGE=0
OPERATION="install"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'
log() { echo -e "${CYAN}[JueUDP]${RESET} $*"; }
ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
die() { echo -e "${RED}[ผิดพลาด]${RESET} $*" >&2; exit 1; }
trap 'echo -e "${RED}[ผิดพลาด]${RESET} ทำงานล้มเหลวที่บรรทัด $LINENO" >&2' ERR

usage() {
    cat <<EOF_USAGE
วิธีใช้: sudo $0 [ตัวเลือก]
  --domain NAME       โดเมนหรือ IP สำหรับ certificate (ค่าเดิม: $DOMAIN)
  --port PORT         พอร์ตภายใน UDP (ค่าเดิม: $UDP_PORT)
  --obfs TEXT         ค่า obfuscation
  --user USER         ผู้ใช้เริ่มต้น
  --password PASS     รหัสผ่านเริ่มต้น
  --local FILE        ใช้ binary Hysteria จากไฟล์ในเครื่อง
  --remove            ถอน service และ binary แต่เก็บ config/users
  --purge             ถอนทั้งหมดรวม config/users/certificate
  -h, --help          แสดงวิธีใช้
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="${2:-}"; DOMAIN_EXPLICIT=1; shift 2 ;;
        --port) UDP_PORT="${2:-}"; shift 2 ;;
        --obfs) OBFS="${2:-}"; shift 2 ;;
        --user) DEFAULT_USER="${2:-}"; shift 2 ;;
        --password) DEFAULT_PASSWORD="${2:-}"; shift 2 ;;
        --local) LOCAL_FILE="${2:-}"; shift 2 ;;
        --remove) OPERATION="remove"; shift ;;
        --purge) OPERATION="remove"; PURGE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "ไม่รู้จักตัวเลือก: $1" ;;
    esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "กรุณารันด้วย sudo"

remove_iptables_rule() {
    local port="$1" iface
    iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
    [[ -n "$iface" && "$port" =~ ^[0-9]+$ ]] || return 0
    while iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$port" 2>/dev/null; do
        iptables -w -t nat -D PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$port"
    done
}

if [[ "$OPERATION" == "remove" ]]; then
    old_port="$(jq -r '.listen // empty' "$CONFIG_FILE" 2>/dev/null | sed 's/.*://')"
    systemctl disable --now hysteria-server.service >/dev/null 2>&1 || true
    remove_iptables_rule "$old_port"
    rm -f "$SERVICE_FILE" "$EXECUTABLE" "$MANAGER_PATH" /usr/local/bin/jueudp
    rm -rf /etc/systemd/system/hysteria-server.service.d
    systemctl daemon-reload
    if [[ $PURGE -eq 1 ]]; then
        rm -rf "$CONFIG_DIR"
        ok "ถอน JueUDP และลบข้อมูลทั้งหมดแล้ว"
    else
        ok "ถอน service แล้ว โดยเก็บข้อมูลไว้ที่ $CONFIG_DIR"
    fi
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
    exit 0
fi

[[ "$UDP_PORT" =~ ^[0-9]+$ ]] && (( UDP_PORT >= 1 && UDP_PORT <= 65535 )) || die "พอร์ตไม่ถูกต้อง"
[[ "$DEFAULT_USER" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || die "ชื่อผู้ใช้ไม่ถูกต้อง"
[[ -n "$DEFAULT_PASSWORD" && "$DEFAULT_PASSWORD" != *:* && "$DEFAULT_PASSWORD" != *[[:space:]]* ]] || die "รหัสผ่านห้ามว่าง มีช่องว่าง หรือมีเครื่องหมาย :"
[[ -f "$SCRIPT_DIR/jueudp_manager_th.sh" ]] || die "ไม่พบ jueudp_manager_th.sh"
[[ -f "$SCRIPT_DIR/network_stability_th.sh" ]] || die "ไม่พบ network_stability_th.sh"

export DEBIAN_FRONTEND=noninteractive
log "ติดตั้งแพ็กเกจที่จำเป็น..."
apt-get update -y
printf 'iptables-persistent iptables-persistent/autosave_v4 boolean true\n' | debconf-set-selections
printf 'iptables-persistent iptables-persistent/autosave_v6 boolean true\n' | debconf-set-selections
apt-get install -y curl ca-certificates jq sqlite3 openssl iptables iptables-persistent iproute2

arch="$(uname -m)"
case "$arch" in
    x86_64|amd64) asset_arch="amd64" ;;
    i386|i686) asset_arch="386" ;;
    aarch64|arm64) asset_arch="arm64" ;;
    armv7l|armv7|armv6l) asset_arch="arm" ;;
    mips|mipsle|mips64|mips64le) asset_arch="mipsle" ;;
    s390x) asset_arch="s390x" ;;
    *) die "ไม่รองรับสถาปัตยกรรม $arch" ;;
esac

if [[ -n "$LOCAL_FILE" ]]; then
    [[ -f "$LOCAL_FILE" ]] || die "ไม่พบไฟล์ binary: $LOCAL_FILE"
    install -m 0755 "$LOCAL_FILE" "$EXECUTABLE"
else
    tmp_bin="$(mktemp)"
    url="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-${asset_arch}"
    log "ดาวน์โหลด Hysteria ${HYSTERIA_VERSION} สำหรับ ${asset_arch}..."
    curl -fL --retry 5 --retry-delay 3 --connect-timeout 15 "$url" -o "$tmp_bin"
    install -m 0755 "$tmp_bin" "$EXECUTABLE"
    rm -f "$tmp_bin"
fi

mkdir -p "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"
sqlite3 "$USER_DB" 'CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, password TEXT NOT NULL);'
existing_count="$(sqlite3 "$USER_DB" 'SELECT COUNT(*) FROM users;')"
if [[ "$existing_count" -eq 0 ]]; then
    sql_pass="${DEFAULT_PASSWORD//\'/\'\'}"
    sqlite3 "$USER_DB" "INSERT INTO users(username,password) VALUES('$DEFAULT_USER','$sql_pass');"
fi
chmod 0600 "$USER_DB"

users_json="$(sqlite3 -separator ':' "$USER_DB" 'SELECT username,password FROM users ORDER BY username;' | jq -R -s 'split("\n") | map(select(length > 0))')"
if [[ -f "$CONFIG_FILE" ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    existing_domain="$(jq -r '.server // empty' "$CONFIG_FILE" 2>/dev/null || true)"
    if [[ $DOMAIN_EXPLICIT -eq 0 && -n "$existing_domain" ]]; then DOMAIN="$existing_domain"; fi
    warn "พบ config เดิม จึงสำรองก่อน และล้างเฉพาะ field ฝั่ง client ที่ไม่ใช้บน server"
    jq --argjson users "$users_json" 'del(.server,.insecure,.up,.down) | .auth.config = $users' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
    jq -n \
      --arg listen ":$UDP_PORT" \
      --arg obfs "$OBFS" \
      --argjson users "$users_json" \
      '{listen:$listen,protocol:"udp",cert:"/etc/hysteria/hysteria.server.crt",key:"/etc/hysteria/hysteria.server.key",up_mbps:100,down_mbps:100,disable_udp:false,obfs:$obfs,auth:{mode:"passwords",config:$users}}' \
      > "$CONFIG_FILE"
fi
printf '%s\n' "$DOMAIN" > "$DOMAIN_FILE"
chmod 0600 "$DOMAIN_FILE"
chmod 0600 "$CONFIG_FILE"
jq empty "$CONFIG_FILE"

CERT_DOMAIN="$(cat "$DOMAIN_FILE")"
if [[ ! -s "$CONFIG_DIR/hysteria.server.crt" || ! -s "$CONFIG_DIR/hysteria.server.key" ]]; then
    log "สร้าง certificate แบบ self-signed..."
    openssl genrsa -out "$CONFIG_DIR/hysteria.ca.key" 2048 >/dev/null 2>&1
    openssl req -new -x509 -days 3650 -key "$CONFIG_DIR/hysteria.ca.key" \
      -subj "/C=TH/O=JueVPN/CN=JueVPN Root CA" -out "$CONFIG_DIR/hysteria.ca.crt" >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes -keyout "$CONFIG_DIR/hysteria.server.key" \
      -subj "/C=TH/O=JueVPN/CN=$CERT_DOMAIN" -out "$CONFIG_DIR/hysteria.server.csr" >/dev/null 2>&1
    if [[ "$CERT_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then san="IP:$CERT_DOMAIN"; else san="DNS:$CERT_DOMAIN"; fi
    openssl x509 -req -days 3650 -in "$CONFIG_DIR/hysteria.server.csr" \
      -CA "$CONFIG_DIR/hysteria.ca.crt" -CAkey "$CONFIG_DIR/hysteria.ca.key" -CAcreateserial \
      -extfile <(printf 'subjectAltName=%s\n' "$san") -out "$CONFIG_DIR/hysteria.server.crt" >/dev/null 2>&1
    chmod 0600 "$CONFIG_DIR"/*.key
else
    warn "พบ certificate เดิม จึงไม่สร้างทับ เพื่อไม่ให้ไคลเอนต์เดิมหลุด"
fi

cat > "$SERVICE_FILE" <<'EOF_SERVICE'
[Unit]
Description=JueUDP Hysteria Server
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria -c /etc/hysteria/config.json server
Restart=always
RestartSec=2s
TimeoutStartSec=30s
TimeoutStopSec=10s
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

install -m 0755 "$SCRIPT_DIR/jueudp_manager_th.sh" "$MANAGER_PATH"
ln -sfn "$MANAGER_PATH" /usr/local/bin/jueudp
install -m 0755 "$SCRIPT_DIR/network_stability_th.sh" "$STABILITY_PATH"

actual_port="$(jq -r '.listen' "$CONFIG_FILE" | sed 's/.*://')"
[[ "$actual_port" =~ ^[0-9]+$ ]] || die "ค่า listen ใน config ไม่ถูกต้อง: $actual_port"
iface="$(ip -4 route show default | awk 'NR==1 {print $5}')"
[[ -n "$iface" ]] || die "ไม่พบ network interface หลัก"
if ! iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$actual_port" 2>/dev/null; then
    iptables -w -t nat -A PREROUTING -i "$iface" -p udp --dport 10000:65000 -j DNAT --to-destination ":$actual_port"
fi
netfilter-persistent save >/dev/null 2>&1 || true

systemctl daemon-reload
"$STABILITY_PATH" >/dev/null
systemctl enable --now hysteria-server.service

if systemctl is-active --quiet hysteria-server.service; then
    ok "JueUDP ทำงานแล้วที่ UDP :$actual_port"
    echo "ช่วงพอร์ตภายนอก: UDP 10000-65000"
    echo "จัดการด้วยคำสั่ง: jueudp"
else
    journalctl -u hysteria-server.service -n 40 --no-pager || true
    die "service เปิดไม่สำเร็จ"
fi
