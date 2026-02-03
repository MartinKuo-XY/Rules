#!/bin/bash
set -e

URL="https://github.newthbay.com/raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

install_downloader() {
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        echo "curl 或 wget 已安装"
        return
    fi

    echo "未检测到 curl 或 wget，尝试安装..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y curl || apt-get install -y wget
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl || yum install -y wget
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl || dnf install -y wget
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl || apk add --no-cache wget
    else
        echo "无法自动安装 curl/wget，请手动安装。"
        exit 1
    fi
}

download_and_run() {
    echo "尝试下载脚本..."
    curl -O "$URL" || wget -O "${URL##*/}" "$URL"

    echo "执行脚本..."
    bash reinstall.sh debian 12
}

install_downloader
download_and_run
