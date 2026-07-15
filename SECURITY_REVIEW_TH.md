# รายงานตรวจไฟล์ต้นฉบับ

## จุดที่พบและแก้แล้ว

### `install.sh` / WebSocket

- ตัวแปร URL ของ manager ใช้คนละชื่อ ทำให้ดาวน์โหลดไม่ได้
- ดาวน์โหลดเป็น `jue_websocket.py` แต่ systemd เรียก `agn_websocket.py`
- installer ใช้ `/opt/jue_websocket` แต่ manager ใช้ `/opt/agn_websocket`
- ส่งพอร์ตเป็น positional argument ทั้งที่ Python รับ `-p/--port`
- ติดตั้ง `websocket-client` ทั้งที่โค้ดไม่ได้ใช้
- systemd ไม่มี `network-online.target`, timeout และ hardening ที่เหมาะสม

### `jue_websocket.py`

- `listen(0)` มี backlog ต่ำผิดปกติ
- ไม่มี TCP keepalive
- response `101` ปิด header ก่อน `Content-Length` ทำให้รูปแบบ HTTP ผิด
- ใช้ `send()` บางจุด จึงมีโอกาสส่งข้อมูลไม่ครบ
- ตัด connection ตามตัวนับ timeout แม้เป็น session ที่ idle ปกติ

### `install_jueudp.sh`

- service ไม่มี `Restart=always`; process ตายแล้วไม่กลับมา
- เขียนทับ `/etc/sysctl.conf` ทั้งไฟล์
- เพิ่ม iptables ซ้ำทุกครั้ง
- สร้าง certificate ทับทุกการติดตั้ง ทำให้ client เดิมมีโอกาสหลุด
- ตัวเลือกใน help บางรายการไม่มี implementation จริง
- error ตรวจ systemd บางทางไม่หยุดการติดตั้ง

### `jueudp_manager.sh`

- เมนูปนภาษาพม่า/อังกฤษ
- query SQLite ต่อ string ตรง ๆ
- เปลี่ยน `obfs.password` แต่ config ต้นฉบับเก็บ `obfs` เป็น string
- ไม่มี validation ของ username/password/port/speed
- แก้ JSON หลายรอบและไม่มี backup แบบ atomic

### `ziv1.sh` / `ziv2.sh` / `JueUDP` / `menuzivpn`

- รัน `apt upgrade -y` โดยไม่จำเป็น เสี่ยงเปลี่ยน kernel/package ระหว่างติดตั้ง
- sysctl ใช้ชั่วคราวและหายหลัง reboot
- iptables เพิ่มซ้ำ
- certificate ถูกสร้างทับ
- เมนูเรียกสคริปต์ remote โดยตรง ทำให้ไฟล์ที่รันจริงเปลี่ยนได้โดยไม่เห็น
- path และข้อความหลายส่วนผิด/ปนภาษา

## ไฟล์ `AutoScripts` — ไม่รวมเป็นตัวรันในชุดใหม่

ไฟล์นี้ไม่ใช่ส่วนหลักของ JueUDP/ZIVPN และมีพฤติกรรมเสี่ยงสูง:

- ดาวน์โหลด URL ของ `iplogger.org`
- ดาวน์โหลด executable/script หลายตัวจาก GitHub และ Dropbox แล้วรันต่อ
- ใช้ `chmod 777`
- เปลี่ยน Python alternatives หลายเวอร์ชันแบบบังคับ
- แก้ SSH port และ restart SSH
- ล้าง `.bash_history`
- ใช้ตัวแปร/URL ที่ทำให้อ่านต้นทางจริงยาก

จึงไม่ควรแค่ “แปลเมนูแล้วรันต่อ” เพราะปัญหาอยู่ที่ trust chain ไม่ใช่ภาษา ต้องมี source ของไฟล์ปลายทางทั้งหมดและ checksum ก่อนจึงจะ audit ได้ครบ
