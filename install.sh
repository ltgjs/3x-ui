red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误: ${plain} 请以root权限运行此脚本 \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统类型，请联系作者！" >&2
    exit 1
fi
echo "当前系统发行版为: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的CPU架构! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "架构: $(arch)"

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC 版本 $glibc_version 过低！要求: 2.32 或更高${plain}"
        echo "请升级您的操作系统以获得更高版本的 GLIBC。"
        exit 1
    fi
    echo "GLIBC 版本: $glibc_version (满足 2.32+ 要求)"
}
check_glibc_version

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local server_ip=$(curl -s https://api.ipify.org)

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 15)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "是否自定义面板端口？(否则将随机生成端口) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "请输入面板端口: " config_port
                echo -e "${yellow}您的面板端口为: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}已随机生成端口: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "检测到为全新安装，为安全起见已随机生成登录信息:"
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "${green}端口: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
        else
            local config_webBasePath=$(gen_random_string 15)
            echo -e "${yellow}WebBasePath 缺失或过短，已自动生成新的...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}新的 WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}检测到默认账户密码，已为您随机生成新账号密码...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "生成的新登录信息如下:"
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}用户名、密码、WebBasePath均已设置。无需更改，退出...${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}获取 x-ui 版本失败，可能因为 GitHub API 受限，请稍后重试${plain}"
            exit 1
        fi
        echo -e "检测到 x-ui 最新版本: ${tag_version}，开始安装..."
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保服务器可以访问 GitHub${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}请使用更新的版本(至少 v2.3.5)，安装终止。${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 x-ui $1"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui $1 失败，请检查版本是否存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch)
    cp -f x-ui.service /etc/systemd/system/
    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/ltgjs/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui ${tag_version}${plain} 安装完成，服务已启动..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制菜单用法(子命令):${plain}                          │
│                                                       │
│  ${blue}x-ui${plain}              - 管理脚本主菜单                    │
│  ${blue}x-ui start${plain}        - 启动服务                          │
│  ${blue}x-ui stop${plain}         - 停止服务                          │
│  ${blue}x-ui restart${plain}      - 重启服务                          │
│  ${blue}x-ui status${plain}       - 查看运行状态                      │
│  ${blue}x-ui settings${plain}     - 当前设置                          │
│  ${blue}x-ui enable${plain}       - 开机自启                          │
│  ${blue}x-ui disable${plain}      - 禁用开机自启                      │
│  ${blue}x-ui log${plain}          - 查看日志                          │
│  ${blue}x-ui banlog${plain}       - 查看 Fail2ban 封禁日志           │
│  ${blue}x-ui update${plain}       - 更新 x-ui                         │
│  ${blue}x-ui legacy${plain}       - 旧版本 x-ui                       │
│  ${blue}x-ui install${plain}      - 安装 x-ui                         │
│  ${blue}x-ui uninstall${plain}    - 卸载 x-ui                         │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}正在运行...${plain}"
install_base
install_x-ui $1
