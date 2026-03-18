# 1. 清理旧文件，防止混淆
rm -f alpine_socks.sh socks5.sh

# 2. 写入修正后的脚本内容
cat > alpine_socks.sh << 'EOF'
#!/bin/sh
# Dante-server SOCKS5 管理脚本（Alpine Linux 完美适配版 v3）

set -e

# 颜色定义
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# Alpine 关键配置
CONFIG_FILE="/etc/sockd.conf"
PAM_FILE="/etc/pam.d/sockd"
INFO_FILE="/usr/local/bin/socks5.info"
SCRIPT_PATH="/usr/local/bin/socks5"
SERVICE_NAME="sockd"  # Alpine下 dante 的服务名必须是 sockd

# 检查 Root
if [ "$(id -u)" != "0" ]; then
    echo "Error: 请使用 root 用户运行。"
    exit 1
fi

# 启用 Community 仓库
enable_community_repo() {
    if ! grep -q "^http.*/community" /etc/apk/repositories; then
        echo -e "${BLUE}启用 Community 仓库...${NC}"
        if grep -q "#.*community" /etc/apk/repositories; then
             sed -i 's/^#\(.*community\)/\1/' /etc/apk/repositories
        else
             VERSION=$(cat /etc/alpine-release | cut -d. -f1,2)
             echo "http://dl-cdn.alpinelinux.org/alpine/v$VERSION/community" >> /etc/apk/repositories
        fi
        apk update
    fi
}

install_deps() {
    echo -e "${BLUE}安装依赖...${NC}"
    enable_community_repo
    apk update
    # linux-pam 用于认证，curl 用于获取IP
    apk add dante-server openssl linux-pam curl
    
    # 二次检查服务文件是否存在
    if [ ! -f "/etc/init.d/$SERVICE_NAME" ]; then
        echo -e "${RED}错误：未找到 $SERVICE_NAME 服务文件。${NC}"
        echo "尝试修复软链接..."
        ln -s /usr/sbin/sockd /etc/init.d/sockd 2>/dev/null || true
    fi
}

detect_iface() {
    iface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    if [ -z "$iface" ]; then
        printf "无法检测网卡，请输入出口网卡名称 (如 eth0): "
        read -r iface
    fi
    echo "$iface"
}

# 配置 PAM (解决账号密码认证失败的问题)
configure_pam() {
    cat > "$PAM_FILE" <<EOF
auth     required pam_unix.so
account  required pam_unix.so
EOF
}

gen_socks5_config() {
    printf "监听端口 [默认: 1080]: "
    read -r input_port
    base_port=${input_port:-1080}

    printf "是否启用用户名密码认证？[y/N]: "
    read -r auth
    auth_mode="none"
    
    case "$auth" in
        [Yy]*)
            auth_mode="username"
            printf "用户名 [user]: "
            read -r input_user
            user=${input_user:-user}
            
            pw=$(openssl rand -base64 8)
            printf "密码 [%s]: " "$pw"
            read -r input_pw
            pass=${input_pw:-$pw}
            
            # 创建用户(无密码交互)
            if id "$user" >/dev/null 2>&1; then
                echo "用户 $user 已存在，更新密码..."
            else
                adduser -D "$user"
            fi
            echo "$user:$pass" | chpasswd
            
            configure_pam
            ;;
    esac

    outbound_iface=$(detect_iface)
    
    # 写入 dante 配置
    cat > "$CONFIG_FILE" <<CONF
logoutput: syslog
user.notprivileged: nobody
user.libwrap: nobody

# 认证模式
method: $auth_mode
clientmethod: none

internal: 0.0.0.0 port = $base_port
external: $outbound_iface

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: error connect disconnect
}
CONF

    # 获取 IP
    IP_ADDR=$(curl -s4 http://ipv4.icanhazip.com || ip addr show "$outbound_iface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

    # 保存信息
    {
        echo "IP: $IP_ADDR"
        echo "Port: $base_port"
        if [ "$auth_mode" = "username" ]; then
            echo "Username: $user"
            echo "Password: $pass"
        else
            echo "Authentication: None"
        fi
    } > "$INFO_FILE"
}

start_service() {
    echo -e "${BLUE}启动服务 ($SERVICE_NAME)...${NC}"
    if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
        rc-service "$SERVICE_NAME" restart
    else
        rc-update add "$SERVICE_NAME" default
        rc-service "$SERVICE_NAME" start
    fi
}

stop_service() {
    rc-service "$SERVICE_NAME" stop
}

uninstall_dante() {
    stop_service
    rc-update del "$SERVICE_NAME" default
    apk del dante-server
    rm -f "$CONFIG_FILE" "$INFO_FILE" "$SCRIPT_PATH" "$PAM_FILE"
    echo -e "${GREEN}卸载完成${NC}"
}

check_status() {
    rc-service "$SERVICE_NAME" status
}

show_info() {
    if [ -f "$INFO_FILE" ]; then
        echo -e "${CYAN}----------------------------------------${NC}"
        cat "$INFO_FILE"
        echo -e "${CYAN}----------------------------------------${NC}"
    else
        echo "未找到配置信息"
    fi
}

create_shortcut() {
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}快捷命令已创建：socks5${NC}"
}

wait_input() {
    printf "按回车键继续..."
    read -r dummy
}

menu() {
    while true; do
        clear
        echo -e "${CYAN}=== Alpine Dante SOCKS5 管理 ===${NC}"
        echo "1. 安装/重装 Socks5"
        echo "2. 卸载 Socks5"
        echo "3. 启动服务"
        echo "4. 停止服务"
        echo "5. 重启服务"
        echo "6. 修改配置"
        echo "7. 显示连接信息"
        echo "8. 检查状态"
        echo "0. 退出"
        printf "请选择: "
        read -r choice
        case "$choice" in
            1) install_deps; gen_socks5_config; start_service; create_shortcut;
               echo -e "\n${GREEN}搭建成功！${NC}"; show_info; wait_input;;
            2) uninstall_dante; wait_input;;
            3) start_service; wait_input;;
            4) stop_service; wait_input;;
            5) stop_service; start_service; wait_input;;
            6) gen_socks5_config; start_service; wait_input;;
            7) show_info; wait_input;;
            8) check_status; wait_input;;
            0) exit 0;;
            *) echo "无效选择"; sleep 1;;
        esac
    done
}

# 入口
if [ "$(basename "$0")" = "socks5" ]; then
    show_info
    wait_input
fi
menu
EOF

# 3. 赋予权限并运行
chmod +x alpine_socks.sh
./alpine_socks.sh
