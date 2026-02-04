#!/bin/bash
# ============================================================
#  DELTA VPN - GRE Smart Manager (Offline Friendly)
# ============================================================

set -euo pipefail

# ============================
# Personalization
# ============================
BRAND_NAME="DELTA VPN"
APP_NAME="GRE Smart Manager"
AUTHOR_TAG="@delta_vpn1"
GRE_NAME="gre1"
LOG_FILE="/var/log/delta-vpn-gre-manager.log"

# Get public IP (best-effort). If offline: UNKNOWN (no problem)
THIS_PUBLIC_IP="$(curl -fsS ipv4.icanhazip.com 2>/dev/null || echo "UNKNOWN")"

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

# Extra neon-ish colors (closer to screenshot vibe)
PINK="\033[38;5;213m"
PINK2="\033[38;5;219m"
PURPLE="\033[38;5;90m"
GRAY="\033[38;5;240m"

# Fancy menu badges (colorful buttons)
BTN1="${GREEN}[ 1 ]${NC}"
BTN2="${CYAN}[ 2 ]${NC}"
BTN3="${MAGENTA}[ 3 ]${NC}"
BTN0="${YELLOW}[ 0 ]${NC}"

# ============================
# Function: Require root
# ============================
function require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo -e "${RED}❌ Please run as root (sudo).${NC}"
        exit 1
    fi
}

# ============================
# Function: Big DELTA VPN Banner (layered, like screenshot)
# ============================
function delta_banner() {
    local A1="██████╗ ███████╗██╗  ████████╗ █████╗     ██╗   ██╗██████╗ ███╗   ██╗"
    local A2="██╔══██╗██╔════╝██║  ╚══██╔══╝██╔══██╗    ██║   ██║██╔══██╗████╗  ██║"
    local A3="██║  ██║█████╗  ██║     ██║   ███████║    ██║   ██║██████╔╝██╔██╗ ██║"
    local A4="██║  ██║██╔══╝  ██║     ██║   ██╔══██║    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║"
    local A5="██████╔╝███████╗███████╗██║   ██║  ██║     ╚████╔╝ ██║     ██║ ╚████║"
    local A6="╚═════╝ ╚══════╝╚══════╝╚═╝   ╚═╝  ╚═╝      ╚═══╝  ╚═╝     ╚═╝  ╚═══╝"

    # Shadow layers (offset-ish via leading spaces)
    printf "\n"
    printf "${PURPLE}    %s${NC}\n" "$A1"
    printf "${PURPLE}    %s${NC}\n" "$A2"
    printf "${PURPLE}    %s${NC}\n" "$A3"
    printf "${PURPLE}    %s${NC}\n" "$A4"
    printf "${PURPLE}    %s${NC}\n" "$A5"
    printf "${PURPLE}    %s${NC}\n" "$A6"

    printf "${PINK}   %s${NC}\n" "$A1"
    printf "${PINK}   %s${NC}\n" "$A2"
    printf "${PINK}   %s${NC}\n" "$A3"
    printf "${PINK}   %s${NC}\n" "$A4"
    printf "${PINK}   %s${NC}\n" "$A5"
    printf "${PINK}   %s${NC}\n" "$A6"

    printf "${PINK2}  %s${NC}\n" "$A1"
    printf "${PINK2}  %s${NC}\n" "$A2"
    printf "${PINK2}  %s${NC}\n" "$A3"
    printf "${PINK2}  %s${NC}\n" "$A4"
    printf "${PINK2}  %s${NC}\n" "$A5"
    printf "${PINK2}  %s${NC}\n" "$A6"
    printf "\n"
}

# ============================
# Function: Header (like screenshot)
# ============================
function header() {
    clear
    delta_banner
    echo -e "${CYAN}${BRAND_NAME} - Simple GRE Local Tunnel${NC}"
    echo -e "${YELLOW}GRE is NOT encrypted (GRE رمزنگاری ندارد)${NC}"
    echo
    echo -e "👤 Maintained by: ${YELLOW}${AUTHOR_TAG}${NC}"
    echo -e "📍 This server IPv4 (آیپی این سرور): ${GREEN}${THIS_PUBLIC_IP}${NC}"
    echo
}

# ============================
# Function: Enable TCP BBR / BBR2 / Cubic
# ============================
function enable_bbr() {
    echo -e "${MAGENTA}🔧 Select TCP Congestion Control:${NC}"
    echo -e "  ${GREEN}1)${NC} BBR (recommended)"
    echo -e "  ${MAGENTA}2)${NC} BBR2"
    echo -e "  ${CYAN}3)${NC} Cubic (default Linux)"
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
    echo "$(date) - [$BRAND_NAME] TCP set to $algo" >> "$LOG_FILE"
}

