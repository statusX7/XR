#!/usr/bin/env bash
set -Eeuo pipefail

# XrayR management script for statusX7/XR
# Install path: /usr/bin/XrayR
# Lowercase alias: /usr/bin/xrayr

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="statusX7/XR"
BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_URL="${RAW_BASE}/install.sh"
XrayR_PATH="/usr/local/XrayR"
CONFIG_PATH="/etc/XrayR"
SERVICE_PATH="/etc/systemd/system/XrayR.service"

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

check_systemd() {
    command -v systemctl >/dev/null 2>&1 || {
        echo -e "${red}未检测到 systemctl，无法管理 XrayR 服务。${plain}"
        exit 1
    }
}

check_installed_status() {
    if [[ ! -f "${SERVICE_PATH}" || ! -f "${XrayR_PATH}/XrayR" ]]; then
        return 1
    fi
    return 0
}

check_running_status() {
    check_systemd
    if systemctl is-active --quiet XrayR; then
        return 0
    fi
    return 1
}

confirm() {
    local prompt="${1:-确认继续？}"
    read -r -p "${prompt} [y/N]: " answer
    [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

show_status() {
    check_systemd
    if ! check_installed_status; then
        echo -e "XrayR 状态：${red}未安装${plain}"
        return 1
    fi

    if check_running_status; then
        echo -e "XrayR 状态：${green}运行中${plain}"
    else
        echo -e "XrayR 状态：${yellow}未运行${plain}"
    fi
}

start() {
    check_systemd
    check_installed_status || {
        echo -e "${red}XrayR 未安装，请先执行：XrayR install${plain}"
        exit 1
    }
    systemctl start XrayR
    sleep 1
    show_status
}

stop() {
    check_systemd
    systemctl stop XrayR || true
    echo -e "${green}XrayR 已停止${plain}"
}

restart() {
    check_systemd
    check_installed_status || {
        echo -e "${red}XrayR 未安装，请先执行：XrayR install${plain}"
        exit 1
    }
    systemctl restart XrayR
    sleep 1
    show_status
}

enable() {
    check_systemd
    systemctl enable XrayR
    echo -e "${green}XrayR 已设置开机自启${plain}"
}

disable() {
    check_systemd
    systemctl disable XrayR
    echo -e "${green}XrayR 已取消开机自启${plain}"
}

log() {
    check_systemd
    journalctl -u XrayR.service -e --no-pager
}

log_follow() {
    check_systemd
    journalctl -u XrayR.service -f
}

config() {
    if [[ -f "${CONFIG_PATH}/config.yml" ]]; then
        cat "${CONFIG_PATH}/config.yml"
    else
        echo -e "${red}未找到配置文件：${CONFIG_PATH}/config.yml${plain}"
        return 1
    fi
}

edit_config() {
    mkdir -p "${CONFIG_PATH}"
    local editor="${EDITOR:-}"
    if [[ -z "${editor}" ]]; then
        if command -v nano >/dev/null 2>&1; then
            editor="nano"
        elif command -v vim >/dev/null 2>&1; then
            editor="vim"
        elif command -v vi >/dev/null 2>&1; then
            editor="vi"
        else
            echo -e "${red}未找到 nano/vim/vi，请手动编辑：${CONFIG_PATH}/config.yml${plain}"
            return 1
        fi
    fi
    "${editor}" "${CONFIG_PATH}/config.yml"
}

version() {
    if [[ -x "${XrayR_PATH}/XrayR" ]]; then
        "${XrayR_PATH}/XrayR" version || true
    else
        echo -e "${red}XrayR 未安装或二进制文件不存在${plain}"
        return 1
    fi
}

install() {
    local ver="${1:-}"
    if [[ -n "${ver}" ]]; then
        bash <(curl -Ls "${INSTALL_URL}") "${ver}"
    else
        bash <(curl -Ls "${INSTALL_URL}")
    fi
}

update() {
    local ver="${1:-}"
    if [[ -n "${ver}" ]]; then
        echo -e "${yellow}开始更新到指定版本：${ver}${plain}"
        install "${ver}"
    else
        echo -e "${yellow}开始更新到最新版本${plain}"
        install
    fi
}

uninstall() {
    echo -e "${yellow}即将卸载 XrayR。默认会保留 /etc/XrayR 配置文件。${plain}"
    confirm "确认卸载 XrayR 吗？" || {
        echo "已取消"
        return 0
    }

    check_systemd
    systemctl stop XrayR >/dev/null 2>&1 || true
    systemctl disable XrayR >/dev/null 2>&1 || true

    rm -f "${SERVICE_PATH}"
    systemctl daemon-reload || true

    rm -rf "${XrayR_PATH}"
    rm -f /usr/bin/XrayR /usr/bin/xrayr

    echo -e "${green}XrayR 已卸载，配置目录仍保留：${CONFIG_PATH}${plain}"
}

uninstall_full() {
    echo -e "${red}危险操作：将卸载 XrayR，并删除 /etc/XrayR 配置文件。${plain}"
    confirm "确认完全卸载并删除配置吗？" || {
        echo "已取消"
        return 0
    }

    check_systemd
    systemctl stop XrayR >/dev/null 2>&1 || true
    systemctl disable XrayR >/dev/null 2>&1 || true

    rm -f "${SERVICE_PATH}"
    systemctl daemon-reload || true

    rm -rf "${XrayR_PATH}" "${CONFIG_PATH}"
    rm -f /usr/bin/XrayR /usr/bin/xrayr

    echo -e "${green}XrayR 已完全卸载${plain}"
}

show_paths() {
    echo "程序目录：${XrayR_PATH}"
    echo "配置目录：${CONFIG_PATH}"
    echo "服务文件：${SERVICE_PATH}"
    echo "安装脚本：${INSTALL_URL}"
    echo "仓库地址：https://github.com/${REPO}"
}

test_urls() {
    echo "正在检测关键下载地址..."
    echo

    local urls=(
        "${INSTALL_URL}"
        "${RAW_BASE}/XrayR.sh"
        "${RAW_BASE}/XrayR.service"
        "https://api.github.com/repos/${REPO}/releases/latest"
    )

    for u in "${urls[@]}"; do
        printf "%-75s" "$u"
        if curl -IsL --connect-timeout 8 "$u" | head -n1 | grep -Eqi '200|301|302'; then
            echo -e "${green}OK${plain}"
        else
            echo -e "${red}FAIL${plain}"
        fi
    done
}

menu() {
    clear || true
    echo "————————————————————————————————————————"
    echo " XrayR 管理脚本 - statusX7/XR"
    echo "————————————————————————————————————————"
    show_status || true
    echo "————————————————————————————————————————"
    echo " 1. 启动 XrayR"
    echo " 2. 停止 XrayR"
    echo " 3. 重启 XrayR"
    echo " 4. 查看状态"
    echo " 5. 查看日志"
    echo " 6. 实时日志"
    echo " 7. 设置开机自启"
    echo " 8. 取消开机自启"
    echo " 9. 安装 XrayR"
    echo "10. 更新 XrayR"
    echo "11. 更新指定版本"
    echo "12. 查看配置文件"
    echo "13. 编辑配置文件"
    echo "14. 查看版本"
    echo "15. 查看路径"
    echo "16. 测试下载地址"
    echo "17. 卸载 XrayR（保留配置）"
    echo "18. 完全卸载 XrayR（删除配置）"
    echo " 0. 退出"
    echo "————————————————————————————————————————"

    read -r -p "请输入选择 [0-18]: " num
    case "${num}" in
        1) start ;;
        2) stop ;;
        3) restart ;;
        4) show_status ;;
        5) log ;;
        6) log_follow ;;
        7) enable ;;
        8) disable ;;
        9) install ;;
        10) update ;;
        11)
            read -r -p "请输入版本号，例如 0.9.0 或 v0.9.0: " ver
            update "${ver}"
            ;;
        12) config ;;
        13) edit_config ;;
        14) version ;;
        15) show_paths ;;
        16) test_urls ;;
        17) uninstall ;;
        18) uninstall_full ;;
        0) exit 0 ;;
        *) echo -e "${red}请输入正确数字${plain}" ;;
    esac
}

