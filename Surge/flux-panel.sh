#!/bin/bash

# 获取系统架构
get_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "amd64"  # 默认使用 amd64
            ;;
    esac
}

# 兼容旧版的下载地址（固定 v2.11.2，直接二进制文件）
ARCH=$(get_architecture)
DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/v2.11.2/gost-linux-${ARCH}-2.11.2"

INSTALL_DIR="/opt/gost"

# 如果在中国，走代理加速
COUNTRY=$(curl -s https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    DOWNLOAD_URL="https://hk.gh-proxy.com/${DOWNLOAD_URL}"
fi

# 显示菜单
show_menu() {
  echo "==============================================="
  echo "              管理脚本"
  echo "==============================================="
  echo "请选择操作："
  echo "1. 安装"
  echo "2. 更新"  
  echo "3. 卸载"
  echo "4. 退出"
  echo "==============================================="
}

# 删除脚本自身
delete_self() {
  echo ""
  echo "🗑️ 操作已完成，正在清理脚本文件..."
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  sleep 1
  rm -f "$SCRIPT_PATH" && echo "✅ 脚本文件已删除" || echo "❌ 删除脚本文件失败"
}

# 检查并安装 tcpkill
check_and_install_tcpkill() {
  if command -v tcpkill &> /dev/null; then
    return 0
  fi
  OS_TYPE=$(uname -s)
  if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
  else
    SUDO_CMD=""
  fi
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    if command -v brew &> /dev/null; then
      brew install dsniff &> /dev/null
    fi
    return 0
  fi
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
  elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel"
  elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
  else
    return 0
  fi
  case $DISTRO in
    ubuntu|debian)
      $SUDO_CMD apt update &> /dev/null
      $SUDO_CMD apt install -y dsniff &> /dev/null
      ;;
    centos|rhel|fedora)
      if command -v dnf &> /dev/null; then
        $SUDO_CMD dnf install -y dsniff &> /dev/null
      elif command -v yum &> /dev/null; then
        $SUDO_CMD yum install -y dsniff &> /dev/null
      fi
      ;;
    alpine)
      $SUDO_CMD apk add --no-cache dsniff &> /dev/null
      ;;
    arch|manjaro)
      $SUDO_CMD pacman -S --noconfirm dsniff &> /dev/null
      ;;
    opensuse*|sles)
      $SUDO_CMD zypper install -y dsniff &> /dev/null
      ;;
    gentoo)
      $SUDO_CMD emerge --ask=n net-analyzer/dsniff &> /dev/null
      ;;
    void)
      $SUDO_CMD xbps-install -Sy dsniff &> /dev/null
      ;;
  esac
  return 0
}

# 获取用户输入的配置参数
get_config_params() {
  if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
    echo "请输入配置参数："
    if [[ -z "$SERVER_ADDR" ]]; then
      read -p "服务器地址: " SERVER_ADDR
    fi
    if [[ -z "$SECRET" ]]; then
      read -p "密钥: " SECRET
    fi
    if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
      echo "❌ 参数不完整，操作取消。"
      exit 1
    fi
  fi
}

# 解析命令行参数
while getopts "a:s:" opt; do
  case $opt in
    a) SERVER_ADDR="$OPTARG" ;;
    s) SECRET="$OPTARG" ;;
    *) echo "❌ 无效参数"; exit 1 ;;
  esac
done

