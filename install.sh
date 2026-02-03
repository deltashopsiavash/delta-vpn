#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# DELTA VPN - WireGuard one-command installer
# For Ubuntu/Debian (apt)
# Output client config: /root/delta-client.conf
# ==========================================

if [[ $EUID -ne 0 ]]; then
  echo "[-] لطفاً با root اجرا کن: sudo ./install.sh"
  exit 1
fi

command_exists() { command -v "$1" >/dev/null 2>&1; }

echo "[+] DELTA VPN نصب شروع شد..."

if ! command_exists apt-get; then
  echo "[-] این اسکریپت برای Ubuntu/Debian نوشته شده (apt-get پیدا نشد)."
  exit 1
fi

read -rp "[?] آی‌پی عمومی یا دامنه سرور (Endpoint)؟ مثال: 1.2.3.4 یا vpn.example.com : " ENDPOINT
if [[ -z "${ENDPOINT}" ]]; then
  echo "[-] Endpoint خالیه."
  exit 1
fi

read -rp "[?] پورت WireGuard (پیشفرض 51820): " WG_PORT
WG_PORT="${WG_PORT:-51820}"

read -rp "[?] نام کلاینت (پیشفرض delta-client): " CLIENT_NAME
CLIENT_NAME="${CLIENT_NAME:-delta-client}"

echo "[+] نصب پکیج‌ها..."
apt-get update -y
apt-get install -y wireguard iptables qrencode

echo "[+] فعال‌سازی IP Forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

IFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"
if [[ -z "${IFACE}" ]]; then
  echo "[-] اینترفیس شبکه پیدا نشد."
  exit 1
fi
echo "[+] اینترفیس شبکه: ${IFACE}"

umask 077
WG_DIR="/etc/wireguard"
mkdir -p "${WG_DIR}"

SERVER_PRIV="${WG_DIR}/server.key"
SERVER_PUB="${WG_DIR}/server.pub"
CLIENT_PRIV="${WG_DIR}/${CLIENT_NAME}.key"
CLIENT_PUB="${WG_DIR}/${CLIENT_NAME}.pub"

if [[ ! -f "${SERVER_PRIV}" ]]; then
  echo "[+] ساخت کلیدهای سرور..."
  wg genkey | tee "${SERVER_PRIV}" | wg pubkey > "${SERVER_PUB}"
else
  echo "[i] کلیدهای سرور از قبل وجود دارد."
fi

if [[ ! -f "${CLIENT_PRIV}" ]]; then
  echo "[+] ساخت کلیدهای کلاینت..."
  wg genkey | tee "${CLIENT_PRIV}" | wg pubkey > "${CLIENT_PUB}"
else
  echo "[i] کلیدهای کلاینت از قبل وجود دارد."
fi

SERVER_PRIVATE_KEY="$(cat "${SERVER_PRIV}")"
SERVER_PUBLIC_KEY="$(cat "${SERVER_PUB}")"
CLIENT_PRIVATE_KEY="$(cat "${CLIENT_PRIV}")"
CLIENT_PUBLIC_KEY="$(cat "${CLIENT_PUB}")"

SERVER_ADDR="10.66.66.1/24"
CLIENT_ADDR="10.66.66.2/32"
WG_CONF="${WG_DIR}/wg0.conf"

echo "[+] ساخت کانفیگ سرور: ${WG_CONF}"
cat > "${WG_CONF}" <<EOF
[Interface]
Address = ${SERVER_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${IFACE} -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_ADDR}
EOF

chmod 600 "${WG_CONF}" "${SERVER_PRIV}" "${CLIENT_PRIV}"

echo "[+] فعال‌سازی سرویس WireGuard..."
systemctl enable wg-quick@wg0 >/dev/null
systemctl restart wg-quick@wg0

if command_exists ufw; then
  if ufw status | grep -qi "Status: active"; then
    echo "[+] UFW فعال است — باز کردن پورت ${WG_PORT}/udp"
    ufw allow "${WG_PORT}/udp" || true
  fi
fi

CLIENT_CONF_OUT="/root/${CLIENT_NAME}.conf"
echo "[+] ساخت کانفیگ کلاینت: ${CLIENT_CONF_OUT}"
cat > "${CLIENT_CONF_OUT}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = 10.66.66.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${ENDPOINT}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "${CLIENT_CONF_OUT}"

echo
echo "=============================================="
echo "[✓] نصب کامل شد!"
echo "Client Config: ${CLIENT_CONF_OUT}"
echo "Endpoint:      ${ENDPOINT}:${WG_PORT}"
echo "=============================================="
echo
echo "[i] QR برای موبایل:"
qrencode -t ansiutf8 < "${CLIENT_CONF_OUT}" || true
echo
echo "[i] وضعیت:"
echo "    sudo wg show"
echo "    sudo systemctl status wg-quick@wg0"
