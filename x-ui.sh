# 定义颜色变量
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

# 检查是否为 root 用户
[[ $EUID -ne 0 ]] && LOGE "错误：你必须以 root 身份运行此脚本！\n" && exit 1

# 检查操作系统，并设置 release 变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统类型，请联系脚本作者！" >&2
    exit 1
fi
echo "操作系统发行版为: $release"

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# 声明变量
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

# 通用确认函数
confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认 $2]: " temp
        if [[ "${temp}" == "" ]]; then
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

# 重启面板确认
confirm_restart() {
    confirm "重启面板，注意：重启面板会同时重启 xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

# 返回主菜单前的等待
before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read -r temp
    show_menu
}

# 安装面板
install() {
    bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

# 更新面板
update() {
    confirm "此操作会强制重装最新版，数据不会丢失。是否继续？" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "更新完成，面板已自动重启"
        before_show_menu
    fi
}

# 更新菜单脚本
update_menu() {
    echo -e "${yellow}正在更新菜单${plain}"
    confirm "此操作会将菜单更新为最新版本。" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/ltgjs/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui

    if [[ $? == 0 ]]; then
        echo -e "${green}菜单更新成功，面板已自动重启。${plain}"
        exit 0
    else
        echo -e "${red}菜单更新失败。${plain}"
        return 1
    fi
}

# 指定版本面板安装
legacy_version() {
    echo -n "请输入面板版本（如 2.4.0）:"
    read -r tag_version

    if [ -z "$tag_version" ]; then
        echo "面板版本不能为空，退出。"
        exit 1
    fi
    # 使用指定版本号下载并安装
    install_command="bash <(curl -Ls \"https://raw.githubusercontent.com/ltgjs/3x-ui/v$tag_version/install.sh\") v$tag_version"

    echo "正在下载并安装面板版本 $tag_version ..."
    eval $install_command
}

# 删除脚本自身
delete_script() {
    rm "$0"
    exit 1
}

# 卸载面板
uninstall() {
    confirm "确定要卸载面板？xray 也会被卸载！" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "卸载成功。\n"
    echo "若需重新安装此面板，可使用下方命令："
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/ltgjs/3x-ui/master/install.sh)${plain}"
    echo ""
    # 捕获 SIGTERM 信号
    trap delete_script SIGTERM
    delete_script
}

# 重置用户名密码
reset_user() {
    confirm "确定要重置面板用户名和密码？" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "请输入新的登录用户名[默认随机]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请输入新的登录密码[默认随机]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    echo -e "面板用户名已重置为: ${green} ${config_account} ${plain}"
    echo -e "面板密码已重置为: ${green} ${config_password} ${plain}"
    echo -e "${green}请使用新的用户名和密码登录 X-UI 面板，请务必牢记！${plain}"
    confirm_restart
}

# 生成随机字符串
gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# 重置 Web 基础路径
reset_webbasepath() {
    echo -e "${yellow}正在重置 Web 基础路径${plain}"

    read -rp "确定要重置 Web 基础路径吗？(y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${yellow}操作已取消。${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 10)

    # 应用新的设置
    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "Web 基础路径已重置为: ${green}${config_webBasePath}${plain}"
    echo -e "${green}请使用新的 Web 基础路径访问面板。${plain}"
    restart
}

# 重置所有设置
reset_config() {
    confirm "确定要重置所有面板设置？账户和密码不会变，账户数据不会丢失" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已恢复默认。"
    restart
}

# 检查配置并打印访问地址
check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "获取当前设置失败，请检查日志"
        show_menu
        return
    fi
    LOGI "${info}"

    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local server_ip=$(curl -s https://api.ipify.org)

    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")

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
    echo -n "请输入端口号[1-65535]: "
    read -r port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "端口已设置，请现在重启面板，并使用新端口 ${green}${port}${plain} 访问面板"
        confirm_restart
    fi
}

# 启动面板及相关服务
start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "面板已运行，无需重复启动。如需重启请选择重启"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui 启动成功"
        else
            LOGE "面板启动失败，可能是启动时间超过两秒，请稍后查看日志"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 停止面板
stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已停止，无需重复操作"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui 和 xray 已停止"
        else
            LOGE "面板停止失败，可能是停止时间超过两秒，请稍后查看日志"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 重启面板
restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui 和 xray 重启成功"
    else
        LOGE "面板重启失败，可能是启动时间超过两秒，请稍后查看日志"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 查看面板状态
status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 设置开机自启
enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "设置 x-ui 开机自启成功"
    else
        LOGE "设置 x-ui 开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 取消开机自启
disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "取消 x-ui 开机自启成功"
    else
        LOGE "取消 x-ui 开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 日志查看与清理
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
        if [[ $# == 0 ]]; then
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

# 查看封禁日志
show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}正在检查封禁日志...${plain}\n"

    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${red}Fail2ban 服务未运行!${plain}\n"
        return 1
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}fail2ban.log 中最新的系统封禁活动:${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}未找到最近的封禁活动${plain}"
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

    echo -e "\n${green}当前 jail 状态:${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}无法获取 jail 状态${plain}"
}

