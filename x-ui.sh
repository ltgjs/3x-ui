#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# 添加基本日志打印函数
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

# check root
if [[ $EUID -ne 0 ]]; then
    LOGE "致命错误: 请使用 root 权限运行此脚本! \n"
    exit 1
fi

# 检查操作系统，并设置 release 变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "检查服务器操作系统失败，请联系作者!" >&2
    exit 1
fi
echo "当前服务器的操作系统为: $release"

os_version=""
if [[ -f /etc/os-release ]]; then
    os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')
fi

# Declare Variables
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm() {
    if [[ $# -gt 1 ]]; then
        echo && read -rp "$1 [Default $2]: " temp
        if [[ -z "${temp}" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "重启面板，注意：重启面板也会重启 Xray" "y"
    if [[ $? -eq 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按 Enter 键返回主菜单: ${plain}"
    read -r temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/main/install.sh)
    if [[ $? -eq 0 ]]; then
        if [[ $# -eq 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "$(echo -e "${green}该功能将强制安装最新版本，并且数据不会丢失。${red}你想继续吗？${plain}---->>请输入")" "y"
    if [[ $? -ne 0 ]]; then
        LOGE "已取消"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/main/install.sh)
    if [[ $? -eq 0 ]]; then
        LOGI "更新完成，面板已自动重启"
        before_show_menu
    fi
}

update_menu() {
    echo -e "${yellow}更新菜单项${plain}"
    confirm "此功能会将所有菜单项更新为最新显示状态" "y"
    if [[ $? -ne 0 ]]; then
        LOGE "已取消"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/ltgjs/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui

    if [[ $? -eq 0 ]]; then
        echo -e "${green}菜单更新成功，面板已自动重启。${plain}"
        exit 0
    else
        echo -e "${red}菜单更新失败。${plain}"
        return 1
    fi
}

legacy_version() {
    echo -n "请输入面板版本（如 2.4.0）:"
    read -r tag_version

    if [[ -z "$tag_version" ]]; then
        echo "面板版本不能为空，退出。"
        exit 1
    fi
    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls \"https://raw.githubusercontent.com/ltgjs/3x-ui/v$tag_version/install.sh\") v$tag_version"

    echo "下载并安装面板版本 $tag_version..."
    eval $install_command
}

# Function to handle the deletion of the script file
delete_script() {
    rm "$0"
    exit 1
}

uninstall() {
    confirm "您确定要卸载面板吗? Xray 也将被卸载!" "n"
    if [[ $? -ne 0 ]]; then
        if [[ $# -eq 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm -f /etc/systemd/system/x-ui.service
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /etc/x-ui/
    rm -rf /usr/local/x-ui/

    echo ""
    echo -e "卸载成功\n"
    echo "如果您需要再次安装此面板，可以使用以下命令:"
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/master/install.sh)${plain}"
    echo ""
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "您确定重置面板的用户名和密码吗?" "n"
    if [[ $? -ne 0 ]]; then
        if [[ $# -eq 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "请设置用户名 [默认为随机用户名]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请设置密码 [默认为随机密码]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}" >/dev/null 2>&1
    echo -e "面板登录用户名已重置为：${green} ${config_account} ${plain}"
    echo -e "面板登录密码已重置为：${green} ${config_password} ${plain}"
    echo -e "${green} 请使用新的登录用户名和密码访问 X-UI 面板。也请记住它们！${plain}"
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string
    random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}修改访问路径${plain}"

    read -rp "您确定要重置访问路径吗？（y/n）: " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${yellow}操作已取消.${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 10)

    # Apply the new web base path setting
    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "面板访问路径已重置为: ${green}${config_webBasePath}${plain}"
    echo -e "${green}请使用新的路径登录访问面板${plain}"
    restart
}

reset_config() {
    confirm "您确定要重置所有面板设置，帐户数据不会丢失，用户名和密码不会更改" "n"
    if [[ $? -ne 0 ]]; then
        if [[ $# -eq 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已重置为默认."
    restart
}

check_config() {
    local info
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? -ne 0 ]]; then
        LOGE "获取当前设置错误，请检查日志"
        show_menu
        return
    fi
    LOGI "${info}"

    local existing_webBasePath existing_port existing_cert server_ip domain
    existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    server_ip=$(curl -s https://api.ipify.org)

    if [[ -n "$existing_cert" ]]; then
        domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${green}访问地址: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
        else
            echo -e "${green}访问地址: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        fi
    else
        echo -e "${green}访问地址: http://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
    fi
}

set_port() {
    echo -n "输入端口号[1-65535]: "
    read -r port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port "${port}"
        echo -e "端口已设置，请立即重启面板，并使用新端口 ${green}${port}${plain} 以访问面板"
        confirm_restart
    fi
}

check_status() {
    systemctl is-active --quiet x-ui
    return $?
}

start() {
    check_status
    if [[ $? -eq 0 ]]; then
        echo ""
        LOGI "面板正在运行，无需再次启动，如需重新启动，请选择重新启动"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? -eq 0 ]]; then
            LOGI "x-ui 已成功启动"
        else
            LOGE "面板启动失败，可能是启动时间超过两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? -ne 0 ]]; then
        echo ""
        LOGI "面板已关闭，无需再次关闭！"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? -ne 0 ]]; then
            LOGI "x-ui 和 Xray 已成功关闭"
        else
            LOGE "面板关闭失败，可能是停止时间超过两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? -eq 0 ]]; then
        LOGI "x-ui 和 Xray 已成功重启"
    else
        LOGE "面板重启失败，可能是启动时间超过两秒，请稍后查看日志信息"
    fi
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? -eq 0 ]]; then
        LOGI "x-ui 已成功设置开机启动"
    else
        LOGE "x-ui 设置开机启动失败"
    fi

    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? -eq 0 ]]; then
        LOGI "x-ui 已成功取消开机启动"
    else
        LOGE "x-ui 取消开机启动失败"
    fi

    if [[ $# -eq 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    echo -e "${green}\t1.${plain} 调试日志"
    echo -e "${green}\t2.${plain} 清空全部日志"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择: " choice

    case "$choice" in
        0)
            show_menu
            ;;
        1)
            journalctl -u x-ui -e --no-pager -f -p debug
            if [[ $# -eq 0 ]]; then
                before_show_menu
            fi
            ;;
        2)
            sudo journalctl --rotate
            sudo journalctl --vacuum-time=1s
            echo "日志已清空。"
            restart
            ;;
        *)
            echo -e "${red}无效选项，请输入正确数字。${plain}\n"
            show_log
            ;;
    esac
}


show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}正在检查封禁日志...${plain}\n"

    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${red}Fail2ban 服务未运行!${plain}\n"
        return 1
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}来自 fail2ban.log 的最近系统封禁活动:${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}未发现近期系统封禁活动${plain}"
        echo ""
    fi

    if [[ -f "${iplimit_banned_log_path}" ]]; then
        echo -e "${green}3X-IPL 封禁日志条目:${plain}"
        if [[ -s "${iplimit_banned_log_path}" ]]; then
            grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo -e "${yellow}未找到封禁条目${plain}"
        else
            echo -e "${yellow}封禁日志文件为空${plain}"
        fi
    else
        echo -e "${red}未找到封禁日志文件: ${iplimit_banned_log_path}${plain}"
    fi

    echo -e "\n${green}当前封禁状态:${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}无法获取封禁状态${plain}"
}

