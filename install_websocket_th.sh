#!/usr/bin/env bash
# Jue WebSocket installer - Thai stable edition v1.0
set -Eeuo pipefail

INSTALL_DIR="/opt/jue_websocket"
PYTHON_PATH="$INSTALL_DIR/jue_websocket.py"
MANAGER_PATH="$INSTALL_DIR/juews_manager.sh"
STABILITY_PATH="/usr/local/sbin/juevpn-network-stability"
ENV_FILE="/etc/default/jue-websocket"
SERVICE_FILE="/etc/systemd/system/agn-websocket.service"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'
log() { echo -e "${CYAN}[JueWS]${RESET} $*"; }
ok() { echo -e "${GREEN}[สำเร็จ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[เตือน]${RESET} $*"; }
die() { echo -e "${RED}[ผิดพลาด]${RESET} $*" >&2; exit 1; }
trap 'echo -e "${RED}[ผิดพลาด]${RESET} ติดตั้งไม่สำเร็จที่บรรทัด $LINENO" >&2' ERR

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "กรุณารันด้วย sudo $0"; }

remove_service() {
    log "กำลังถอนการติดตั้ง Jue WebSocket..."
    systemctl disable --now agn-websocket.service >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE" /usr/local/bin/websocket
    rm -rf /etc/systemd/system/agn-websocket.service.d
    rm -rf "$INSTALL_DIR"
    rm -f "$ENV_FILE"
    systemctl daemon-reload
    ok "ถอนการติดตั้งแล้ว"
}

if [[ "${1:-}" == "--remove" ]]; then
    require_root
    remove_service
    exit 0
fi

require_root
[[ -f "$SCRIPT_DIR/jue_websocket_stable.py" ]] || die "ไม่พบ jue_websocket_stable.py ในโฟลเดอร์เดียวกัน"
[[ -f "$SCRIPT_DIR/juews_manager_th.sh" ]] || die "ไม่พบ juews_manager_th.sh ในโฟลเดอร์เดียวกัน"
[[ -f "$SCRIPT_DIR/network_stability_th.sh" ]] || die "ไม่พบ network_stability_th.sh ในโฟลเดอร์เดียวกัน"

log "ติดตั้งแพ็กเกจที่จำเป็น..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 ca-certificates iproute2

mkdir -p "$INSTALL_DIR" /etc/default
install -m 0755 "$SCRIPT_DIR/jue_websocket_stable.py" "$PYTHON_PATH"
install -m 0755 "$SCRIPT_DIR/juews_manager_th.sh" "$MANAGER_PATH"
install -m 0755 "$SCRIPT_DIR/network_stability_th.sh" "$STABILITY_PATH"
ln -sfn "$MANAGER_PATH" /usr/local/bin/websocket

if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<'EOF_ENV'
JUEWS_BIND=0.0.0.0
JUEWS_PORT=8098
JUEWS_PASSWORD=
JUEWS_DEFAULT_HOST=127.0.0.1:22
EOF_ENV
    chmod 0600 "$ENV_FILE"
else
    warn "พบค่าตั้งเดิม จึงเก็บไว้: $ENV_FILE"
fi

cat > "$SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=Jue WebSocket Stable Proxy
Wants=network-online.target
After=network-online.target ssh.service sshd.service
StartLimitIntervalSec=0

[Service]
Type=simple
EnvironmentFile=-$ENV_FILE
ExecStart=/usr/bin/python3 $PYTHON_PATH
Restart=always
RestartSec=2s
TimeoutStartSec=20s
TimeoutStopSec=10s
KillSignal=SIGTERM
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
"$STABILITY_PATH" >/dev/null
systemctl enable --now agn-websocket.service

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    port="$(awk -F= '$1=="JUEWS_PORT" {print $2}' "$ENV_FILE" | tail -1)"
    ufw allow "${port:-8098}/tcp" >/dev/null || true
fi

if systemctl is-active --quiet agn-websocket.service; then
    ok "WebSocket ทำงานแล้ว"
    echo "จัดการด้วยคำสั่ง: websocket menu"
else
    journalctl -u agn-websocket.service -n 30 --no-pager || true
    die "service เปิดไม่สำเร็จ"
fi
