#!/bin/sh
# Dante-server SOCKS5 管理脚本（Alpine Linux 修正版 v2）
# Author: Modified for Alpine (Fix Service Name & PAM)

# 遇到错误立即退出
set -e

# 颜色定义
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# Alpine 中 danted 的配置文件是 /etc/sockd.conf
CONFIG_FILE="/etc/sockd.conf"
PAM_FILE="/etc/pam.d/sockd"
INFO_FILE="/usr/local/bin/socks5.info"
SCRIPT_INSTALL_PATH="/usr/local/bin/socks5"

# 检查是否为 root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# 启用 community 仓库 (如果未启用)
enable_community_repo() {
    if ! grep -q "^http.*/community" /etc/apk/repositories; then
        echo -e "${BLUE}正在启用 Community 仓库...${NC}"
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
    echo -e "${BLUE}更新软件源并安装依赖...${NC}"
    enable_community_repo
    apk update
    # linux-pam 用于用户认证，dante-server 是主程序
    apk add dante-server openssl linux-pam curl
}

detect_iface() {
    iface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    if [ -z "$iface" ]; then
        echo -e "${RED}无法检测出口网卡，请手动指定${NC}"
        printf "出口网卡: "
        read -r iface
    fi
    echo "$iface"
}

configure_pam() {
    # 只有在使用用户名/密码认证时才需要配置 PAM
    # 创建 /etc/pam.d/sockd 文件，允许使用系统用户认证
    cat > "$PAM_FILE" <<EOF
auth required pam_unix.so
account required pam_unix.so
EOF
}

gen_socks5_config() {
    printf "监听端口 [默认: 1080]: "
    read -r input_port
    base_port=${input_port:-1080}

    printf "是否启用用户名密码认证？[y/N]: "
    read -r auth
    auth_mode="none"
    
    # 兼容 sh 的大小写判断
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
            
            # Alpine 创建用户 (无密码模式)
            if id "$user" >/dev/null 2>&1; then
                echo "用户 $user 已存在，将更新密码"
            else
                adduser -D "$user"
            fi
            # 设置密码
            echo "$user:$pass" | chpasswd
            
            # 配置 PAM
            configure_pam
            ;;
    esac

    outbound_iface=$(detect_iface)
    
    # 写入配置
    cat > "$CONFIG_FILE" <<EOF
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
EOF

    # 获取外网 IP
    IP_ADDR=$(wget -qO- http://ipv4.icanhazip.com 2>/dev/null)
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR=$(ip addr show "$outbound_iface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    fi

    # 保存信息文件
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
    # 修正：Alpine 上 dante 的服务名是 sockd
    echo -e "${BLUE}正在启动 sockd 服务...${NC}"
    if rc-service sockd status >/dev/null 2>&1; then
        rc-service sockd restart
    else
        rc-update add sockd default
        rc-service sockd start
    fi
}

stop_service() {
    rc-service sockd stop
}

uninstall_dante() {
    stop_service
    rc-update del sockd default
    apk del dante-server
    # 删除用户创建的配置文件
    rm -f "$CONFIG_FILE" "$INFO_FILE" "$SCRIPT_INSTALL_PATH" "$PAM_FILE"
    echo -e "${GREEN}卸载完成${NC}"
}

check_status() {
    if rc-service sockd status >/dev/null 2>&1; then
        echo "服务状态: 运行中"
    else
        echo "服务状态: 未运行"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        echo "配置文件: 存在"
    else
        echo "配置文件: 缺失"
    fi
}

show_info() {
    if [ -f "$INFO_FILE" ]; then
        echo -e "${CYAN}----------------------------------------${NC}"
        cat "$INFO_FILE"
        echo -e "${CYAN}----------------------------------------${NC}"
    else
        echo -e "${RED}未找到信息${NC}"
    fi
}

update_dante() {
    apk update && apk upgrade dante-server
}

create_shortcut() {
    cp "$0" "$SCRIPT_INSTALL_PATH"
    chmod +x "$SCRIPT_INSTALL_PATH"
    echo -e "${GREEN}快捷命令已创建：socks5${NC}"
}

wait_input() {
    printf "按回车键继续..."
    read -r dummy
}

menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${MAGENTA}   Alpine Dante SOCKS5 管理菜单         ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${YELLOW} 1.${NC} 安装 Socks5 代理"
        echo -e "${YELLOW} 2.${NC} 卸载 Socks5 代理"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${YELLOW} 3.${NC} 启动服务"
        echo -e "${YELLOW} 4.${NC} 停止服务"
        echo -e "${YELLOW} 5.${NC} 重启服务"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${YELLOW} 6.${NC} 修改配置"
        echo -e "${YELLOW} 7.${NC} 显示配置文件"
        echo -e "${YELLOW} 8.${NC} 显示连接信息"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${YELLOW} 9.${NC} 更新 Socks5 代理"
        echo -e "${YELLOW} 10.${NC} 检查状态"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${RED} 0.${NC} 退出"
        echo -e "${CYAN}----------------------------------------${NC}"
        printf "请选择: "
        read -r choice
        case "$choice" in
            1) install_deps; install_dante; gen_socks5_config; start_service; 
               create_shortcut;
               echo -e "\n${GREEN}=== 搭建完成，SOCKS5 信息 ===${NC}"; show_info;
               wait_input;;
            2) uninstall_dante; wait_input;;
            3) start_service; wait_input;;
            4) stop_service; wait_input;;
            5) stop_service; start_service; wait_input;;
            6) gen_socks5_config; start_service; wait_input;;
            7) cat "$CONFIG_FILE"; wait_input;;
            8) show_info; wait_input;;
            9) update_dante; wait_input;;
            10) check_status; wait_input;;
            0) exit 0;;
            *) echo "无效选择"; sleep 1;;
        esac
    done
}

install_dante() {
    # 确保 config 目录结构存在
    touch "$CONFIG_FILE"
}

# 逻辑入口
if [ "$(basename "$0")" = "socks5" ]; then
    echo -e "${GREEN}=== 当前 SOCKS5代理 信息 ===${NC}"
    show_info
    wait_input
fi

menu
