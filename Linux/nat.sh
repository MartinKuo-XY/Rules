#!/usr/bin/env bash
# Update: 彻底解决国内机器无法获取海外视角的问题 (采用远程API代理查询)
# Usage: ./script.sh

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

CN_DNS="114.114.114.114"

# --- 3. 解析逻辑 ---

# 【大陆视角】
# 直接用本机向 114DNS 查询。因为你在国内，这会返回国内 IP。
CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

# 【海外视角】(关键修改)
# 既然本机查会被智能分流回国内，我们请求美国的 API (hackertarget) 帮我们查。
# 这个请求是由美国的服务器发起的，所以一定会得到海外的 IP。
HK_IPS=$(curl -s "https://api.hackertarget.com/dnslookup/?q=$DOMAIN" \
         | grep "^A" | awk '{print $3}' | sort -u)

# 如果上面的 API 挂了，用备用 API (Google DNS JSON，不带 ECS，通常返回美国结果)
if [[ -z "$HK_IPS" ]]; then
   HK_IPS=$(curl -s "https://dns.google/resolve?name=$DOMAIN&type=A" \
            | grep -oE '"data":"[0-9]{1,3}(\.[0-9]{1,3}){3}"' \
            | cut -d'"' -f4 | sort -u)
fi

echo -e "\n🌏 [大陆视角] 解析 IP (DNS: $CN_DNS)："
if [[ -n "$CN_IPS" ]]; then echo "$CN_IPS"; else echo "❌ 未解析到 IP"; fi

echo -e "\n🌍 [海外视角] 解析 IP (远程 API 代理查询)："
if [[ -n "$HK_IPS" ]]; then echo "$HK_IPS"; else echo "❌ 未解析到 IP"; fi

# --- 4. 本机出口 ---
# 你的 NAT 机出口肯定还是国内 IP，这是正常的
EXIT_IP=$(curl -s --max-time 3 https://api.ip.sb/ip -A "Mozilla/5.0")
[[ -z "$EXIT_IP" ]] && EXIT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

echo -e "\n🚀 [本机出口] IP："
[[ -n "$EXIT_IP" ]] && echo "$EXIT_IP" || echo "❌ 获取失败"

# --- 5. 归属地信息 ---
echo -e "\n📊 [IP 归属地信息]："
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
# 提示：如果大陆入口和海外入口依然一样，说明该域名没有做国内外分流，全球都是同一个IP。
