#!/usr/bin/env bash
# Update: 支持交互式输入域名
# Usage: ./script.sh [domain] OR ./script.sh (then input)

# --- 1. 获取域名逻辑 (核心修改点) ---
DOMAIN="$1"

# 如果没有通过命令参数传入域名，则进入交互模式
if [[ -z "$DOMAIN" ]]; then
    echo "========================================="
    echo " ⚠️  未检测到命令行参数"
    # read -p 用于等待用户输入
    read -p " ⌨️  请输入要检测的域名 (例如 baidu.com): " INPUT_DOMAIN
    DOMAIN="$INPUT_DOMAIN"
fi

# 如果还是为空（用户直接回车），则报错退出
if [[ -z "$DOMAIN" ]]; then
    echo "❌ 错误: 域名不能为空，脚本退出。"
    exit 1
fi

# --- 2. 依赖检查 (自动安装缺失工具) ---
# 防止因为缺少 dig 或 whois 导致报错
check_install() {
    if ! command -v "$1" &> /dev/null; then
        echo "🛠️  正在安装必要工具: $1 ..."
        if [ -f /etc/debian_version ]; then
            apt-get update -y -q && apt-get install dnsutils whois curl -y -q
        elif [ -f /etc/redhat-release ]; then
            yum install bind-utils whois curl -y -q
        fi
    fi
}
check_install dig
check_install whois
check_install curl

# --- 3. 开始执行检测 ---
echo "========================================="
echo "🔍 正在检测域名: $DOMAIN"
echo "⏳ 请稍候..."
echo "========================================="

CN_DNS="114.114.114.114"
HK_DNS="1.1.1.1"

# 解析 IP (增加 grep 过滤空行)
CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

echo -e "\n🌏 [大陆视角] 解析 IP (DNS: $CN_DNS)："
if [[ -n "$CN_IPS" ]]; then echo "$CN_IPS"; else echo "❌ 未解析到 IP"; fi

echo -e "\n🌍 [海外视角] 解析 IP (DNS: $HK_DNS)："
if [[ -n "$HK_IPS" ]]; then echo "$HK_IPS"; else echo "❌ 未解析到 IP"; fi

# 获取本机出口 IP
EXIT_IP=$(curl -s --max-time 3 https://api.ip.sb/ip -A "Mozilla/5.0")
[[ -z "$EXIT_IP" ]] && EXIT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

echo -e "\n🚀 [本机出口] IP："
[[ -n "$EXIT_IP" ]] && echo "$EXIT_IP" || echo "❌ 获取失败"

# ASN 信息查询
echo -e "\n📊 [归属地信息]："
ALL_IPS=$(echo -e "$CN_IPS\n$HK_IPS\n$EXIT_IP" | sort -u | grep -v "^$")

for ip in $ALL_IPS; do
    INFO=$(whois -h whois.cymru.com " -v $ip" 2>/dev/null | awk -F'|' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/, "", $0); print $3 " (" $2 ")"}')
    
    TAG=""
    [[ "$CN_IPS" =~ "$ip" ]] && TAG="[大陆入口]"
    [[ "$HK_IPS" =~ "$ip" ]] && TAG="${TAG}[海外入口]"
    [[ "$EXIT_IP" == "$ip" ]] && TAG="${TAG}[本机出口]"
    
    echo -e "$ip \t→ ${INFO:-未知} \t$TAG"
done

echo -e "\n✅ 完成。"
