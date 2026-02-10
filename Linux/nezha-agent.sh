#!/bin/sh

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "ERROR: sudo is not installed on the system, the action cannot be proceeded."
            exit 1
        fi
    else
        "$@"
    fi
}

deps_check() {
    local deps="curl unzip grep"
    local _err=0
    local missing=""

    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _err=1
            missing="${missing} $dep"
        fi
    done

    if [ "$_err" -ne 0 ]; then
        err "Missing dependencies:$missing. Please install them and try again."
        exit 1
    fi
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://developers.cloudflare.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- "$api_list"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s "$url")"
        endpoint="$(echo "$text" | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo "$text" | grep -qw 'CN'; then
            isCN=true
            break
        elif echo "$url" | grep -q "$endpoint"; then
            break
        fi
    done
}

env_check() {
    mach=$(uname -m)
    case "$mach" in
        amd64|x86_64)
            os_arch="amd64"
            ;;
        i386|i686)
            os_arch="386"
            ;;
        aarch64|arm64)
            os_arch="arm64"
            ;;
        *arm*)
            os_arch="arm"
            ;;
        s390x)
            os_arch="s390x"
            ;;
        riscv64)
            os_arch="riscv64"
            ;;
        mips)
            os_arch="mips"
            ;;
        mipsel|mipsle)
            os_arch="mipsle"
            ;;
        loongarch64)
            os_arch="loong64"
            ;;
        *)
            err "Unknown architecture: $mach"
            exit 1
            ;;
    esac

    system=$(uname)
    case "$system" in
        *Linux*)
            os="linux"
            ;;
        *Darwin*)
            os="darwin"
            ;;
        *FreeBSD*)
            os="freebsd"
            ;;
        *)
            err "Unknown architecture: $system"
            exit 1
            ;;
    esac
}

init() {
    deps_check
    env_check

    ## China_IP
    if [ -z "$CN" ]; then
        geo_check
        if [ -n "$isCN" ]; then
            CN=true
        fi
    fi

    if [ -z "$CN" ]; then
        GITHUB_URL="github.com"
    else
        GITHUB_URL="gitee.com"
    fi
}

install() {
    echo "Installing..."

    # ----------------------------------------------------------------
    # 修改说明：强制使用指定的加速地址和固定版本 (v1.15.0 linux_amd64)
    # ----------------------------------------------------------------
    NZ_AGENT_URL="https://github.newthbay.com/https://github.com/nezhahq/agent/releases/download/v1.15.0/nezha-agent_linux_amd64.zip"
    
    # 强制将下载文件命名为 nezha-agent_linux_amd64.zip 以匹配您的链接
    DOWNLOAD_FILE="/tmp/nezha-agent_linux_amd64.zip"

    if command -v wget >/dev/null 2>&1; then
        _cmd="wget --timeout=60 -O $DOWNLOAD_FILE \"$NZ_AGENT_URL\" >/dev/null 2>&1"
    elif command -v curl >/dev/null 2>&1; then
        _cmd="curl --max-time 60 -fsSL \"$NZ_AGENT_URL\" -o $DOWNLOAD_FILE >/dev/null 2>&1"
    fi

    if ! eval "$_cmd"; then
        err "Download nezha-agent release failed, check your network connectivity"
        exit 1
    fi

    sudo mkdir -p $NZ_AGENT_PATH

    # 解压指定的文件
    sudo unzip -qo $DOWNLOAD_FILE -d $NZ_AGENT_PATH &&
        sudo rm -rf $DOWNLOAD_FILE

    path="$NZ_AGENT_PATH/config.yml"
    if [ -f "$path" ]; then
        random=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 5)
        path=$(printf "%s" "$NZ_AGENT_PATH/config-$random.yml")
    fi

    if [ -z "$NZ_SERVER" ]; then
        err "NZ_SERVER should not be empty"
        exit 1
    fi

    if [ -z "$NZ_CLIENT_SECRET" ]; then
        err "NZ_CLIENT_SECRET should not be empty"
        exit 1
    fi

    env="NZ_UUID=$NZ_UUID NZ_SERVER=$NZ_SERVER NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET NZ_TLS=$NZ_TLS NZ_DISABLE_AUTO_UPDATE=$NZ_DISABLE_AUTO_UPDATE NZ_DISABLE_FORCE_UPDATE=$DISABLE_FORCE_UPDATE NZ_DISABLE_COMMAND_EXECUTE=$NZ_DISABLE_COMMAND_EXECUTE NZ_SKIP_CONNECTION_COUNT=$NZ_SKIP_CONNECTION_COUNT"

    sudo "${NZ_AGENT_PATH}"/nezha-agent service -c "$path" uninstall >/dev/null 2>&1
    _cmd="sudo env $env $NZ_AGENT_PATH/nezha-agent service -c $path install"
    if ! eval "$_cmd"; then
        err "Install nezha-agent service failed"
        sudo "${NZ_AGENT_PATH}"/nezha-agent service -c "$path" uninstall >/dev/null 2>&1
        exit 1
    fi

    success "nezha-agent successfully installed"
}

uninstall() {
    find "$NZ_AGENT_PATH" -type f -name "*config*.yml" | while read -r file; do
        sudo "$NZ_AGENT_PATH/nezha-agent" service -c "$file" uninstall
        sudo rm "$file"
    done
    info "Uninstallation completed."
}

if [ "$1" = "uninstall" ]; then
    uninstall
    exit
fi

init
install
