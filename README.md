<div align="center">

# 🚀 DELTA VPN

### Fast • Clean • Self-Hosted WireGuard VPN

[![WireGuard](https://img.shields.io/badge/VPN-WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)](https://www.wireguard.com/)
![Linux](https://img.shields.io/badge/Linux-Ubuntu%20%7C%20Debian-111?style=for-the-badge&logo=linux&logoColor=white)

</div>

---

## ✨ چی هست؟
**DELTA VPN** یک اسکریپت ساده و شیک برای راه‌اندازی **WireGuard VPN** روی سرورهای Ubuntu/Debian است.
- نصب خودکار WireGuard
- ساخت کلیدها
- ساخت کانفیگ سرور
- ساخت کانفیگ کلاینت (فایل `.conf`)
- فعال‌سازی IP Forwarding و NAT

---

## ✅ پیش‌نیازها
- سرور **Ubuntu 20.04+** یا **Debian 11+**
- دسترسی `root` یا `sudo`
- یک آی‌پی عمومی یا دامنه

---

## ⚡ نصب با یک دستور (مثل نمونه‌ای که دادی)

### 1) دانلود اسکریپت:
```bash
wget https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/delta-vpn/main/install.sh -O delta-vpn.sh
