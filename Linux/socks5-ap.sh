# 1. 强制清理旧的错误文件
rm -f socks_alpine.sh socks5.sh

# 2. 安全写入脚本 (使用 END_OF_SCRIPT 防止冲突)
cat > socks_alpine.sh << 'END_OF_SCRIPT'
#!/bin/sh
# Dante-server SOCKS5 管理脚本 (Alpine 最终修复版)

set -e

# --- 变量定义 ---
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

CONFIG_FILE="/etc/sockd.conf"
PAM_FILE="/etc/pam.d/sockd"
INFO_FILE="/usr/local/bin/socks5.info"
SCRIPT_PATH="/usr/local/bin/socks5"
SERVICE_NAME="sockd"

# --- 基础检查 ---
if [ "$(id -u)" != "0" ]; then
    echo "必须使用 root 运行"
    exit 1
fi

# --- 功能函数 ---

enable_community_repo() {
    # 启用 community 仓库以安装 dante-server
    if ! grep -q "^http.*/community" /etc/apk/repositories; then
        echo "正在启用 Community 仓库..."
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
    echo -e "${BLUE}安装依赖组件...${NC}"
    enable_community_repo
    apk update
    apk add dante-server openssl linux-pam curl iproute2
    
    # 修复可能缺失的服务软链
    if [ ! -f "/etc/init.d/$SERVICE_NAME" ]; then
        if [ -f "/usr/sbin/sockd" ]; then
            ln -s /usr/sbin/sockd /etc/init.d/sockd 2>/dev/null || true
        fi
    fi
}

detect_iface() {
    iface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    if [ -z "$iface" ]; then
        # 如果自动检测失败，尝试列出第一个非 lo 网卡
        iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n1)
    fi
    echo "$iface"
}

configure_pam() {
    # 写入 PAM 配置，用于账号密码验证
    cat > "$PAM_FILE" <<EOF
auth     required pam_unix.so
account  required pam_unix.so
EOF
}

gen_socks5_config() {
    printf "监听端口 [默认: 1080]: "
    read -r input_port
    base_port=${input_port:-1080}

    printf "是否启用用户认证 (y/n) [默认: n]: "
    read -r auth
    auth_mode="none"
    
    case "$auth" in
        [Yy]*)
            auth_mode="username"
            printf "用户名: "
            read -r user
            [ -z "$user" ] && user="user"
            
            pw=$(openssl rand -base64 8)
            printf "密码 [随机: %s]: " "$pw"
            read -r input_pw
            pass=${input_pw:-$pw}
            
            # 创建用户
            if id "$user" >/dev/null 2>&1; then
                echo "用户已存在，更新密码..."
            else
                adduser -D "$user"
            fi
            echo "$user:$pass" | chpasswd
            
            configure_pam
            ;;
    esac

    outbound_iface=$(detect_iface)
    if [ -z "$outbound_iface" ]; then
        echo -e "${RED}错误：无法检测到网卡。${NC}"
        outbound_iface="eth0"
    fi
    
    # 写入 Dante 配置文件
    cat > "$CONFIG_FILE" <<EOF
logoutput: syslog
user.notprivileged: nobody
user.libwrap: nobody

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
EOF

    # 获取IP
    IP_ADDR=$(curl -s4 http://ipv4.icanhazip.com 2>/dev/null)
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR=$(ip addr show "$outbound_iface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    fi

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
    echo -e "${BLUE}配置并启动服务 ($SERVICE_NAME)...${NC}"
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

show_info() {
    if [ -f "$INFO_FILE" ]; then
        echo -e "${CYAN}--- SOCKS5 配置信息 ---${NC}"
        cat "$INFO_FILE"
        echo -e "${CYAN}-----------------------${NC}"
    else
        echo "无配置信息"
    fi
}

create_shortcut() {
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
}

wait_input() {
    printf "按回车继续..."
    read -r dummy
}

menu() {
    while true; do
        clear
        echo -e "${CYAN}=== Alpine Socks5 管理 ===${NC}"
        echo "1. 安装"
        echo "2. 卸载"
        echo "3. 启动"
        echo "4. 停止"
        echo "5. 重启"
        echo "6. 重新配置"
        echo "7. 查看信息"
        echo "0. 退出"
        printf "选择: "
        read -r choice
        case "$choice" in
            1) install_deps; gen_socks5_config; start_service; create_shortcut;
               echo -e "\n${GREEN}安装成功${NC}"; show_info; wait_input;;
            2) uninstall_dante; wait_input;;
            3) start_service; wait_input;;
            4) stop_service; wait_input;;
            5) stop_service; start_service; wait_input;;
            6) gen_socks5_config; start_service; wait_input;;
            7) show_info; wait_input;;
            0) exit 0;;
            *) echo "无效"; sleep 1;;
        esac
    done
}

if [ "$(basename "$0")" = "socks5" ]; then
    show_info
    wait_input
fi

menu
END_OF_SCRIPT

# 3. 运行
chmod +x socks_alpine.sh
./socks_alpine.sh
