# JueVPN Thai Stable v1

ชุดแก้ไขจากไฟล์ที่ส่งมา โดยเน้น 3 เรื่อง:

1. เมนูและข้อความสำคัญเป็นภาษาไทย
2. แก้ path, filename, systemd และ config ที่ขัดกัน
3. เพิ่มการฟื้นตัวอัตโนมัติ, socket keepalive และค่าระบบที่ช่วยลดอาการหลุด

> ไม่มีสคริปต์ฝั่งเซิร์ฟเวอร์ใดรับประกัน “ไม่หลุด 100%” ได้ เพราะสัญญาณมือถือ, Wi-Fi, ISP, NAT และการสลับเครือข่ายอยู่เหนือการควบคุมของเซิร์ฟเวอร์ ชุดนี้ทำให้ service กลับมาเองและลดสาเหตุหลุดที่มาจากตัวเซิร์ฟเวอร์

## ระบบที่รองรับ

- Ubuntu / Debian ที่ใช้ systemd
- ต้องรันด้วย root หรือ `sudo`
- ZIVPN รองรับ x86_64, ARM64 และ ARM ตาม binary ที่ release มีให้
- JueUDP ในชุดนี้คง Hysteria v1.3.5 เพื่อรักษาความเข้ากันได้กับ config/client เดิม ไม่ได้ย้ายเป็น Hysteria 2 อัตโนมัติ

## เริ่มใช้งาน

```bash
chmod +x *.sh JueUDP_th menuzivpn_th
sudo ./setup_menu_th.sh
sudo juevpn
```

หรือไม่ติดตั้งคำสั่งก็เปิดตรงได้ด้วย `sudo ./juevpn_menu_th.sh`

## คำสั่งหลังติดตั้ง

```bash
sudo jueudp          # เมนูจัดการ JueUDP/Hysteria
sudo websocket menu # เมนูจัดการ WebSocket
sudo JueUDP          # เมนูจัดการ ZIVPN
```

## ไฟล์หลัก

- `juevpn_menu_th.sh` เมนูรวม
- `install_jueudp_th.sh` ติดตั้ง JueUDP/Hysteria
- `jueudp_manager_th.sh` จัดการบัญชี, certificate/SNI, obfs, speed และ port
- `install_websocket_th.sh` ติดตั้ง WebSocket proxy
- `jue_websocket_stable.py` proxy รุ่นแก้ keepalive/path/backlog
- `juews_manager_th.sh` จัดการ WebSocket และผู้ใช้ SSH
- `zivpn_menu_th.sh` เมนู ZIVPN ภาษาไทย
- `zivpn_install_stable_th.sh` ตัวติดตั้ง ZIVPN กลาง
- `ziv1_stable_th.sh` ช่วง UDP 20000-50000 ไป 5666
- `ziv2_stable_th.sh` ช่วง UDP 6000-19999 ไป 5667
- `network_stability_th.sh` ติดตั้ง sysctl และ systemd restart policy

## สิ่งที่ปรับเรื่องความเสถียร

- `Restart=always`, `RestartSec=2s`, `StartLimitIntervalSec=0`
- รอ `network-online.target`
- เพิ่ม `LimitNOFILE`
- TCP keepalive สำหรับ WebSocket ทั้งฝั่ง client และ target
- เพิ่ม listen backlog จากเดิมที่ต่ำผิดปกติ
- ไม่ตัด WebSocket เพียงเพราะ connection idle
- เพิ่ม UDP/TCP socket buffer แบบถาวรผ่าน `/etc/sysctl.d/99-juevpn-stability.conf`
- ใช้ iptables แบบตรวจสอบก่อนเพิ่ม ป้องกัน rule ซ้ำทุกครั้งที่ติดตั้ง
- ไม่เขียนทับ `/etc/sysctl.conf`
- ไม่สร้าง certificate ทับทุกครั้ง เพื่อไม่ให้ fingerprint เปลี่ยนและตัด client เดิม
- ไม่รัน `apt upgrade -y` โดยพลการ

## ข้อควรระวัง

- สำรอง VPS snapshot ก่อนติดตั้งจริง
- ตรวจ firewall ของผู้ให้บริการ VPS ด้วย ไม่ใช่เฉพาะ UFW/iptables
- WebSocket ที่ไม่ได้ตั้ง `X-Pass` จะอนุญาต tunnel ไปเฉพาะ localhost ซึ่งปลอดภัยกว่าค่าเปิดกว้าง
- ห้ามเปิด proxy ไปปลายทางภายนอกโดยไม่มีรหัสผ่าน
- หากแอปฝั่งมือถือไม่มี auto-reconnect การสลับ Wi-Fi/4G ยังทำให้ session หลุดได้