# BBR/加速相关菜单
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

# 禁用 BBR
disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR 当前未启用。${plain}"
        before_show_menu
    fi

    # 替换为 CUBIC
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    # 应用更改
    sysctl -p

    # 验证
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR 已成功替换为 CUBIC。${plain}"
    else
        echo -e "${red}替换失败，请检查系统配置。${plain}"
    fi
}

# 启用 BBR
enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR 已经启用!${plain}"
        before_show_menu
    fi

    # 检查操作系统并安装依赖
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
        echo -e "${red}不支持的操作系统，请手动安装依赖。${plain}\n"
        exit 1
        ;;
    esac

    # 启用 BBR
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    # 应用更改
    sysctl -p

    # 验证
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR 已成功启用。${plain}"
    else
        echo -e "${red}BBR 启用失败，请检查系统配置。${plain}"
    fi
}

# 升级菜单脚本
update_shell() {
    wget -O /usr/bin/x-ui -N https://github.com/ltgjs/3x-ui/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查机器网络连接"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "升级脚本成功，请重新运行脚本"
        before_show_menu
    fi
}

# 检查面板与服务状态函数
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
        LOGE "面板已安装，请勿重复安装"
        if [[ $# == 0 ]]; then
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
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# 显示状态
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
        echo -e "开机自启: ${green}已启用${plain}"
    else
        echo -e "开机自启: ${red}未启用${plain}"
    fi
}

# 检查 xray 状态
check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
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

# 防火墙管理菜单
firewall_menu() {
    echo -e "${green}\t1.${plain} ${green}安装${plain}防火墙"
    echo -e "${green}\t2.${plain} 端口列表 [编号]"
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

# 安装 UFW 防火墙并开放常用端口
install_firewall() {
    if ! command -v ufw &>/dev/null; then
        echo "未检测到 ufw，正在安装..."
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw 已安装"
    fi

    # 检查防火墙是否已激活
    if ufw status | grep -q "Status: active"; then
        echo "防火墙已激活"
    else
        echo "正在激活防火墙..."
        # 开放常用端口
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp # webPort
        ufw allow 2096/tcp # subport

        # 启用防火墙
        ufw --force enable
    fi
}

# 开放指定端口（支持单端口与区间）
open_ports() {
    read -rp "请输入需要开放的端口（如 80,443,2053 或区间 400-500）: " ports

    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "输入有误，请用英文逗号分隔或区间格式（如 80,443,2053 或 400-500）。" >&2
        exit 1
    fi

    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            ufw allow $start_port:$end_port/tcp
            ufw allow $start_port:$end_port/udp
        else
            ufw allow "$port"
        fi
    done

    echo "已开放端口:"
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

# 删除防火墙规则，可以按编号或端口
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
            echo "输入有误，请用英文逗号分隔编号。" >&2
            exit 1
        fi
        IFS=',' read -ra RULE_NUMBERS <<<"$rule_numbers"
        for rule_number in "${RULE_NUMBERS[@]}"; do
            ufw delete "$rule_number" || echo "删除规则编号 $rule_number 失败"
        done
        echo "所选规则已删除。"
    elif [[ $choice -eq 2 ]]; then
        read -rp "请输入要删除的端口（如 80,443,2053 或区间 400-500）: " ports
        if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
            echo "输入有误，请用英文逗号分隔或区间格式。" >&2
            exit 1
        fi
        IFS=',' read -ra PORT_LIST <<<"$ports"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                ufw delete allow $start_port:$end_port/tcp
                ufw delete allow $start_port:$end_port/udp
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
        echo "${red}错误:${plain} 请输入 1 或 2。" >&2
        exit 1
    fi
}

# Geo IP/站点数据更新菜单
update_geo() {
    echo -e "${green}\t1.${plain} Loyalsoldier (geoip.dat, geosite.dat)"
    echo -e "${green}\t2.${plain} chocolate4u (geoip_IR.dat, geosite_IR.dat)"
    echo -e "${green}\t3.${plain} runetfreedom (geoip_RU.dat, geosite_RU.dat)"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -rp "请选择: " choice

    cd /usr/local/x-ui/bin

    case "$choice" in
    0)
        show_menu
        ;;
    1)
        systemctl stop x-ui
        rm -f geoip.dat geosite.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}Loyalsoldier 数据集更新成功!${plain}"
        restart
        ;;
    2)
        systemctl stop x-ui
        rm -f geoip_IR.dat geosite_IR.dat
        wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
        wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
        echo -e "${green}chocolate4u 数据集更新成功!${plain}"
        restart
        ;;
    3)
        systemctl stop x-ui
        rm -f geoip_RU.dat geosite_RU.dat
        wget -O geoip_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}runetfreedom 数据集更新成功!${plain}"
        restart
        ;;
    *)
        echo -e "${red}无效选项，请输入正确数字。${plain}\n"
        update_geo
        ;;
    esac

    before_show_menu
}

