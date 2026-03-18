#!/bin/sh

echo "=== 正在修复网卡名称问题 ==="

# 1. 停止服务
rc-service sockd stop 2>/dev/null

# 2. 获取并清洗网卡名称 (这是修复的关键！)
# 先获取原始名称 (如 eth0@if336)
RAW_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n1)
# 去掉 @ 后面的所有内容，只保留 eth0
REAL_IFACE=$(echo "$RAW_IFACE" | cut -d@ -f1)

# 如果清洗后为空，强制设为 eth0
if [ -z "$REAL_IFACE" ]; then
    REAL_IFACE="eth0"
fi

echo "原始检测: $RAW_IFACE"
echo "修复后接口: $REAL_IFACE"

# 3. 重新写入配置文件 (使用修复后的 REAL_IFACE)
cat > /etc/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = 23040
external: $REAL_IFACE

method: username
clientmethod: none
user.notprivileged: nobody
user.libwrap: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: error
}
EOF

# 4. 确保 PAM 认证文件存在
cat > /etc/pam.d/sockd <<EOF
auth required pam_unix.so
account required pam_unix.so
EOF

# 5. 确保用户存在 (沿用你之前的用户)
# 如果你需要重置用户，取消下面这行的注释
# echo "user:password" | chpasswd

# 6. 启动服务
echo "----------------------------------------"
echo "正在启动..."
rc-update add sockd default >/dev/null 2>&1
rc-service sockd restart

# 7. 最终检查
if rc-service sockd status | grep -q "started"; then
    IP=$(curl -s4 http://ipv4.icanhazip.com)
    echo -e "\033[32m=== 修复成功！服务已启动 ===\033[0m"
    echo "公网IP:   $IP"
    echo "监听端口: 23040"
    echo "网卡接口: $REAL_IFACE"
    echo "----------------------------------------"
else
    echo -e "\033[31m=== 依然失败，请查看下方错误 ===\033[0m"
    sockd -V -f /etc/sockd.conf
fi
