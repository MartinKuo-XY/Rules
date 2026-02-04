#!/usr/bin/env bash
# 用法： ./check_nat_full.sh example.com
# 功能：检测域名的境内/境外入口 IP，并显示当前主机出口 IP

DOMAIN="$1"

main() {
  if [[ -z "$DOMAIN" ]]; then
    echo "用法: $0 <域名>"
    exit 1
  fi

  echo "==============================="
  echo "检测域名: $DOMAIN"
  echo "==============================="

  CN_DNS="114.114.114.114"   # 大陆公共 DNS
  HK_DNS="1.1.1.1"           # 海外公共 DNS (Cloudflare)

  # --- 解析不同地区的入口 IP ---
  CN_IPS=$(dig +short "$DOMAIN" @"$CN_DNS" \
           | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
  HK_IPS=$(dig +short "$DOMAIN" @"$HK_DNS" \
           | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

  echo -e "\n🌏 通过大陆 DNS($CN_DNS) 解析到的入口 IP："
  [[ -n "$CN_IPS" ]] && echo "$CN_IPS" || echo "未解析到 IP"

  echo -e "\n🌍 通过海外 DNS($HK_DNS) 解析到的入口 IP："
  [[ -n "$HK_IPS" ]] && echo "$HK_IPS" || echo "未解析到 IP"

  # --- 测本机出口 IP ---
  EXIT_IP=$(curl -s https://ip.sb)
  [[ -z "$EXIT_IP" ]] && EXIT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

  echo -e "\n🚀 当前主机出口 IP（curl ip.sb）："
  [[ -n "$EXIT_IP" ]] && echo "$EXIT_IP" || echo "未能获取出口 IP"

  # --- 可选 ASN 信息 ---
  echo -e "\n--- ASN / 运营商 信息 ---"
  for ip in $CN_IPS $HK_IPS $EXIT_IP; do
    if [[ -n "$ip" ]]; then
      INFO=$(whois -h whois.cymru.com " -v $ip" 2>/dev/null \
             | awk -F'|' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/, "", $0);
                                 print $3 " (" $2 ")"}')
      echo "$ip → ${INFO:-未知}"
    fi
  done

  echo -e "\n✅ 检测完成。以上 IP 可分别作为："
  echo "   - 大陆入口（供大陆用户访问或中转入口）"
  echo "   - 海外入口（海外方向或出口域名使用）"
  echo "   - 出口 IP（你 VPS 对外访问时呈现的地址）"
  echo
}

main