# 安装功能
install_gost() {
  echo "🚀 开始安装 GOST v2.11.2..."
  get_config_params
  check_and_install_tcpkill
  mkdir -p "$INSTALL_DIR"

  if systemctl list-units --full -all | grep -Fq "gost.service"; then
    echo "🔍 检测到已存在的gost服务"
    systemctl stop gost 2>/dev/null && echo "🛑 停止服务"
    systemctl disable gost 2>/dev/null && echo "🚫 禁用自启"
  fi

  [[ -f "$INSTALL_DIR/gost" ]] && echo "🧹 删除旧文件 gost" && rm -f "$INSTALL_DIR/gost"

  echo "⬇️ 下载 gost ${DOWNLOAD_URL} ..."
  curl -L --fail "$DOWNLOAD_URL" -o "$INSTALL_DIR/gost"
  if [[ ! -s "$INSTALL_DIR/gost" ]]; then
      echo "❌ 下载失败，请检查链接是否正确或网络是否正常。"
      exit 1
  fi
  chmod +x "$INSTALL_DIR/gost"
  echo "✅ 下载完成"

  echo "🔎 gost 版本：$($INSTALL_DIR/gost -V)"

  CONFIG_FILE="$INSTALL_DIR/config.json"
  echo "📄 创建新配置: config.json"
  cat > "$CONFIG_FILE" <<EOF
{
  "addr": "$SERVER_ADDR",
  "secret": "$SECRET"
}
EOF

  GOST_CONFIG="$INSTALL_DIR/gost.json"
  if [[ -f "$GOST_CONFIG" ]]; then
    echo "⏭️ 跳过配置文件: gost.json (已存在)"
  else
    echo "📄 创建新配置: gost.json"
    cat > "$GOST_CONFIG" <<EOF
{}
EOF
  fi

  chmod 600 "$INSTALL_DIR"/*.json

  SERVICE_FILE="/etc/systemd/system/gost.service"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Gost Proxy Service
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/gost -C $INSTALL_DIR/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable gost
  systemctl start gost

  echo "🔄 检查服务状态..."
  if systemctl is-active --quiet gost; then
    echo "✅ 安装完成，gost服务已启动并设置为开机启动。"
    echo "📁 配置目录: $INSTALL_DIR"
  else
    echo "❌ gost服务启动失败，请执行以下命令查看日志："
    echo "journalctl -u gost -f"
  fi
}

# 更新功能
update_gost() {
  echo "🔄 开始更新 GOST v2.11.2..."
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "❌ GOST 未安装，请先选择安装。"
    return 1
  fi
  check_and_install_tcpkill

  echo "⬇️ 下载兼容版..."
  curl -L --fail "$DOWNLOAD_URL" -o "$INSTALL_DIR/gost.new"
  if [[ ! -s "$INSTALL_DIR/gost.new" ]]; then
      echo "❌ 下载失败，请检查链接是否正确或网络是否正常。"
      return 1
  fi
  mv "$INSTALL_DIR/gost.new" "$INSTALL_DIR/gost"
  chmod +x "$INSTALL_DIR/gost"

  echo "🔎 新版本：$($INSTALL_DIR/gost -V)"
  systemctl stop gost
  systemctl start gost
  echo "✅ 更新完成，服务已重新启动。"
}

# 卸载功能
uninstall_gost() {
  echo "🗑️ 开始卸载 GOST..."
  read -p "确认卸载 GOST 吗？此操作将删除所有相关文件 (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ 取消卸载"
    return 0
  fi
  if systemctl list-units --full -all | grep -Fq "gost.service"; then
    echo "🛑 停止并禁用服务..."
    systemctl stop gost 2>/dev/null
    systemctl disable gost 2>/dev/null
  fi
  if [[ -f "/etc/systemd/system/gost.service" ]]; then
    rm -f "/etc/systemd/system/gost.service"
    echo "🧹 删除服务文件"
  fi
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "🧹 删除安装目录: $INSTALL_DIR"
  fi
  systemctl daemon-reload
  echo "✅ 卸载完成"
}

# 主逻辑
main() {
  if [[ -n "$SERVER_ADDR" && -n "$SECRET" ]]; then
    install_gost
    delete_self
    exit 0
  fi
  while true; do
    show_menu
    read -p "请输入选项 (1-4): " choice
    case $choice in
      1) install_gost; delete_self; exit 0 ;;
      2) update_gost; delete_self; exit 0 ;;
      3) uninstall_gost; delete_self; exit 0 ;;
      4) echo "👋 退出脚本"; delete_self; exit 0 ;;
      *) echo "❌ 无效选项，请输入 1-4"; echo "" ;;
    esac
  done
}

main