# 安装 acme.sh 证书脚本
install_acme() {
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh 已安装。"
        return 0
    fi

    LOGI "正在安装 acme.sh..."
    cd ~ || return 1

    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "acme.sh 安装失败。"
        return 1
    else
        LOGI "acme.sh 安装成功。"
    fi

    return 0
}

# 证书管理主菜单
ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} 获取 SSL"
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
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "未找到可吊销的证书。"
        else
            echo "已有域名:"
            echo "$domains"
            read -rp "请输入要吊销证书的域名: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --revoke -d ${domain}
                LOGI "已吊销 $domain 证书"
            else
                echo "输入域名无效。"
            fi
        fi
        ssl_cert_issue_main
        ;;
    3)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "未找到可续期的证书。"
        else
            echo "已有域名:"
            echo "$domains"
            read -rp "请输入要续期证书的域名: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --renew -d ${domain} --force
                LOGI "已强制续期 $domain 证书"
            else
                echo "输入域名无效。"
            fi
        fi
        ssl_cert_issue_main
        ;;
    4)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
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
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
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
    # 获取当前 webBasePath 和端口
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # 检查 acme.sh 是否存在
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "未找到 acme.sh，将自动安装"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "acme 安装失败，请检查日志"
            exit 1
        fi
    fi

    # 安装 socat
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

    # 输入域名并检测
    local domain=""
    read -rp "请输入你的域名: " domain
    LOGD "你的域名是: ${domain}，正在检测..."

    # 检查是否已存在证书
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "系统已有该域名证书，不可重复签发。当前证书信息："
        LOGI "$certInfo"
        exit 1
    else
        LOGI "你的域名可以签发证书..."
    fi

    # 创建证书目录
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # 获取 standalone 服务器端口
    local WebPort=80
    read -rp "请选择端口（默认80）: " WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "输入无效，使用默认 80 端口。"
        WebPort=80
    fi
    LOGI "将使用端口: ${WebPort} 签发证书，请确保该端口已开放。"

    # 开始签发证书
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        LOGE "证书签发失败，请检查日志"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "证书签发成功，正在安装证书..."
    fi

    reloadCmd="x-ui restart"
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
            LOGI "reloadcmd: systemctl reload nginx ; x-ui restart"
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

    # 安装证书
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        LOGE "证书安装失败，退出。"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "证书安装成功，开启自动续签..."
    fi

    # 自动续签
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "自动续签失败，证书信息:"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "自动续签成功，证书信息:"
        ls -lah cert/*
        chmod 755 $certPath/*
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
    # 获取当前 webBasePath 和端口
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
        # 检查 acme.sh
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "未找到 acme.sh，将自动安装。"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "acme 安装失败，请检查日志。"
                exit 1
            fi
        fi

        CF_Domain=""

        LOGD "请设置你的域名："
        read -rp "输入你的域名: " CF_Domain
        LOGD "已设置域名：${CF_Domain}"

        # 设置 Cloudflare API
        CF_GlobalKey=""
        CF_AccountEmail=""
        LOGD "请设置 API 密钥："
        read -rp "输入你的 API 密钥: " CF_GlobalKey
        LOGD "你的 API 密钥为: ${CF_GlobalKey}"

        LOGD "请设置注册邮箱："
        read -rp "输入你的邮箱: " CF_AccountEmail
        LOGD "你的注册邮箱为: ${CF_AccountEmail}"

        # 设置默认 CA 为 Let's Encrypt
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "默认 CA 设置失败，脚本退出..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        # 使用 Cloudflare DNS 方式签发证书
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
        if [ $? -ne 0 ]; then
            LOGE "证书签发失败，脚本退出..."
            exit 1
        else
            LOGI "证书签发成功，正在安装..."
        fi

        # 安装证书
        certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf ${certPath}
        fi

        mkdir -p ${certPath}
        if [ $? -ne 0 ]; then
            LOGE "创建目录失败: ${certPath}"
            exit 1
        fi

        reloadCmd="x-ui restart"

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
                LOGI "reloadcmd: systemctl reload nginx ; x-ui restart"
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
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem --reloadcmd "${reloadCmd}"
        
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败，脚本退出..."
            exit 1
        else
            LOGI "证书安装成功，开启自动更新..."
        fi

        # 自动更新
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动更新设置失败，脚本退出..."
            exit 1
        else
            LOGI "证书已安装并开启自动续签，详细信息如下："
            ls -lah ${certPath}/*
            chmod 755 ${certPath}/*
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

if [[ $# > 0 ]]; then
    case $1 in
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
    *) show_usage ;;
    esac
else
    show_menu
fi
