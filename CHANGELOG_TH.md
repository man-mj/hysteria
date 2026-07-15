# Changelog

## v1.0

- แปลเมนู JueUDP, WebSocket และ ZIVPN เป็นภาษาไทย
- เพิ่มเมนูรวม `juevpn_menu_th.sh`
- แก้ path/filename ของ WebSocket ให้ตรงกัน
- เขียน WebSocket proxy ใหม่บน Python standard library
- เพิ่ม TCP keepalive, backlog, graceful shutdown และ `sendall`
- เพิ่ม systemd auto-restart และ network-online dependency
- ย้าย tuning ไป `/etc/sysctl.d/99-juevpn-stability.conf`
- ทำ firewall rule แบบ idempotent และ persist
- ป้องกัน certificate ถูกสร้างทับโดยไม่จำเป็น
- เพิ่ม validation และ atomic JSON update ใน manager
- ตัด `apt upgrade -y` และ dependency ที่ไม่ใช้
- แยก `AutoScripts` ออกจาก runnable bundle เนื่องจาก audit พบพฤติกรรมเสี่ยง
