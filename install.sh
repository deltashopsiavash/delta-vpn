#!/bin/bash
set -euo pipefail

# ============================================================
#                DELTA VPN — GRE Smart Manager
# ============================================================

# ============================
# Personalization
# ============================
BRAND_NAME="DELTA VPN"
APP_NAME="Simple GRE Local Tunnel"
AUTHOR_TAG="@delta_vpn1"
GRE_NAME="gre1"
LOG_FILE="/var/log/delta-vpn-gre-manager.log"

# ============================
# Colors
# ============================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"

# Neon-ish banner colors
PINK="\033[38;5;213m"
PINK2="\033[38;5;219m"
PURPLE="\033[38;5;90m"
GRAY="\033[38;5;240m"

# Colorful buttons
BTN1="${GREEN}[ 1 ]${NC}"
BTN2="${CYAN}[ 2 ]${NC}"
BTN3="${MAGENTA}[ 3 ]${NC}"
BTN4="${BLUE}[ 4 ]${NC}"
BTN0="${YELLOW}[ 0 ]${NC}"

# ============================
# Helpers
# ============================
log() { echo "$(date '+%F %T') - $*" >> "$LOG_FILE"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}❌ Please run as root (sudo).${NC}"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}❌ Missing command: $1${NC}"
    exit 1
  }
}

# Offline-friendly local public IP guess (does NOT require internet)
get_public_ip_offline() {
  # tries to infer primary IPv4 used for routing
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

# Optional online method (commented by default)
# get_public_ip_online() { curl -fsS ipv4.icanhazip.com 2>/dev/null || true; }

THIS_PUBLIC_IP="$(get_public_ip_offline)"
THIS_PUBLIC_IP="${THIS_PUBLIC_IP:-UNKNOWN}"

# ============================
# Banner (ONE logo, layered effect by horizontal offsets)
# ============================
delta_banner() {
  local A1="██████╗ ███████╗██╗  ████████╗ █████╗     ██╗   ██╗██████╗ ███╗   ██╗"
  local A2="██╔══██╗██╔════╝██║  ╚══██╔══╝██╔══██╗    ██║   ██║██╔══██╗████╗  ██║"
  local A3="██║  ██║█████╗  ██║     ██║   ███████║    ██║   ██║██████╔╝██╔██╗ ██║"
  local A4="██║  ██║██╔══╝  ██║     ██║   ██╔══██║    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║"
  local A5="██████╔╝███████╗███████╗██║   ██║  ██║     ╚████╔╝ ██║     ██║ ╚████║"
  local A6="╚═════╝ ╚══════╝╚══════╝╚═╝   ╚═╝  ╚═╝      ╚═══╝  ╚═╝     ╚═╝  ╚═══╝"

  echo
  echo -e "${PINK2}${A1}${NC}"
  echo -e "${PINK2}${A2}${NC}"
  echo -e "${PINK2}${A3}${NC}"
  echo -e "${PINK2}${A4}${NC}"
  echo -e "${PINK2}${A5}${NC}"
  echo -e "${PINK2}${A6}${NC}"
  echo
}

# ============================
# UI
# ============================
header() {
  clear
  delta_banner
  echo -e "${CYAN}${BRAND_NAME} — ${APP_NAME}${NC}"
  echo -e "${YELLOW}GRE is NOT encrypted (GRE رمزنگاری ندارد)${NC}"
  echo
  echo -e "👤 Maintained by: ${YELLOW}${AUTHOR_TAG}${NC}"
  echo -e "📍 This server IPv4 (آیپی این سرور): ${GREEN}${THIS_PUBLIC_IP}${NC}"
  echo
}

pause() {
  echo
  read -rp "Press Enter to continue..."
}

# ============================
# GRE Functions
# ============================
status_gre() {
  echo -e "${CYAN}--- GRE Status ---${NC}"
  if ip link show "$GRE_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ $GRE_NAME is UP${NC}"
    ip -br addr show "$GRE_NAME" || true
    ip -d link show "$GRE_NAME" | sed -n '1,3p' || true
  else
    echo -e "${RED}❌ $GRE_NAME not found${NC}"
  fi
}

remove_gre() {
  echo -e "${YELLOW}⚠ Removing GRE Tunnel...${NC}"
  if ip link show "$GRE_NAME" >/dev/null 2>&1; then
    ip addr flush dev "$GRE_NAME" 2>/dev/null || true
    ip -6 addr flush dev "$GRE_NAME" 2>/dev/null || true
    ip tunnel del "$GRE_NAME" 2>/dev/null || true
    echo -e "${GREEN}✅ Removed${NC}"
    log "GRE removed"
  else
    echo -e "${RED}❌ GRE Tunnel not found${NC}"
  fi
}

create_gre() {
  echo -e "${CYAN}🌐 Enter Peer Public IP (Public IP of the other server):${NC}"
  read -rp "> " REMOTE_PUBLIC_IP

  echo -e "${CYAN}🔹 Enter Private IPv4 for THIS server (e.g., 10.50.60.1/30):${NC}"
  read -rp "> " PRIVATE_IPV4

  echo -e "${CYAN}🔹 Enter Private IPv6 for THIS server (e.g., fd00:50:60::1/126):${NC}"
  read -rp "> " PRIVATE_IPV6

  echo -e "${CYAN}🔹 Enter Peer Private IPv4 (طرف مقابل) (e.g., 10.50.60.2):${NC}"
  read -rp "> " PEER_IPV4

  echo -e "${CYAN}🔹 Enter Peer Private IPv6 (طرف مقابل) (e.g., fd00:50:60::2):${NC}"
  read -rp "> " PEER_IPV6

  echo -e "${CYAN}🔹 MTU (recommended 1400):${NC}"
  read -rp "> " MTU
  MTU="${MTU:-1400}"

  echo
  echo -e "${CYAN}📋 Summary${NC}"
  echo -e "This server Public IP : ${GREEN}${THIS_PUBLIC_IP}${NC}"
  echo -e "Peer server Public IP : ${GREEN}${REMOTE_PUBLIC_IP}${NC}"
  echo -e "This Private IPv4     : ${GREEN}${PRIVATE_IPV4}${NC}"
  echo -e "Peer Private IPv4     : ${GREEN}${PEER_IPV4}${NC}"
  echo -e "This Private IPv6     : ${GREEN}${PRIVATE_IPV6}${NC}"
  echo -e "Peer Private IPv6     : ${GREEN}${PEER_IPV6}${NC}"
  echo -e "MTU                   : ${YELLOW}${MTU}${NC}"
  echo
  read -rp "Continue? (y/n): " c
  [[ "$c" != "y" ]] && return

  echo -e "${CYAN}🚀 Creating GRE Tunnel...${NC}"

  modprobe ip_gre 2>/dev/null || true
  ip tunnel del "$GRE_NAME" 2>/dev/null || true

  ip tunnel add "$GRE_NAME" mode gre \
    local "$THIS_PUBLIC_IP" \
    remote "$REMOTE_PUBLIC_IP" \
    ttl 255

  ip link set "$GRE_NAME" up
  ip link set "$GRE_NAME" mtu "$MTU"

  # Assign addresses
  ip addr add "$PRIVATE_IPV4" dev "$GRE_NAME"
  ip -6 addr add "$PRIVATE_IPV6" dev "$GRE_NAME"

  # Enable forwarding
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

  # Allow GRE protocol in INPUT
  iptables -C INPUT -p gre -j ACCEPT 2>/dev/null || iptables -A INPUT -p gre -j ACCEPT

  echo -e "${GREEN}✅ GRE Tunnel is UP — ${BRAND_NAME}${NC}"
  log "GRE created remote=$REMOTE_PUBLIC_IP v4=$PRIVATE_IPV4 v6=$PRIVATE_IPV6 mtu=$MTU"

  echo
  echo -e "${CYAN}🔍 Connectivity tests:${NC}"

  echo -e "IPv4 -> ping ${PEER_IPV4}"
  if ping -c 3 "$PEER_IPV4" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ IPv4 tunnel reachable${NC}"
  else
    echo -e "${RED}❌ IPv4 test failed${NC}"
  fi

  echo -e "IPv6 -> ping6 ${PEER_IPV6}"
  if ping6 -c 3 "$PEER_IPV6" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ IPv6 tunnel reachable${NC}"
  else
    echo -e "${RED}❌ IPv6 test failed${NC}"
  fi

  echo
  echo -e "${YELLOW}ℹ Tip:${NC} باید سمت مقابل هم GRE ساخته شده باشد، و route/iptables درست باشد."
}

enable_bbr() {
  echo -e "${MAGENTA}🔧 Select TCP Congestion Control:${NC}"
  echo -e "  ${GREEN}1)${NC} BBR (recommended)"
  echo -e "  ${MAGENTA}2)${NC} BBR2"
  echo -e "  ${CYAN}3)${NC} Cubic (default)"
  read -rp "Your choice: " bbr

  local algo=""
  case "$bbr" in
    1) algo="bbr" ;;
    2) algo="bbr2" ;;
    3) algo="cubic" ;;
    *) echo -e "${RED}❌ Invalid choice${NC}"; return ;;
  esac

  if ! sysctl net.ipv4.tcp_available_congestion_control | grep -qw "$algo"; then
    echo -e "${RED}❌ $algo is not available on this system${NC}"
    return
  fi

  sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

  cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=$algo