bbr_menu() {
    echo -e "${green}\t1.${plain} 启用 BBR"
    echo -e "${green}\t2.${plain} 禁用 BBR"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择: " choice
    case "$choice" in
        0)
            show_menu
            ;;
        1)
            enable_bbr
            bbr_menu
            ;;
        2)
            disable_bbr
            bbr_menu
            ;;
        *)
            echo -e "${red}无效选项，请输入正确数字。${plain}\n"
            bbr_menu
            ;;
    esac
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR 当前未启用。${plain}"
        before_show_menu
        return 0
    fi

    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    sysctl -p

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR 已成功替换为 CUBIC${plain}"
    else
        echo -e "${red}用 CUBIC 替换 BBR 失败，请检查您的系统配置。${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR 已经启用!${plain}"
        before_show_menu
        return 0
    fi

    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
            ;;
        centos | almalinux | rocky | ol)
            yum -y update && yum -y install ca-certificates
            ;;
        fedora | amzn | virtuozzo)
            dnf -y update && dnf -y install ca-certificates
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm ca-certificates
            ;;
        *)
            echo -e "${red}不支持的操作系统。请检查脚本并手动安装必要的软件包${plain}\n"
            exit 1
            ;;
    esac

    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    sysctl -p

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR 已成功启用${plain}"
    else
        echo -e "${red}启用 BBR 失败，请检查您的系统配置${plain}"
    fi
}

update_shell() {
    wget -O /usr/bin/x-ui -N https://github.com/ltgjs/3x-ui/raw/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查机器是否可以连接至 GitHub"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "升级脚本成功，请重新运行脚本"
        exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ "${temp}" == "enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请勿重新安装"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板"
        if [[ $# -eq 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "面板状态: ${green}运行中${plain}"
            show_enable_status
            ;;
        1)
            echo -e "面板状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "面板状态: ${red}未安装${plain}"
            ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "开机启动: ${green}是${plain}"
    else
        echo -e "开机启动: ${red}否${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ $count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray 状态: ${green}运行中${plain}"
    else
        echo -e "xray 状态: ${red}未运行${plain}"
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} ${green}安装${plain}防火墙"
    echo -e "${green}\t2.${plain} 端口列表 [numbered]"
    echo -e "${green}\t3.${plain} ${green}开放${plain}端口"
    echo -e "${green}\t4.${plain} ${red}删除${plain}端口规则"
    echo -e "${green}\t5.${plain} ${green}启用${plain}防火墙"
    echo -e "${green}\t6.${plain} ${red}禁用${plain}防火墙"
    echo -e "${green}\t7.${plain} 防火墙状态"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择: " choice
    case "$choice" in
        0)
            show_menu
            ;;
        1)
            install_firewall
            firewall_menu
            ;;
        2)
            ufw status numbered
            firewall_menu
            ;;
        3)
            open_ports
            firewall_menu
            ;;
        4)
            delete_ports
            firewall_menu
            ;;
        5)
            ufw enable
            firewall_menu
            ;;
        6)
            ufw disable
            firewall_menu
            ;;
        7)
            ufw status verbose
            firewall_menu
            ;;
        *)
            echo -e "${red}无效选项，请输入正确数字。${plain}\n"
            firewall_menu
            ;;
    esac
}

install_firewall() {
    if ! command -v ufw &>/dev/null; then
        echo "ufw 防火墙未安装，正在安装......"
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw 防火墙已安装"
    fi

    if ufw status | grep -q "Status: active"; then
        echo "防火墙已经激活"
    else
        echo "正在激活防火墙..."
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp
        ufw allow 2096/tcp
        ufw --force enable
    fi
}

