#!/usr/bin/env bash
# 功能：检测域名的境内/境外入口 IP，并显示当前主机出口 IP
# 依赖：dnsutils (dig), curl, whois

# --- 1. 检查必要软件依赖 ---
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "\033[31m错误: 未找到命令 '$1'\033[0m"
        echo "请先安装相关工具："
        echo "  - Debian/Ubuntu: apt-get install dnsutils whois curl -y"
        echo "  - CentOS/RHEL:   yum install bind-utils whois curl -y"
        exit 1
    fi
}

check_dep dig
check_dep curl
check_dep whois

# --- 2. 获取域名输入 (参数 或 交互) ---
DOMAIN="$1"

if [[ -z "$DOMAIN" ]]; then
    echo "========================================="
    echo " 你未在命令后提供域名。"
    read -p " 请输入要检测的域名 (例如 google.com): " INPUT_DOMAIN
    DOMAIN="$INPUT_DOMAIN"
fi

if [[ -z "$DOMAIN" ]]; then
    echo -e "\033[31m错误: 域名不能为空！\033[0m"
    exit 1
fi

main() {
  echo "========================================="
  echo "正在检测域名: $DOMAIN"
  echo "请稍候..."
  echo "========================================="

  CN_DNS="114.114.114.114"   # 大陆公共 DNS
  HK_DNS="1.1.1.1"           # 海外公共 DNS (Cloudflare)

  # --- 解析不同地区的入口 IP ---
  # 增加超时设置 +1s，防止 dig 卡死
  CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" +time=2 \
           | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
  HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS" +time=2 \
           | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

  echo -e "\n🌏 [大陆视角] 通过 DNS($CN_DNS) 解析到的入口 IP："
  if [[ -n "$CN_IPS" ]]; then
      echo "$CN_IPS"
  else
      echo -e "\033[33m未解析到 IP (可能域名被墙或无国内解析)\033[0m"
  fi

  echo -e "\n🌍 [海外视角] 通过 DNS($HK_DNS) 解析到的入口 IP："
  if [[ -n "$HK_IPS" ]]; then
      echo "$HK_IPS"
  else
      echo -e "\033[33m未解析到 IP\033[0m"
  fi

  # --- 测本机出口 IP ---
  # 尝试两个接口，防止 ip.sb 偶尔抽风
  EXIT_IP=$(curl -s --max-time 3 https://api.ip.sb/ip -A "Mozilla/5.0")
  if [[ -z "$EXIT_IP" ]]; then
      EXIT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
  fi

  echo -e "\n🚀 [本机信息] 当前主机出口 IP："
  [[ -n "$EXIT_IP" ]] && echo "$EXIT_IP" || echo -e "\033[31m未能获取出口 IP\033[0m"

  # --- 可选 ASN 信息 ---
  echo -e "\n📊 [详细信息] ASN / 运营商归属："
  # 合并所有唯一IP进行查询
  ALL_IPS=$(echo -e "$CN_IPS\n$HK_IPS\n$EXIT_IP" | sort -u | grep -v "^$")
  
  for ip in $ALL_IPS; do
      # 使用 cymru 服务查询 ASN
      INFO=$(whois -h whois.cymru.com " -v $ip" 2>/dev/null \
             | awk -F'|' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/, "", $0); print $3 " (" $2 ")"}')
      
      # 简单的标记
      TAG=""
      if [[ "$CN_IPS" =~ "$ip" ]]; then TAG="[大陆入口]"; fi
      if [[ "$HK_IPS" =~ "$ip" ]]; then TAG="${TAG}[海外入口]"; fi
      if [[ "$EXIT_IP" == "$ip" ]]; then TAG="${TAG}[本机出口]"; fi
      
      echo -e "IP: $ip \t→ ${INFO:-未知运营商} \t\033[36m$TAG\033[0m"
  done

  echo -e "\n✅ 检测完成。"
  echo
}

main
