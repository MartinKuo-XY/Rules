#!/bin/sh
# Dante-server SOCKS5 管理脚本（Alpine 专属优化版）

set -e

# 颜色定义
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

CONFIG_FILE="/etc/sockd.conf"
INFO_FILE="/usr/local/bin/socks5.info"
SCRIPT_INSTALL_PATH="/usr/local/bin/socks5"

install_deps() {
    for dep in iproute2 openssl; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "${BLUE}安装依赖: $dep${NC}"
            apk add --no-cache "$dep"
        fi
    done
}

detect_iface() {
    iface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    if [ -z "$iface" ]; then
        echo -e "${RED}无法检测出口网卡，请手动指定${NC}"
        read -p "出口网卡: " iface
    fi
    echo "$iface"
}

install_dante() {
    echo -e "${BLUE}正在安装 dante-server...${NC}"
    apk add --no-cache dante-server
}

gen_socks5_config() {
    read -p "监听端口 [默认: 1080]: " base_port
    base_port=${base_port:-1080}

    read -p "是否启用用户名密码认证？[y/N]: " auth
    auth_mode="none"
    
    case "$auth" in
        [Yy]*)
            auth_mode="username"
            read -p "用户名 [user]: " user
            user=${user:-user}
            pw=$(openssl rand -base64 8)
            read -p "密码 [$pw]: " input_pw
            pass=${input_pw:-$pw}
            
            # Alpine 下的用户创建方式
            if ! id "$user" >/dev/null 2>&1; then
                adduser -D -H "$user"
            fi
            echo "$user:$pass" | chpasswd
            ;;
    esac

    outbound_iface=$(detect_iface)
    
    # 写入 Alpine 专属的 sockd 配置
    cat > "$CONFIG_FILE" <<EOF
logoutput: syslog
user.privileged: root
user.notprivileged: nobody
method: $auth_mode
clientmethod: none

internal: 0.0.0.0 port = $base_port
external: $outbound_iface

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect
}
EOF

    # 获取本机的出口 IP
    IP_ADDR=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR=$(ip addr | awk '/inet / && !/127.0.0.1/ {split($2,a,"/"); print a[1]; exit}')
    fi

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

# OpenRC (Alpine Init) 服务控制指令
start_service() { 
    rc-update add sockd default
    rc-service sockd restart
}

stop_service() { 
    rc-service sockd stop 
}

uninstall_dante() { 
    stop_service || true
    rc-update del sockd default || true
    apk del dante-server
    rm -f "$CONFIG_FILE" "$INFO_FILE" "$SCRIPT_INSTALL_PATH"
    echo -e "${GREEN}Socks5 代理已彻底卸载。${NC}"
}

check_status() {
    if rc-service sockd status 2>/dev/null | grep -q "started"; then
        echo -e "${GREEN}服务状态: 运行中 (Running)${NC}"
    else
        echo -e "${RED}服务状态: 未运行 (Stopped)${NC}"
    fi
    [ -f "$CONFIG_FILE" ] && echo -e "配置文件: ${GREEN}存在${NC}" || echo -e "配置文件: ${RED}缺失${NC}"
}

show_info() {
    if [ -f "$INFO_FILE" ]; then
        echo -e "${CYAN}----------------------------------------${NC}"
        cat "$INFO_FILE"
        echo -e "${CYAN}----------------------------------------${NC}"
    else
        echo -e "${RED}未找到信息，请先安装配置。${NC}"
    fi
}

update_dante() { 
    apk update && apk upgrade dante-server 
}

create_shortcut() {
    cp "$0" "$SCRIPT_INSTALL_PATH"
    chmod +x "$SCRIPT_INSTALL_PATH"
    echo -e "${GREEN}全局快捷命令已创建：可随时输入 socks5 调出面板${NC}"
}

pause() {
    printf "按回车键继续..."
    read -r dummy
}

menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${MAGENTA}   Dante SOCKS5 管理菜单 (Alpine 专版)  ${NC}"
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
        read -p "请选择 [0-10]: " choice
        
        case "$choice" in
            1) install_deps; install_dante; gen_socks5_config; start_service; create_shortcut
               echo -e "\n${GREEN}=== 搭建完成，SOCKS5 信息 ===${NC}"
               show_info
               pause ;;
            2) uninstall_dante; pause ;;
            3) start_service; pause ;;
            4) stop_service; pause ;;
            5) stop_service; start_service; pause ;;
            6) gen_socks5_config; start_service; pause ;;
            7) cat "$CONFIG_FILE" 2>/dev/null || echo "配置不存在"; pause ;;
            8) show_info; pause ;;
            9) update_dante; pause ;;
            10) check_status; pause ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 快捷方式入口拦截
if [ "$(basename "$0")" = "socks5" ]; then
    echo -e "${GREEN}=== 当前 SOCKS5 代理信息 ===${NC}"
    show_info
    pause
fi

menu
