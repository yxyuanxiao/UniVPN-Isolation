#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CONTAINER_BIN="${SCRIPT_DIR}/runtime/bin/container"
CONTAINER_NAME="univpn-isolation"
STATE_FILE="${SCRIPT_DIR}/state/active-network-service"
network_service="Wi-Fi"

if [[ -f "${STATE_FILE}" ]]; then
    network_service="$(<"${STATE_FILE}")"
fi

print "需要管理员密码来恢复 Clash Verge 原有代理绕过列表。"
sudo -v
sudo /usr/sbin/networksetup -setautoproxyurl "${network_service}" 'http://127.0.0.1:33331/commands/pac'
sudo /usr/sbin/networksetup -setautoproxystate "${network_service}" off
sudo /usr/sbin/networksetup -setproxybypassdomains "${network_service}" \
    127.0.0.1 \
    192.168.0.0/16 \
    10.0.0.0/8 \
    172.16.0.0/12 \
    localhost \
    '*.local' \
    '*.crashlytics.com' \
    '<local>'

if "${CONTAINER_BIN}" list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qx "${CONTAINER_NAME}"; then
    "${CONTAINER_BIN}" stop --time 10 "${CONTAINER_NAME}"
fi

"${CONTAINER_BIN}" system stop >/dev/null 2>&1 || true

print "UniVPN 隔离容器已停止；10.10.128.0/24 已恢复按当前网络直连。"