usage() {
    cat <<EOF
XrayR 管理脚本

用法：
  XrayR              显示管理菜单
  XrayR start        启动 XrayR
  XrayR stop         停止 XrayR
  XrayR restart      重启 XrayR
  XrayR status       查看 XrayR 状态
  XrayR enable       设置开机自启
  XrayR disable      取消开机自启
  XrayR log          查看 XrayR 日志
  XrayR logf         实时查看 XrayR 日志
  XrayR update       更新 XrayR 最新版本
  XrayR update x.x.x 更新 XrayR 指定版本
  XrayR install      安装 XrayR
  XrayR install x.x.x 安装指定版本
  XrayR uninstall    卸载 XrayR，保留配置
  XrayR uninstall-full 完全卸载 XrayR，删除配置
  XrayR config       显示配置文件内容
  XrayR edit         编辑配置文件
  XrayR version      查看版本
  XrayR paths        查看路径
  XrayR test         测试下载地址
  XrayR help         显示帮助
EOF
}

case "${1:-}" in
    "") menu ;;
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) show_status ;;
    enable) enable ;;
    disable) disable ;;
    log) log ;;
    logf|log-follow) log_follow ;;
    update) shift || true; update "${1:-}" ;;
    install) shift || true; install "${1:-}" ;;
    uninstall) uninstall ;;
    uninstall-full) uninstall_full ;;
    config) config ;;
    edit|edit-config) edit_config ;;
    version) version ;;
    paths|path) show_paths ;;
    test|test-url|test-urls) test_urls ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
esac
