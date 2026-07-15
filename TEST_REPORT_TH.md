# รายงานทดสอบ JueVPN Thai Stable v1

วันที่ตรวจ: 15 กรกฎาคม 2026

## ผ่าน

- Bash syntax (`bash -n`) ทุกไฟล์ `.sh` และไฟล์เมนู compatibility
- Python compile (`python3 -m py_compile`) สำหรับ `jue_websocket_stable.py`
- systemd unit syntax สำหรับ Hysteria, WebSocket และ ZIVPN
- WebSocket HTTP 101 handshake
- WebSocket ส่งข้อมูลไป-กลับผ่าน TCP echo backend จริงใน local sandbox
- WebSocket graceful shutdown
- ปฏิเสธรหัส X-Pass ที่ไม่ถูกต้อง
- static scan ไม่พบ `iplogger`, `chmod 777`, `apt upgrade`, การ pipe remote script เข้า shell หรือการเขียนทับ `/etc/sysctl.conf` ในไฟล์ที่รันได้

## ยังไม่ได้ทดสอบ

- การติดตั้งจริงบน VPS ภายนอก
- การดาวน์โหลด binary จาก GitHub ระหว่างติดตั้งจริง
- พฤติกรรมของ client app Jaidee VPN/ZIVPN เมื่อสลับ Wi-Fi กับ 4G/5G
- firewall ของผู้ให้บริการ VPS และ NAT ภายนอก

ดังนั้นชุดนี้ผ่านการตรวจโค้ดและ local functional test แต่ควรทดลองบน VPS สำรองหรือ snapshot ก่อนใช้ production
