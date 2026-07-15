#!/usr/bin/env bash
# ZIVPN UDP installer - Thai stable edition v1.0
set -Eeuo pipefail

VARIANT="2"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="$CONFIG_DIR/config.json"
EXECUTABLE="/usr/local/bin/zivpn"
SERVICE_FILE="/etc/systemd/system/zivpn.service"
MENU_PATH="/usr/local/bin/zivpn-menu"
STABILITY_PATH="/usr/local/sbin/juevpn-network-stability"
TOOLS_DIR="/opt/juevpn-tools"
RELEASE="udp-zivpn_1.4.9"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'
log() { echo -e "${CYAN}[ZIVPN]${RESET} $*"; }
ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
die() { echo -e "${RED}[ผิดพลาด]${RESET} $*" >&2; exit 1; }
trap 'echo -e "${RED}[ผิดพลาด]${RESET} ติดตั้งไม่สำเร็จที่บรรทัด $LINENO" >&2' ERR

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:-}"; shift 2 ;;
        -h|--help) echo "วิธีใช้: sudo $0 --variant 1|2"; exit 0 ;;
        *) die "ไม่รู้จักตัวเลือก $1" ;;
    esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "กรุณารันด้วย sudo"
[[ "$VARIANT" == "1" || "$VARIANT" == "2" ]] || die "variant ต้องเป็น 1 หรือ 2"
[[ -f "$SCRIPT_DIR/zivpn_menu_th.sh" ]] || die "ไม่พบ zivpn_menu_th.sh"
[[ -f "$SCRIPT_DIR/network_stability_th.sh" ]] || die "ไม่พบ network_stability_th.sh"

if [[ "$VARIANT" == "1" ]]; then
    INTERNAL_PORT=5666
    EXTERNAL_RANGE="20000:50000"
else
    INTERNAL_PORT=5667
    EXTERNAL_RANGE="6000:19999"
fi

export DEBIAN_FRONTEND=noninteractive
log "ติดตั้งแพ็กเกจที่จำเป็น..."
apt-get update -y
printf 'iptables-persistent iptables-persistent/autosave_v4 boolean true\n' | debconf-set-selections
printf 'iptables-persistent iptables-persistent/autosave_v6 boolean true\n' | debconf-set-selections
apt-get install -y curl ca-certificates jq openssl iptables iptables-persistent iproute2

case "$(uname -m)" in
    x86_64|amd64) asset_arch="amd64" ;;
    aarch64|arm64) asset_arch="arm64" ;;
    armv7l|armv7|armv6l) asset_arch="arm" ;;
    *) die "ZIVPN ชุดนี้ไม่รองรับสถาปัตยกรรม $(uname -m)" ;;
esac

systemctl stop zivpn.service >/dev/null 2>&1 || true
tmp_bin="$(mktemp)"
url="https://github.com/zahidbd2/udp-zivpn/releases/download/${RELEASE}/udp-zivpn-linux-${asset_arch}"
log "ดาวน์โหลด ZIVPN ${RELEASE} สำหรับ ${asset_arch}..."
curl -fL --retry 5 --retry-delay 3 --connect-timeout 15 "$url" -o "$tmp_bin"
install -m 0755 "$tmp_bin" "$EXECUTABLE"
rm -f "$tmp_bin"

mkdir -p "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
fi

read -r -p "รหัสผ่าน UDP คั่นด้วย comma [ค่าเริ่มต้น: zi]: " input_config
input_config="${input_config:-zi}"
passwords_json="$(jq -n --arg value "$input_config" '$value | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))')"
count="$(jq 'length' <<<"$passwords_json")"
(( count > 0 )) || die "ต้องมีรหัสผ่านอย่างน้อย 1 ค่า"
if jq -e 'any(.[]; test("[:[:space:]]"))' <<<"$passwords_json" >/dev/null; then
    die "รหัสผ่านห้ามมีเครื่องหมาย : หรือช่องว่าง"