open_ports() {
    read -rp "输入您要打开的端口 (例如 80,443,2053 或端口范围 400-500): " ports

    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "错误：输入无效。请输入以英文逗号分隔的端口列表或端口范围（例如 80,443,2053 或 400-500)" >&2
        exit 1
    fi

    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            ufw allow "$start_port:$end_port/tcp"
            ufw allow "$start_port:$end_port/udp"
        else
            ufw allow "$port"
        fi
    done

    echo "开放指定端口:"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            (ufw status | grep -q "$start_port:$end_port") && echo "$start_port-$end_port"
        else
            (ufw status | grep -q "$port") && echo "$port"
        fi
    done
}

delete_ports() {
    echo "当前 UFW 规则:"
    ufw status numbered

    echo "请选择删除方式:"
    echo "1) 按规则编号删除"
    echo "2) 按端口删除"
    read -rp "请输入选项 (1 或 2): " choice

    if [[ $choice -eq 1 ]]; then
        read -rp "请输入要删除的规则编号（如 1,2 等）: " rule_numbers
        if ! [[ $rule_numbers =~ ^([0-9]+)(,[0-9]+)*$ ]]; then
            echo "输入有误，请用英文逗号分隔编号." >&2
            exit 1
        fi
        IFS=',' read -ra RULE_NUMBERS <<<"$rule_numbers"
        for rule_number in "${RULE_NUMBERS[@]}"; do
            ufw delete "$rule_number" || echo "删除规则编号 $rule_number"
        done
        echo "所选规则已删除."
    elif [[ $choice -eq 2 ]]; then
        read -rp "请输入要删除的端口 (例如 80,443,2053 或端口范围 400-500): " ports
        if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
            echo "错误：输入无效。请输入以逗号分隔的端口列表或端口范围 (例如 80,443,2053 或 400-500)." >&2
            exit 1
        fi
        IFS=',' read -ra PORT_LIST <<<"$ports"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                ufw delete allow "$start_port:$end_port/tcp"
                ufw delete allow "$start_port:$end_port/udp"
            else
                ufw delete allow "$port"
            fi
        done
        echo "已删除端口:"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                (ufw status | grep -q "$start_port:$end_port") || echo "$start_port-$end_port"
            else
                (ufw status | grep -q "$port") || echo "$port"
            fi
        done
    else
        echo -e "${red}错误:${plain} 请输入 1 或 2。" >&2
        exit 1
    fi
}

update_geo() {
    echo -e "${green}\t1.${plain} Loyalsoldier (geoip.dat, geosite.dat)"
    echo -e "${green}\t2.${plain} chocolate4u (geoip_IR.dat, geosite_IR.dat)"
    echo -e "${green}\t3.${plain} runetfreedom (geoip_RU.dat, geosite_RU.dat)"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择: " choice

    cd /usr/local/x-ui/bin || return 1

    case "$choice" in
        0)
            show_menu
            ;;
        1)
            systemctl stop x-ui
            rm -f geoip.dat geosite.dat
            wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
            echo -e "${green}Loyalsoldier 数据集已成功更新!${plain}"
            restart
            ;;
        2)
            systemctl stop x-ui
            rm -f geoip_IR.dat geosite_IR.dat
            wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
            wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
            echo -e "${green}chocolate4u 数据集已成功更新!${plain}"
            restart
            ;;
        3)
            systemctl stop x-ui
            rm -f geoip_RU.dat geosite_RU.dat
            wget -O geoip_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
            echo -e "${green}runetfreedom 数据集已成功更新!${plain}"
            restart
            ;;
        *)
            echo -e "${red}无效选项，请输入正确数字。${plain}\n"
            update_geo
            ;;
    esac

    before_show_menu
}

