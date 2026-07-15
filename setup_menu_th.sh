#!/usr/bin/env bash
# ติดตั้งเมนู JueVPN Thai Stable เป็นคำสั่ง juevpn
set -Eeuo pipefail

TARGET="/opt/juevpn-thai-stable"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "กรุณารันด้วย sudo $0" >&2; exit 1; }

if [[ "$SCRIPT_DIR" != "$TARGET" ]]; then
    rm -rf "$TARGET"
    mkdir -p "$TARGET"
    cp -a "$SCRIPT_DIR"/. "$TARGET"/
fi
find "$TARGET" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
chmod +x "$TARGET"/*.sh "$TARGET"/JueUDP_th "$TARGET"/menuzivpn_th "$TARGET"/jue_websocket_stable.py
ln -sfn "$TARGET/juevpn_menu_th.sh" /usr/local/bin/juevpn

echo "ติดตั้งเมนูแล้ว"
echo "เปิดด้วยคำสั่ง: sudo juevpn"