fi

jq -n \
  --arg listen ":$INTERNAL_PORT" \
  --argjson passwords "$passwords_json" \
  '{listen:$listen,cert:"/etc/zivpn/zivpn.crt",key:"/etc/zivpn/zivpn.key",obfs:"zivpn",auth:{mode:"passwords",config:$passwords}}' \
  > "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"
jq empty "$CONFIG_FILE"

if [[ ! -s "$CONFIG_DIR/zivpn.crt" || ! -s "$CONFIG_DIR/zivpn.key" ]]; then
    log "สร้าง certificate ใหม่..."
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
      -subj "/C=TH/O=JueVPN/CN=zivpn" \
      -keyout "$CONFIG_DIR/zivpn.key" -out "$CONFIG_DIR/zivpn.crt" >/dev/null 2>&1
    chmod 0600 "$CONFIG_DIR/zivpn.key"
else
    warn "พบ certificate เดิม จึงไม่สร้างทับ"
fi

cat > "$SERVICE_FILE" <<'EOF_SERVICE'
[Unit]
Description=ZIVPN UDP Server
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=2s
TimeoutStartSec=30s
TimeoutStopSec=10s
LimitNOFILE=1048576
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

mkdir -p "$TOOLS_DIR"
install -m 0755 "$SCRIPT_DIR/zivpn_menu_th.sh" "$TOOLS_DIR/zivpn_menu_th.sh"
install -m 0755 "$SCRIPT_DIR/zivpn_install_stable_th.sh" "$TOOLS_DIR/zivpn_install_stable_th.sh"
install -m 0755 "$SCRIPT_DIR/ziv1_stable_th.sh" "$TOOLS_DIR/ziv1_stable_th.sh"
install -m 0755 "$SCRIPT_DIR/ziv2_stable_th.sh" "$TOOLS_DIR/ziv2_stable_th.sh"
install -m 0755 "$SCRIPT_DIR/network_stability_th.sh" "$TOOLS_DIR/network_stability_th.sh"
install -m 0755 "$SCRIPT_DIR/zivpn_menu_th.sh" "$MENU_PATH"
ln -sfn "$MENU_PATH" /usr/local/bin/JueUDP
install -m 0755 "$SCRIPT_DIR/network_stability_th.sh" "$STABILITY_PATH"

iface="$(ip -4 route show default | awk 'NR==1 {print $5}')"
[[ -n "$iface" ]] || die "ไม่พบ network interface หลัก"
remove_rule() {
    local range="$1" port="$2"
    while iptables -w -t nat -C PREROUTING -i "$iface" -p udp --dport "$range" -j DNAT --to-destination ":$port" 2>/dev/null; do
        iptables -w -t nat -D PREROUTING -i "$iface" -p udp --dport "$range" -j DNAT --to-destination ":$port"
    done
}
remove_rule "20000:50000" 5666
remove_rule "6000:19999" 5667
iptables -w -t nat -A PREROUTING -i "$iface" -p udp --dport "$EXTERNAL_RANGE" -j DNAT --to-destination ":$INTERNAL_PORT"
netfilter-persistent save >/dev/null 2>&1 || true

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$EXTERNAL_RANGE/udp" >/dev/null || true
    ufw allow "$INTERNAL_PORT/udp" >/dev/null || true
fi

systemctl daemon-reload
"$STABILITY_PATH" >/dev/null
systemctl enable --now zivpn.service

if systemctl is-active --quiet zivpn.service; then
    ok "ZIVPN ออนไลน์แล้ว"
    echo "พอร์ตภายนอก UDP: $EXTERNAL_RANGE"
    echo "พอร์ตภายใน: $INTERNAL_PORT"
    echo "จัดการด้วยคำสั่ง: JueUDP"
else
    journalctl -u zivpn.service -n 40 --no-pager || true
    die "service เปิดไม่สำเร็จ"
fi
