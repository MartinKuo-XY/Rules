#!/usr/bin/env bash
# Update: 强制指定香港ISP DNS (PCCW) 并使用 TCP 协议
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

# --- 3. 解析逻辑 ---

# 【大陆视角】
# 使用 114 DNS (UDP)
# 只要在国内，这肯定返回国内优化 IP
CN_DNS="114.114.114.114"
CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

# 【香港视角】(核心修改)
# 策略：直接向香港 PCCW (电讯盈科) 的 DNS 发起 TCP 查询
# 1. IP: 202.14.67.4 (PCCW 公共 DNS)
# 2. 协议: +tcp (绕过 NAT 机器的 UDP 53 劫持)
# 3. 如果 PCCW 连不上，尝试 HKBN (香港宽频) 203.80.96.10

HK_DNS_IP="202.14.67.4" # PCCW
HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS_IP" +tcp +time=3 +tries=1 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

# 如果 PCCW 失败（可能被墙或超时），尝试备用 HKBN
if [[ -z "$HK_IPS" ]]; then
    HK_DNS_IP="203.80.96.10" # HKBN
    HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS_IP" +tcp +time=3 +tries=1 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
fi

echo -e "\n🌏 [大陆视角] 解析 IP (DNS: 114.114.114.114)："
if [[ -n "$CN_IPS" ]]; then echo "$CN_IPS"; else echo "❌ 未解析到 IP"; fi

echo -e "\n🇭🇰 [香港视角] 解析 IP (DNS: $HK_DNS_IP via TCP)："
if [[ -n "$HK_IPS" ]]; then 
    echo "$HK_IPS"
else 
    echo "❌ 获取失败 (可能原因: 防火墙拦截了到香港的 TCP DNS 流量)"
fi

# --- 4. 本机出口 ---
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
    [[ "$HK_IPS" =~ "$ip" ]] && TAG="${TAG}[香港入口]"
    [[ "$EXIT_IP" == "$ip" ]] && TAG="${TAG}[本机出口]"
    
    echo -e "$ip \t→ ${INFO:-未知} \t$TAG"
done

echo -e "\n✅ 完成。"
