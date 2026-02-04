#!/usr/bin/env bash
# Update: 仅保留域名解析与归属地查询，去除本机IP检测
# Usage: ./script.sh [domain] OR ./script.sh (then input)

# --- 1. 获取域名逻辑 ---
DOMAIN="$1"

# 如果没有通过命令参数传入域名，则进入交互模式
if [[ -z "$DOMAIN" ]]; then
    echo "========================================="
    echo " ⚠️  未检测到命令行参数"
    read -p " ⌨️  请输入要检测的域名 (例如 baidu.com): " INPUT_DOMAIN
    DOMAIN="$INPUT_DOMAIN"
fi

# 如果还是为空，则退出
if [[ -z "$DOMAIN" ]]; then
    echo "❌ 错误: 域名不能为空，脚本退出。"
    exit 1
fi

# --- 2. 依赖检查 ---
# 去除了 curl，因为不再需要请求外部API获取本机IP
check_install() {
    if ! command -v "$1" &> /dev/null; then
        echo "🛠️  正在安装必要工具: $1 ..."
        if [ -f /etc/debian_version ]; then
            apt-get update -y -q && apt-get install dnsutils whois -y -q
        elif [ -f /etc/redhat-release ]; then
            yum install bind-utils whois -y -q
        fi
    fi
}
check_install dig
check_install whois

# --- 3. 开始执行检测 ---
echo "========================================="
echo "🔍 正在检测域名: $DOMAIN"
echo "⏳ 请稍候..."
echo "========================================="

CN_DNS="114.114.114.114"
HK_DNS="1.1.1.1"

# 解析 IP
CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS" +time=2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

echo -e "\n🌏 [大陆视角] 解析 IP (DNS: $CN_DNS)："
if [[ -n "$CN_IPS" ]]; then echo "$CN_IPS"; else echo "❌ 未解析到 IP"; fi

echo -e "\n🌍 [海外视角] 解析 IP (DNS: $HK_DNS)："
if [[ -n "$HK_IPS" ]]; then echo "$HK_IPS"; else echo "❌ 未解析到 IP"; fi

# --- 4. ASN 信息查询 ---
echo -e "\n📊 [归属地信息]："

# 合并 IP 列表 (去除了本机 EXIT_IP)
ALL_IPS=$(echo -e "$CN_IPS\n$HK_IPS" | sort -u | grep -v "^$")

if [[ -z "$ALL_IPS" ]]; then
    echo "❌ 没有获取到任何 IP，无法查询归属地。"
else
    for ip in $ALL_IPS; do
        # 查询 ASN 信息
        INFO=$(whois -h whois.cymru.com " -v $ip" 2>/dev/null | awk -F'|' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/, "", $0); print $3 " (" $2 ")"}')
        
        TAG=""
        # 简单的包含匹配
        [[ "$CN_IPS" =~ "$ip" ]] && TAG="[大陆解析]"
        [[ "$HK_IPS" =~ "$ip" ]] && TAG="${TAG}[海外解析]"
        
        echo -e "$ip \t→ ${INFO:-未知} \t$TAG"
    done
fi

echo -e "\n✅ 完成。"