install_acme() {
    if [ -x ~/.acme.sh/acme.sh ]; then
        LOGI "acme.sh 已安装。"
        return 0
    fi

    LOGI "正在安装 acme.sh..."
    cd ~ || return 1

    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "安装 acme.sh 失败."
        return 1
    else
        LOGI "安装 acme.sh 成功."
    fi

    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} 获取 SSL 证书"
    echo -e "${green}\t2.${plain} 吊销证书"
    echo -e "${green}\t3.${plain} 强制续期"
    echo -e "${green}\t4.${plain} 显示已存在域名"
    echo -e "${green}\t5.${plain} 设置面板证书路径"
    echo -e "${green}\t0.${plain} 返回主菜单"

    read -rp "请选择: " choice
    case "$choice" in
        0)
            show_menu
            ;;
        1)
            ssl_cert_issue
            ssl_cert_issue_main
            ;;
        2)
            local domains
            domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
            if [ -z "$domains" ]; then
                echo "未找到可吊销的证书。"
            else
                echo "已有域名:"
                echo "$domains"
                read -rp "请输入要吊销证书的域名: " domain
                if echo "$domains" | grep -qw "$domain"; then
                    ~/.acme.sh/acme.sh --revoke -d "${domain}"
                    LOGI "已吊销 $domain 证书"
                else
                    echo "输入域名无效。"
                fi
            fi
            ssl_cert_issue_main
            ;;
        3)
            local domains
            domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
            if [ -z "$domains" ]; then
                echo "未找到可续期的证书。"
            else
                echo "已有域名:"
                echo "$domains"
                read -rp "请输入要续期证书的域名: " domain
                if echo "$domains" | grep -qw "$domain"; then
                    ~/.acme.sh/acme.sh --renew -d "${domain}" --force
                    LOGI "已强制续期 $domain 证书"
                else
                    echo "输入域名无效。"
                fi
            fi
            ssl_cert_issue_main
            ;;
        4)
            local domains
            domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
            if [ -z "$domains" ]; then
                echo "未找到证书。"
            else
                echo "已有域名和路径:"
                for domain in $domains; do
                    local cert_path="/root/cert/${domain}/fullchain.pem"
                    local key_path="/root/cert/${domain}/privkey.pem"
                    if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
                        echo -e "域名: ${domain}"
                        echo -e "\t证书路径: ${cert_path}"
                        echo -e "\t私钥路径: ${key_path}"
                    else
                        echo -e "域名: ${domain} - 缺少证书或私钥文件。"
                    fi
                done
            fi
            ssl_cert_issue_main
            ;;
        5)
            local domains
            domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
            if [ -z "$domains" ]; then
                echo "未找到证书。"
            else
                echo "可用域名:"
                echo "$domains"
                read -rp "请选择要设置面板路径的域名: " domain

                if echo "$domains" | grep -qw "$domain"; then
                    local webCertFile="/root/cert/${domain}/fullchain.pem"
                    local webKeyFile="/root/cert/${domain}/privkey.pem"

                    if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
                        /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                        echo "已设置面板证书路径: $domain"
                        echo "  - 证书文件: $webCertFile"
                        echo "  - 私钥文件: $webKeyFile"
                        restart
                    else
                        echo "未找到该域名的证书或私钥。"
                    fi
                else
                    echo "输入域名无效。"
                fi
            fi
            ssl_cert_issue_main
            ;;
        *)
            echo -e "${red}无效选项，请输入正确数字。${plain}\n"
            ssl_cert_issue_main
            ;;
    esac
}
ssl_cert_issue() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # check for acme.sh first
    if ! [ -x ~/.acme.sh/acme.sh ]; then
        echo "未找到 acme.sh，将自动安装"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "acme 安装失败，请检查日志"
            exit 1
        fi
    fi

    # install socat second
    case "${release}" in
        ubuntu | debian | armbian)
            apt update && apt install socat -y
            ;;
        centos | almalinux | rocky | ol)
            yum -y update && yum -y install socat
            ;;
        fedora | amzn | virtuozzo)
            dnf -y update && dnf -y install socat
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm socat
            ;;
        *)
            echo -e "${red}不支持的操作系统，请手动安装必要依赖。${plain}\n"
            exit 1
            ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "socat 安装失败，请检查日志"
        exit 1
    else
        LOGI "socat 安装成功..."
    fi

    # get the domain here, and we need to verify it
    local domain=""
    read -rp "请输入你的域名: " domain
    LOGD "你的域名是: ${domain}，正在检测..."

    # check if there already exists a certificate
    local currentCert
    currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo
        certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "系统已有该域名证书，不可重复签发。当前证书信息："
        LOGI "$certInfo"
        exit 1
    else
        LOGI "你的域名可以签发证书..."
    fi

    # create a directory for the certificate
    local certPath="/root/cert/${domain}"
    if [ -d "$certPath" ]; then
        rm -rf "$certPath"
    fi
    mkdir -p "$certPath"

    # get the port number for the standalone server
    local WebPort=80
    read -rp "请选择端口（默认80）: " WebPort
    if ! [[ "$WebPort" =~ ^[0-9]+$ ]] || [[ $WebPort -gt 65535 || $WebPort -lt 1 ]]; then
        LOGE "输入无效，使用默认 80 端口。"
        WebPort=80
    fi
    LOGI "将使用端口: ${WebPort} 签发证书，请确保该端口已开放。"

    # issue the certificate
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "${domain}" --listen-v6 --standalone --httpport "${WebPort}" --force
    if [ $? -ne 0 ]; then
        LOGE "证书签发失败，请检查日志"
        rm -rf ~/.acme.sh/"${domain}"
        exit 1
    else
        LOGI "证书签发成功，正在安装证书..."
    fi

    local reloadCmd="x-ui restart"
    LOGI "ACME 的默认 --reloadcmd 为:${yellow}x-ui restart"
    LOGI "此命令将在每次签发和续签后执行。"
    read -rp "需要自定义 --reloadcmd 吗？(y/n): " setReloadcmd
    if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
        echo -e "\n${green}\t1.${plain} 预设：systemctl reload nginx ; x-ui restart"
        echo -e "${green}\t2.${plain} 自定义命令"
        echo -e "${green}\t0.${plain} 保持默认"
        read -rp "请选择: " choice
        case "$choice" in
            1)
                LOGI "Reloadcmd 是: systemctl reload nginx ; x-ui restart"
                reloadCmd="systemctl reload nginx ; x-ui restart"
                ;;
            2)
                LOGD "建议将 x-ui restart 放在最后，这样如果其他服务失败，它就不会引发错误"
                read -rp "请输入 reloadcmd (example: systemctl reload nginx ; x-ui restart): " reloadCmd
                LOGI "你对 reloadcmd 是: ${reloadCmd}"
                ;;
            *)
                LOGI "保持reloadcmd默认"
                ;;
        esac
    fi

    # install the certificate
    ~/.acme.sh/acme.sh --installcert -d "${domain}" \
        --key-file "/root/cert/${domain}/privkey.pem" \
        --fullchain-file "/root/cert/${domain}/fullchain.pem" --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        LOGE "证书安装失败，退出。"
        rm -rf ~/.acme.sh/"${domain}"
        exit 1
    else
        LOGI "证书安装成功，开启自动续签..."
    fi

    # enable auto-renew
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "自动续签失败，证书信息:"
        ls -lah "$certPath"/*
        chmod 755 "$certPath"/*
        exit 1
    else
        LOGI "自动续签成功，证书信息:"
        ls -lah "$certPath"/*
        chmod 755 "$certPath"/*
    fi

    # 证书安装成功后，是否设置面板证书路径
    read -rp "是否要设置面板使用此证书？(y/n): " setPanel
    if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            LOGI "面板证书路径已设置: $domain"
            LOGI "  - 证书文件: $webCertFile"
            LOGI "  - 密钥文件: $webKeyFile"
            echo -e "${green}访问地址: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
            restart
        else
            LOGE "错误: 没找到证书或密钥文件: $domain."
        fi
    else
        LOGI "跳过面板证书设置。"
    fi
}

ssl_cert_issue_CF() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    LOGI "****** 使用说明 ******"
    LOGI "请按以下步骤操作："
    LOGI "1. Cloudflare 注册邮箱"
    LOGI "2. Cloudflare 全局 API 密钥"
    LOGI "3. 你的域名"
    LOGI "4. 证书签发后，会提示你是否设置给面板使用（可选）"
    LOGI "5. 脚本支持证书安装后的自动续签"

    confirm "请确认以上信息并继续？[y/n]" "y"

    if [ $? -eq 0 ]; then
        # Check for acme.sh first
        if ! [ -x ~/.acme.sh/acme.sh ]; then
            echo "未找到 acme.sh，将自动安装。"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "acme 安装失败，请检查日志。"
                exit 1
            fi
        fi

        local CF_Domain=""
        LOGD "请设置你的域名："
        read -rp "输入你的域名: " CF_Domain
        LOGD "已设置域名：${CF_Domain}"

        # Set up Cloudflare API details
        local CF_GlobalKey=""
        local CF_AccountEmail=""
        LOGD "请设置 API 密钥："
        read -rp "输入你的 API 密钥: " CF_GlobalKey
        LOGD "你的 API 密钥为: ${CF_GlobalKey}"

        LOGD "请设置注册邮箱："
        read -rp "输入你的邮箱: " CF_AccountEmail
        LOGD "你的注册邮箱为: ${CF_AccountEmail}"

        # Set the default CA to Let's Encrypt
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "默认 CA 设置失败，脚本退出..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        # Issue the certificate using Cloudflare DNS
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${CF_Domain}" -d "*.${CF_Domain}" --log --force
        if [ $? -ne 0 ]; then
            LOGE "证书签发失败，脚本退出..."
            exit 1
        else
            LOGI "证书签发成功，正在安装..."
        fi

        # Install the certificate
        local certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf "${certPath}"
        fi

        mkdir -p "${certPath}"
        if [ $? -ne 0 ]; then
            LOGE "创建目录失败: ${certPath}"
            exit 1
        fi

        local reloadCmd="x-ui restart"

        LOGI "ACME 默认 --reloadcmd: ${yellow}x-ui restart"
        LOGI "此命令将在每次签发和续签后执行。"
        read -rp "需要自定义 --reloadcmd 吗？(y/n): " setReloadcmd
        if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
            echo -e "\n${green}\t1.${plain} 预设：systemctl reload nginx ; x-ui restart"
            echo -e "${green}\t2.${plain} 自定义命令"
            echo -e "${green}\t0.${plain} 保持默认"
            read -rp "请选择: " choice
            case "$choice" in
                1)
                    LOGI "Reloadcmd: systemctl reload nginx ; x-ui restart"
                    reloadCmd="systemctl reload nginx ; x-ui restart"
                    ;;
                2)
                    LOGD "建议最后加 x-ui restart，防止前面服务失败"
                    read -rp "请输入 reloadcmd (例: systemctl reload nginx ; x-ui restart): " reloadCmd
                    LOGI "你的 reloadcmd 是: ${reloadCmd}"
                    ;;
                *)
                    LOGI "保持默认"
                    ;;
            esac
        fi
        ~/.acme.sh/acme.sh --installcert -d "${CF_Domain}" -d "*.${CF_Domain}" \
            --key-file "${certPath}/privkey.pem" \
            --fullchain-file "${certPath}/fullchain.pem" --reloadcmd "${reloadCmd}"

        if [ $? -ne 0 ]; then
            LOGE "证书安装失败，脚本退出..."
            exit 1
        else
            LOGI "证书安装成功，开启自动更新..."
        fi

        # Enable auto-update
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动更新设置失败，脚本退出..."
            exit 1
        else
            LOGI "证书已安装并开启自动续签，详细信息如下："
            ls -lah "${certPath}"/*
            chmod 755 "${certPath}"/*
        fi

        # 是否设置证书给面板
        read -rp "是否要设置面板使用此证书？(y/n): " setPanel
        if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
            local webCertFile="${certPath}/fullchain.pem"
            local webKeyFile="${certPath}/privkey.pem"

            if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
                /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                LOGI "面板证书路径已设置: $CF_Domain"
                LOGI "  - 证书文件: $webCertFile"
                LOGI "  - 密钥文件: $webKeyFile"
                echo -e "${green}访问地址: https://${CF_Domain}:${existing_port}${existing_webBasePath}${plain}"
                restart
            else
                LOGE "错误: 没找到证书或密钥文件: $CF_Domain."
            fi
        else
            LOGI "跳过面板证书设置。"
        fi
    else
        show_menu
    fi
}

run_speedtest() {
    # Check if Speedtest is already installed
    if ! command -v speedtest &>/dev/null; then
        # If not installed, determine installation method
        if command -v snap &>/dev/null; then
            echo "Installing Speedtest using snap..."
            snap install speedtest
        else
            local pkg_manager=""
            local speedtest_install_script=""

            if command -v dnf &>/dev/null; then
                pkg_manager="dnf"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v yum &>/dev/null; then
                pkg_manager="yum"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v apt-get &>/dev/null; then
                pkg_manager="apt-get"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            elif command -v apt &>/dev/null; then
                pkg_manager="apt"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            fi

            if [[ -z $pkg_manager ]]; then
                echo "错误：找不到包管理器。 您可能需要手动安装 Speedtest"
                return 1
            else
                echo "正在使用 $pkg_manager 安装 Speedtest..."
                curl -s $speedtest_install_script | bash
                $pkg_manager install -y speedtest
            fi
        fi
    fi

    speedtest
}

create_iplimit_jails() {
    # Use default bantime if not passed => 30 minutes
    local bantime="${1:-30}"

    # Uncomment 'allowipv6 = auto' in fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    # On Debian 12+ fail2ban's default backend should be changed to systemd
    if [[ "${release}" == "debian" && ${os_version} -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
name = default
protocol = tcp
chain = INPUT
EOF

    echo -e "${green}使用 ${bantime} 分钟的封禁时间以创建的 IP Limit 限制文件。${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        # Check for [3x-ipl] config in jail file then remove it
        if [[ -f "${file}" ]] && grep -qw '3x-ipl' "${file}"; then
            sed -i "/\[3x-ipl\]/,/^$/d" "${file}"
            echo -e "${yellow}消除系统环境中 [3x-ipl] 的冲突 (${file})!${plain}\n"
        fi
    done
}

ip_validation() {
    ipv6_regex="^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$"
}

iplimit_main() {
    echo -e "\n${green}\t1.${plain} 安装 Fail2ban 并配置 IP 限制"
    echo -e "${green}\t2.${plain} 更改封禁期限"
    echo -e "${green}\t3.${plain} 解禁所有IP"
    echo -e "${green}\t4.${plain} 查看日志"
    echo -e "${green}\t5.${plain} 手动封禁指定 IP"
    echo -e "${green}\t6.${plain} 手动解封指定 IP"
    echo -e "${green}\t7.${plain} 实时查看 Fail2ban 日志"
    echo -e "${green}\t8.${plain} 查看 Fail2ban 服务状态"
    echo -e "${green}\t9.${plain} 重启 Fail2ban 服务"
    echo -e "${green}\t10.${plain} 卸载 Fail2ban 和 IP 限制"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择操作: " choice
    case "$choice" in
        0)
            show_menu
            ;;
        1)
            confirm "确认要安装 Fail2ban 和 IP 限制吗？" "y"
            if [[ $? -eq 0 ]]; then
                install_iplimit
            else
                iplimit_main
            fi
            ;;
        2)
            read -rp "请输入新的封禁时长，单位为分钟（默认 30）: " NUM
            if [[ $NUM =~ ^[0-9]+$ ]]; then
                create_iplimit_jails "${NUM}"
                systemctl restart fail2ban
            else
                echo -e "${red}${NUM} 不是有效数字！请重试。${plain}"
            fi
            iplimit_main
            ;;
        3)
            confirm "确认要解除 IP 限制 jail 的所有封禁吗？" "y"
            if [[ $? -eq 0 ]]; then
                fail2ban-client reload --restart --unban 3x-ipl
                truncate -s 0 "${iplimit_banned_log_path}"
                echo -e "${green}已成功解除所有用户的封禁。${plain}"
                iplimit_main
            else
                echo -e "${yellow}已取消操作。${plain}"
                iplimit_main
            fi
            ;;
        4)
            show_banlog
            iplimit_main
            ;;
        5)
            read -rp "请输入你要封禁的 IP 地址: " ban_ip
            ip_validation
            if [[ $ban_ip =~ $ipv4_regex || $ban_ip =~ $ipv6_regex ]]; then
                fail2ban-client set 3x-ipl banip "$ban_ip"
                echo -e "${green}IP 地址 ${ban_ip} 已成功封禁。${plain}"
            else
                echo -e "${red}IP 地址格式无效！请重试。${plain}"
            fi
            iplimit_main
            ;;
        6)
            read -rp "请输入你要解封的 IP 地址: " unban_ip
            ip_validation
            if [[ $unban_ip =~ $ipv4_regex || $unban_ip =~ $ipv6_regex ]]; then
                fail2ban-client set 3x-ipl unbanip "$unban_ip"
                echo -e "${green}IP 地址 ${unban_ip} 已成功解除封禁。${plain}"
            else
                echo -e "${red}IP 地址格式无效！请重试。${plain}"
            fi
            iplimit_main
            ;;
        7)
            tail -f /var/log/fail2ban.log
            iplimit_main
            ;;
        8)
            service fail2ban status
            iplimit_main
            ;;
        9)
            systemctl restart fail2ban
            iplimit_main
            ;;
        10)
            remove_iplimit
            iplimit_main
            ;;
        *)
            echo -e "${red}无效选项，请输入有效数字。${plain}\n"
            iplimit_main
            ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}未检测到 Fail2ban，正在安装...!${plain}\n"

        case "${release}" in
            ubuntu)
                if [[ "${os_version}" -ge 24 ]]; then
                    apt update && apt install python3-pip -y
                    python3 -m pip install pyasynchat --break-system-packages
                fi
                apt update && apt install fail2ban -y
                ;;
            debian | armbian)
                apt update && apt install fail2ban -y
                ;;
            centos | almalinux | rocky | ol)
                yum update -y && yum install epel-release -y
                yum -y install fail2ban
                ;;
            fedora | amzn | virtuozzo)
                dnf -y update && dnf -y install fail2ban
                ;;
            arch | manjaro | parch)
                pacman -Syu --noconfirm fail2ban
                ;;
            *)
                echo -e "${red}不支持的操作系统，请手动安装 Fail2ban。${plain}\n"
                exit 1
                ;;
        esac

        if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Fail2ban 安装失败。${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban 安装成功！${plain}\n"
    else
        echo -e "${yellow}Fail2ban 已安装，无需重复安装。${plain}\n"
    fi

    echo -e "${green}正在配置 IP 限制功能...${plain}\n"

    iplimit_remove_conflicts

    if ! test -f "${iplimit_banned_log_path}"; then
        touch "${iplimit_banned_log_path}"
    fi

    if ! test -f "${iplimit_log_path}"; then
        touch "${iplimit_log_path}"
    fi

    create_iplimit_jails

    if ! systemctl is-active --quiet fail2ban; then
        systemctl start fail2ban
    else
        systemctl restart fail2ban
    fi
    systemctl enable fail2ban

    echo -e "${green}IP 限制功能已成功安装并配置！${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} 仅移除 IP 限制配置"
    echo -e "${green}\t2.${plain} 卸载 Fail2ban 和 IP 限制"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择操作: " num
    case "$num" in
        1)
            rm -f /etc/fail2ban/filter.d/3x-ipl.conf
            rm -f /etc/fail2ban/action.d/3x-ipl.conf
            rm -f /etc/fail2ban/jail.d/3x-ipl.conf
            systemctl restart fail2ban
            echo -e "${green}已成功移除 IP 限制！${plain}\n"
            before_show_menu
            ;;
        2)
            rm -rf /etc/fail2ban
            systemctl stop fail2ban
            case "${release}" in
                ubuntu | debian | armbian)
                    apt-get remove -y fail2ban
                    apt-get purge -y fail2ban
                    apt-get autoremove -y
                    ;;
                centos | almalinux | rocky | ol)
                    yum remove fail2ban -y
                    yum autoremove -y
                    ;;
                fedora | amzn | virtuozzo)
                    dnf remove fail2ban -y
                    dnf autoremove -y
                    ;;
                arch | manjaro | parch)
                    pacman -Rns --noconfirm fail2ban
                    ;;
                *)
                    echo -e "${red}不支持的操作系统，请手动卸载 Fail2ban。${plain}\n"
                    exit 1
                    ;;
            esac
            echo -e "${green}已成功卸载 Fail2ban 和 IP 限制！${plain}\n"
            before_show_menu
            ;;
        0)
            show_menu
            ;;
        *)
            echo -e "${red}无效选项，请输入有效数字。${plain}\n"
            remove_iplimit
            ;;
    esac
}

SSH_port_forwarding() {
    local server_ip
    server_ip=$(curl -s https://api.ipify.org)
    local existing_webBasePath
    existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port
    existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listenIP
    existing_listenIP=$(/usr/local/x-ui/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_cert
    existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key
    existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    local config_listenIP=""
    local listen_choice=""

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        echo -e "${green}面板已配置 SSL 证书，访问安全。${plain}"
        before_show_menu
    fi
    if [[ -z "$existing_cert" && -z "$existing_key" && ( -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ) ]]; then
        echo -e "\n${red}警告：未检测到证书与密钥！面板为不安全 HTTP。${plain}"
        echo "请获取证书或配置 SSH 端口转发。"
    fi

    if [[ -n "$existing_listenIP" && "$existing_listenIP" != "0.0.0.0" && ( -z "$existing_cert" && -z "$existing_key" ) ]]; then
        echo -e "\n${green}当前 SSH 端口转发配置如下：${plain}"
        echo -e "标准 SSH 命令："
        echo -e "${yellow}ssh -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\n如果使用 SSH 密钥:"
        echo -e "${yellow}ssh -i <sshkeypath> -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\n连接后，访问面板:"
        echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
    fi

    echo -e "\n请选择操作："
    echo -e "${green}1.${plain} 设置监听 IP"
    echo -e "${green}2.${plain} 清除监听 IP"
    echo -e "${green}0.${plain} 返回主菜单"
    read -rp "请选择操作: " num

    case "$num" in
        1)
            if [[ -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ]]; then
                echo -e "\n未配置监听 IP，请选择："
                echo -e "1. 使用默认 IP（127.0.0.1）"
                echo -e "2. 自定义监听 IP"
                read -rp "请选择（1 或 2）: " listen_choice

                config_listenIP="127.0.0.1"
                [[ "$listen_choice" == "2" ]] && read -rp "请输入自定义监听 IP: " config_listenIP

                /usr/local/x-ui/x-ui setting -listenIP "${config_listenIP}" >/dev/null 2>&1
                echo -e "${green}监听 IP 已设置为 ${config_listenIP}。${plain}"
                echo -e "\n${green}SSH 端口转发配置：${plain}"
                echo -e "标准 SSH 命令："
                echo -e "${yellow}ssh -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
                echo -e "\n如果使用 SSH 密钥:"
                echo -e "${yellow}ssh -i <sshkeypath> -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
                echo -e "\n连接后，访问面板:"
                echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
                restart
            else
                config_listenIP="${existing_listenIP}"
                echo -e "${green}当前监听 IP 已设置为 ${config_listenIP}。${plain}"
            fi
            ;;
        2)
            /usr/local/x-ui/x-ui setting -listenIP 0.0.0.0 >/dev/null 2>&1
            echo -e "${green}监听 IP 已清除。${plain}"
            restart
            ;;
        0)
            show_menu
            ;;
        *)
            echo -e "${red}无效选项，请输入有效数字。${plain}\n"
            SSH_port_forwarding
            ;;
    esac
}

show_usage() {
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制菜单用法 (子命令):${plain}                            │
│                                                       │
│  ${blue}x-ui${plain}              - 进入管理脚本                      │
│  ${blue}x-ui start${plain}        - 启动 3x-ui 面板                   │
│  ${blue}x-ui stop${plain}         - 关闭 3x-ui 面板                   │
│  ${blue}x-ui restart${plain}      - 重启 3x-ui 面板                   │
│  ${blue}x-ui status${plain}       - 查看 3x-ui 状态                   │
│  ${blue}x-ui settings${plain}     - 查看当前设置信息                  │
│  ${blue}x-ui enable${plain}       - 启用 3x-ui 开机启动                │
│  ${blue}x-ui disable${plain}      - 禁用 3x-ui 开机启动                │
│  ${blue}x-ui log${plain}          - 查看 3x-ui 运行日志                │
│  ${blue}x-ui banlog${plain}       - 检查 Fail2ban 禁止日志             │
│  ${blue}x-ui update${plain}       - 更新 3x-ui 面板                    │
│  ${blue}x-ui legacy${plain}       - 自定义 3x-ui 面板                  │
│  ${blue}x-ui install${plain}      - 安装 3x-ui 面板                    │
│  ${blue}x-ui uninstall${plain}    - 卸载 3x-ui 面板                    │
└───────────────────────────────────────────────────────┘"
}

show_menu() {
    echo -e "
╔──────────────────────────────────────────────────────────────╗
│   ${green}3X-UI 面板管理脚本${plain}                                 │
│   ${green}0.${plain}  退出脚本                                       │
│──────────────────────────────────────────────────────────────│
│   ${green}1.${plain}  安装面板                                       │
│   ${green}2.${plain}  更新面板                                       │
│   ${green}3.${plain}  更新菜单项                                     │
│   ${green}4.${plain}  自定义版本                                     │
│   ${green}5.${plain}  卸载面板                                       │
│──────────────────────────────────────────────────────────────│
│   ${green}6.${plain}  重置用户名、密码和Secret Token                  │
│   ${green}7.${plain}  修改访问路径                                   │
│   ${green}8.${plain}  重置面板设置                                   │
│   ${green}9.${plain}  修改面板端口                                   │
│  ${green}10.${plain}  查看面板设置                                   │
│──────────────────────────────────────────────────────────────│
│  ${green}11.${plain}  启动面板                                       │
│  ${green}12.${plain}  停止面板                                       │
│  ${green}13.${plain}  重启面板                                       │
│  ${green}14.${plain}  查看面板状态                                   │
│  ${green}15.${plain}  查看面板日志                                   │
│──────────────────────────────────────────────────────────────│
│  ${green}16.${plain}  启用开机启动                                   │
│  ${green}17.${plain}  禁用开机启动                                   │
│──────────────────────────────────────────────────────────────│
│  ${green}18.${plain}  SSL 证书管理                                   │
│  ${green}19.${plain}  Cloudflare SSL 证书                            │
│  ${green}20.${plain}  IP 限制管理                                    │
│  ${green}21.${plain}  防火墙管理                                     │
│  ${green}22.${plain}  SSH 端口转发管理                                │
│──────────────────────────────────────────────────────────────│
│  ${green}23.${plain}  启用 BBR                                       │
│  ${green}24.${plain}  更新 GEO 数据文件                               │
│  ${green}25.${plain}  Speedtest by Ookla                             │
╚──────────────────────────────────────────────────────────────╝
"
    show_status
    echo && read -rp "请输入选项 [0-25]: " num

    case "${num}" in
        0)
            exit 0
            ;;
        1)
            check_uninstall && install
            ;;
        2)
            check_install && update
            ;;
        3)
            check_install && update_menu
            ;;
        4)
            check_install && legacy_version
            ;;
        5)
            check_install && uninstall
            ;;
        6)
            check_install && reset_user
            ;;
        7)
            check_install && reset_webbasepath
            ;;
        8)
            check_install && reset_config
            ;;
        9)
            check_install && set_port
            ;;
        10)
            check_install && check_config
            ;;
        11)
            check_install && start
            ;;
        12)
            check_install && stop
            ;;
        13)
            check_install && restart
            ;;
        14)
            check_install && status
            ;;
        15)
            check_install && show_log
            ;;
        16)
            check_install && enable
            ;;
        17)
            check_install && disable
            ;;
        18)
            ssl_cert_issue_main
            ;;
        19)
            ssl_cert_issue_CF
            ;;
        20)
            iplimit_main
            ;;
        21)
            firewall_menu
            ;;
        22)
            SSH_port_forwarding
            ;;
        23)
            bbr_menu
            ;;
        24)
            update_geo
            ;;
        25)
            run_speedtest
            ;;
        *)
            LOGE "请输入正确的数字 [0-25]"
            ;;
    esac
}
if [[ $# -gt 0 ]]; then
    case "$1" in
        "start")
            check_install 0 && start 0
            ;;
        "stop")
            check_install 0 && stop 0
            ;;
        "restart")
            check_install 0 && restart 0
            ;;
        "status")
            check_install 0 && status 0
            ;;
        "settings")
            check_install 0 && check_config 0
            ;;
        "enable")
            check_install 0 && enable 0
            ;;
        "disable")
            check_install 0 && disable 0
            ;;
        "log")
            check_install 0 && show_log 0
            ;;
        "banlog")
            check_install 0 && show_banlog 0
            ;;
        "update")
            check_install 0 && update 0
            ;;
        "legacy")
            check_install 0 && legacy_version 0
            ;;
        "install")
            check_uninstall 0 && install 0
            ;;
        "uninstall")
            check_install 0 && uninstall 0
            ;;
        *)
            show_usage
            ;;
    esac
else
    show_menu
fi
