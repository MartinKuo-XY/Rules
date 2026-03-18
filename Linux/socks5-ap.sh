#!/bin/sh

# 1. 彻底清理环境
rm -f /etc/sockd.conf
rc-service sockd stop 2>/dev/null

# 2. 重新安装必要组件
apk add dante-server linux-pam curl iproute2

# 3. 智能检测网卡（这是最容易出错的地方）
# 获取第一个非 loopback 的网卡名称
ETH_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n1)

# 如果检测失败，强制默认为 eth0
if [ -z "$ETH_INTERFACE" ]; then
    ETH_INTERFACE="eth0"
fi
echo "当前网卡接口: $ETH_INTERFACE"

# 4. 写入极简配置文件 (去除 user.libwrap 等可能报错的项)
cat > /etc/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = 23040
external: $ETH_INTERFACE

# 认证方式：系统用户
method: username
clientmethod: none

user.notprivileged: nobody

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

# 5. 配置 PAM 认证
cat > /etc/pam.d/sockd <<EOF
auth required pam_unix.so
account required pam_unix.so
EOF

# 6. 创建测试用户 (防止之前的用户没建成功)
id socktest >/dev/null 2>&1 || adduser -D socktest
echo "socktest:123456" | chpasswd

# 7. === 关键步骤：启动诊断 ===
echo "----------------------------------------"
echo "正在尝试启动服务..."

# 先尝试验证配置文件语法
echo "配置文件语法检查:"
sockd -V -f /etc/sockd.conf
if [ $? -ne 0 ]; then
    echo "【严重错误】配置文件语法有误，请查看上方报错！"
    exit 1
fi

# 尝试启动
rc-update add sockd default >/dev/null 2>&1
rc-service sockd restart

# 8. 如果启动失败，运行前台调试模式
if ! rc-service sockd status | grep -q "started"; then
    echo "----------------------------------------"
    echo "【启动失败】正在运行调试模式..."
    echo "请将下面出现的错误信息发给我："
    echo "----------------------------------------"
    # 在前台运行 sockd，这样就能看到它为什么挂掉了
    /usr/sbin/sockd -d 1 -N 1
else
    echo "----------------------------------------"
    echo "【成功】服务已启动！"
    echo "测试 IP: $(curl -s4 http://ipv4.icanhazip.com)"
    echo "测试端口: 23040"
    echo "测试账号: socktest"
    echo "测试密码: 123456"
    echo "----------------------------------------"
fi