# ============================
# Function: Create / Rebuild GRE Tunnel
# ============================
function create_gre() {
    echo -e "🌐 Enter Public IP of the server you want to connect (Server Peer):"
    read -rp "> " REMOTE_PUBLIC_IP

    echo -e "🔹 Enter Private IPv4 for THIS server (e.g., 10.50.60.1/30):"
    read -rp "> " PRIVATE_IPV4

    echo -e "🔹 Enter Private IPv6 for THIS server (e.g., fd00:50:60::1/126):"
    read -rp "> " PRIVATE_IPV6

    echo -e "🔹 Enter MTU (recommended: 1400):"
    read -rp "> " MTU
    MTU="${MTU:-1400}"

    echo
    echo -e "${CYAN}📋 ${BRAND_NAME} Tunnel Summary${NC}"
    echo -e "This server      : ${BLUE}${THIS_PUBLIC_IP}${NC}"
    echo -e "Peer server      : ${BLUE}${REMOTE_PUBLIC_IP}${NC}"
    echo -e "Private IPv4     : ${GREEN}${PRIVATE_IPV4}${NC}"
    echo -e "Private IPv6     : ${GREEN}${PRIVATE_IPV6}${NC}"
    echo -e "MTU              : ${YELLOW}${MTU}${NC}"
    echo
    read -rp "Continue? (y/n): " c
    [[ "$c" != "y" ]] && return

    echo -e "🚀 Building GRE Tunnel..."
    modprobe ip_gre || true
    ip tunnel del "$GRE_NAME" 2>/dev/null || true

    ip tunnel add "$GRE_NAME" mode gre \
        local "$THIS_PUBLIC_IP" \
        remote "$REMOTE_PUBLIC_IP" \
        ttl 255

    ip link set "$GRE_NAME" up
    ip link set "$GRE_NAME" mtu "$MTU"

    ip addr add "$PRIVATE_IPV4" dev "$GRE_NAME"
    ip -6 addr add "$PRIVATE_IPV6" dev "$GRE_NAME"

    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

    iptables -C INPUT -p gre -j ACCEPT 2>/dev/null || iptables -A INPUT -p gre -j ACCEPT

    echo -e "${GREEN}✅ GRE Tunnel is UP — powered by ${BRAND_NAME}${NC}"
    ip addr show "$GRE_NAME"
    echo "$(date) - [$BRAND_NAME] GRE Tunnel created for $REMOTE_PUBLIC_IP" >> "$LOG_FILE"

    echo
    echo -e "🔍 Quick tests (basic reachability)..."

    local LOCAL_IPV4 LOCAL_IPV6
    LOCAL_IPV4="$(echo "$PRIVATE_IPV4" | cut -d/ -f1)"
    LOCAL_IPV6="$(echo "$PRIVATE_IPV6" | cut -d/ -f1)"

    echo -e "🌐 Pinging via IPv4..."
    if ping -c 3 "$LOCAL_IPV4" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ IPv4 reachable${NC}"
    else
        echo -e "${RED}❌ IPv4 test failed${NC}"
    fi

    echo -e "🌐 Pinging via IPv6..."
    if ping6 -c 3 "$LOCAL_IPV6" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ IPv6 reachable${NC}"
    else
        echo -e "${RED}❌ IPv6 test failed${NC}"
    fi

    echo
    echo -e "${YELLOW}ℹ Tip:${NC} اگر سمت مقابل هم GRE ساخته نشده باشه، تست‌ها ممکنه fail بشن."
}

# ============================
# Function: Remove GRE Tunnel
# ============================
function remove_gre() {
    echo -e "⚠ Removing GRE Tunnel..."
    if ip link show "$GRE_NAME" >/dev/null 2>&1; then
        ip addr flush dev "$GRE_NAME"
        ip tunnel del "$GRE_NAME"
        echo -e "${YELLOW}🗑 GRE Tunnel removed${NC}"
        echo "$(date) - [$BRAND_NAME] GRE Tunnel removed" >> "$LOG_FILE"
    else
        echo -e "${RED}❌ GRE Tunnel not found${NC}"
    fi
}

# ============================
# Main
# ============================
require_root

while true; do
    header
    echo -e "${BTN1} ${GREEN}Create / Rebuild GRE Tunnel${NC}  ${GRAY}(ساخت/بازسازی)${NC}"
    echo -e "${BTN2} ${CYAN}Remove GRE Tunnel${NC}           ${GRAY}(حذف)${NC}"
    echo -e "${BTN3} ${MAGENTA}Enable TCP BBR / BBR2 / Cubic${NC} ${GRAY}(بهینه‌سازی)${NC}"
    echo -e "${BTN0} ${YELLOW}Exit${NC}                        ${GRAY}(خروج)${NC}"
    echo
    read -rp "Select an option (انتخاب): " opt

    case "$opt" in
        1) create_gre ;;
        2) remove_gre ;;
        3) enable_bbr ;;
        0) echo -e "${CYAN}Bye 👋 (${BRAND_NAME})${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
    esac

    echo
    read -rp "Press Enter to continue..."
done
