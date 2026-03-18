# 1. 强制清理旧文件
rm -f alpine_socks.sh socks5.sh

# 2. 写入修正后的脚本 (使用单引号EOF防止截断和变量提前解析)
cat > alpine_socks.sh << 'EOF'
#!/bin/sh
# Alpine Dante Installer - Debug Version
# 遇到任何错误不退出，以便显示调试信息

# --- 颜色 ---
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

echo "=== 开始安装/修复 Dante Socks5 ==="

# 1. 确保安装依赖
echo "-> 检查依赖..."
if ! grep -q "community" /etc/apk/repositories; then
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
fi
apk update >/dev/null
apk add dante-server openssl linux-pam curl iproute2 >/dev/null

# 2. 智能检测网卡 (这是最容易出错的地方)
echo "-> 检测网卡..."
# 使用 ip route get 8.8.8.8 是最准确的方法
IFACE=$(ip route get 8.8.8.8 | grep -o "dev.*" | cut -d " " -f 2)
if [ -z "$IFACE" ]; then
    # 备用方案
    IFACE=$(ip link | grep 'state UP' | awk -F: '{print $2}' | head -n1 | tr -d ' ')
fi
echo "   检测到出口网卡: $IFACE"

if [ -z "$IFACE" ]; then
    echo -e "${RED}错误：无法自动检测网卡，服务将无法启动！${NC}"
    echo "请手动编辑 /etc/sockd.conf 将 'external:' 改为正确的网卡名"
fi

# 3. 收集用户信息
printf "请输入端口 [默认 1080]: "
read p
PORT=${p:-1080}

printf "请输入用户名 [默认 user]: "
read u
USER=${u:-user}

PW=$(openssl rand -base64 8)
printf "请输入密码 [默认随机]: "
read w
PASS=${w:-$PW}

# 4. 创建用户
id "$USER" >/dev/null 2>&1 || adduser -D "$USER"
echo "$USER:$PASS" | chpasswd
echo "-> 用户 $USER 配置完成"

# 5. 配置 PAM (认证关键)
cat > /etc/pam.d/sockd <<ENDPAM
auth required pam_unix.so
account required pam_unix.so
ENDPAM

# 6. 写入配置文件 (移除可能导致错误的 libwrap)
cat > /etc/sockd.conf <<ENDCONF
logoutput: syslog /var/log/sockd.log
user.notprivileged: nobody

# 认证模式
method: username
clientmethod: none

internal: 0.0.0.0 port = $PORT
external: $IFACE

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: error
}
ENDCONF

# 7. 启动服务与诊断
echo "-> 正在启动 sockd 服务..."
rc-update add sockd default >/dev/null 2>&1
rc-service sockd restart

# 8. 检查状态
if rc-service sockd status | grep -q "started"; then
    IP=$(curl -s4 http://ipv4.icanhazip.com)
    echo -e "\n${GREEN}=== 安装成功！===${NC}"
    echo "IP:   $IP"
    echo "Port: $PORT"
    echo "User: $USER"
    echo "Pass: $PASS"
    echo -e "${GREEN}===================${NC}"
else
    echo -e "\n${RED}=== 启动失败，开始诊断 ===${NC}"
    echo "1. 尝试前台运行以查看错误信息："
    # 这一步会直接把错误打印在屏幕上
    sockd -V -f /etc/sockd.conf
    
    echo -e "\n2. 查看日志文件内容："
    tail -n 10 /var/log/sockd.log 2>/dev/null
    
    echo -e "${RED}请截图上述错误信息以便排查。${NC}"
fi
EOF

# 3. 赋予权限并运行
chmod +x alpine_socks.sh
./alpine_socks.sh
