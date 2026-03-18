echo 'Iy!/bin/sh
# Alpine SOCKS5 Auto Installer (Base64 Encoded to prevent copy-paste errors)

set -e
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
NC="\033[0m"

SERVICE="sockd"
CONF="/etc/sockd.conf"
PAM="/etc/pam.d/sockd"

# 1. Check Root
if [ "$(id -u)" != "0" ]; then echo "Root required"; exit 1; fi

# 2. Install Deps
echo -e "${BLUE}Installing dependencies...${NC}"
grep -q "community" /etc/apk/repositories || echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
apk update
apk add dante-server openssl linux-pam curl iproute2

# 3. Fix Service Name (Alpine uses sockd, not dante)
if [ ! -f /etc/init.d/sockd ] && [ -f /etc/init.d/dante ]; then
    ln -s /etc/init.d/dante /etc/init.d/sockd
fi

# 4. Input Info
echo -e "${GREEN}--- Configuration ---${NC}"
printf "Port [1080]: "; read p; PORT=${p:-1080}
printf "User [user]: "; read u; USER=${u:-user}
PW=$(openssl rand -base64 6); printf "Pass [$PW]: "; read w; PASS=${w:-$PW}

# 5. Create User
id "$USER" >/dev/null 2>&1 || adduser -D "$USER"
echo "$USER:$PASS" | chpasswd

# 6. Configure PAM
cat > "$PAM" <<ENDPAM
auth required pam_unix.so
account required pam_unix.so
ENDPAM

# 7. Configure Dante
IFACE=$(ip route | grep default | awk "{print \$5}" | head -n1)
[ -z "$IFACE" ] && IFACE=eth0

cat > "$CONF" <<ENDCONF
logoutput: syslog
user.notprivileged: nobody
user.libwrap: nobody
method: username
clientmethod: none
internal: 0.0.0.0 port = $PORT
external: $IFACE
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
pass { from: 0.0.0.0/0 to: 0.0.0.0/0 protocol: tcp udp log: error }
ENDCONF

# 8. Start Service
echo -e "${BLUE}Starting Service...${NC}"
rc-update add $SERVICE default >/dev/null 2>&1 || true
rc-service $SERVICE restart

# 9. Show Info
IP=$(curl -s4 http://ipv4.icanhazip.com 2>/dev/null)
echo -e "\n${GREEN}=== SOCKS5 Installed ===${NC}"
echo "IP:   $IP"
echo "Port: $PORT"
echo "User: $USER"
echo "Pass: $PASS"
echo -e "${GREEN}========================${NC}"
' > alpine_socks.sh && chmod +x alpine_socks.sh && ./alpine_socks.sh
