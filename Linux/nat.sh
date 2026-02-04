#!/usr/bin/env bash
# Update: 修复NAT机DNS劫持问题 (使用DoH获取海外IP)
# Usage: ./script.sh [domain] OR ./script.sh (then input)

# --- 1. 获取域名 ---
DOMAIN="$1"
if [[ -z "$DOMAIN" ]]; then
    echo "========================================="
    read -p " ⌨️  请输入要检测的域名 (例如 baidu.com): " INPUT_DOMAIN
    DOMAIN="$INPUT_DOMAIN"
fi

if [[ -z "$DOMAIN" ]]; then
    echo "❌ 错误: 域名不能为空。"
    exit 1
fi

# --- 2. 依赖检查 ---
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

echo "========================================="
echo "🔍 正在检测域名: $DOMAIN"
echo "⏳ 请稍候..."
echo "========================================="

# --- 3. 解析 (核心修改部分) ---

CN_DNS="114.114.114.114"

# [大陆解析] 依然使用 DIG (UDP)，通常国内环境不需抗劫持
CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

# [海外解析] 改用 DoH (DNS over HTTPS)
# 原因：防止 NAT VPS 的 UDP 53 端口被强制劫持到国内 DNS
# 我们直接请求 Cloudflare 的 HTTPS 接口，这无法被劫持
HK_IPS=$(curl -s -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=$DOMAIN&type=A" \
         | grep -oE '"data":"[0-9]{1,3}(\.[0-9]{1,3}){3}"' \
         | cut -d'"' -f4 | sort -u)

echo -e "\n🌏 [大陆视角] 解析 IP (DNS: $CN_DNS)："
if [[ -n "$CN_IPS" ]]; then echo "$CN_IPS"; else echo "❌ 未解析到 IP"; fi

echo -e "\n🌍 [海外视角] 解析 IP (Cloudflare DoH)："
if [[ -n "$HK_IPS" ]]; then echo "$HK_IPS"; else echo "❌ 未解析到 IP (或域名无海外解析)"; fi

# --- 4. 本机出口 ---
EXIT_IP=$(curl -s --max-time 3 https://api.ip.sb/ip -A "Mozilla/5.0")
[[ -z "$EXIT_IP" ]] && EXIT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

echo -e "\n🚀 [本机出口] IP："
[[ -n "$EXIT_IP" ]] && echo "$EXIT_IP" || echo "❌ 获取失败"

# --- 5. 归属地信息 ---
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