EOF

  sysctl -p >/dev/null
  echo -e "${GREEN}✅ TCP Congestion Control set to $algo${NC}"
  log "TCP congestion control set to $algo"
}

# ============================
# Main
# ============================
require_root
need_cmd ip
need_cmd sysctl
need_cmd iptables

while true; do
  header
  echo -e "${BTN1} ${GREEN}Create / Rebuild GRE Tunnel${NC}   ${GRAY}(ساخت/بازسازی)${NC}"
  echo -e "${BTN2} ${CYAN}Status${NC}                      ${GRAY}(وضعیت)${NC}"
  echo -e "${BTN3} ${MAGENTA}Enable TCP BBR / BBR2 / Cubic${NC} ${GRAY}(بهینه‌سازی)${NC}"
  echo -e "${BTN4} ${RED}Remove GRE Tunnel${NC}            ${GRAY}(حذف)${NC}"
  echo -e "${BTN0} ${YELLOW}Exit${NC}                        ${GRAY}(خروج)${NC}"
  echo
  read -rp "Select an option (انتخاب): " opt

  case "$opt" in
    1) create_gre; pause ;;
    2) status_gre; pause ;;
    3) enable_bbr; pause ;;
    4) remove_gre; pause ;;
    0) echo -e "${CYAN}Bye 👋 (${BRAND_NAME})${NC}"; exit 0 ;;
    *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
  esac
done
