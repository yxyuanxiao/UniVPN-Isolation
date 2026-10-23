#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CONTAINER_BIN="${SCRIPT_DIR}/runtime/bin/container"
CONTAINER_NAME="univpn-isolation"
PAC_URL="http://127.0.0.1:16080/univpn.pac"
STATE_DIR="${SCRIPT_DIR}/state"

if [[ ! -x "${CONTAINER_BIN}" ]]; then
    print -u2 "找不到 Apple Container 运行时：${CONTAINER_BIN}"
    exit 1
fi

mkdir -p "${STATE_DIR}"

default_interface="$(/sbin/route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"
network_service="$(/usr/sbin/networksetup -listnetworkserviceorder | awk -v dev="${default_interface}" '
    /^\([0-9]+\)/ {
        service=$0
        sub(/^\([0-9]+\) /, "", service)
    }
    $0 ~ "Device: " dev "\\)" { print service; exit }
')"
network_service="${network_service:-Wi-Fi}"
print -r -- "${network_service}" > "${STATE_DIR}/active-network-service"

if ! "${CONTAINER_BIN}" system start >/tmp/univpn-container-system-start.log 2>&1; then
    if ! grep -qi "already\|running" /tmp/univpn-container-system-start.log; then
        cat /tmp/univpn-container-system-start.log >&2
        exit 1
    fi
fi

if ! "${CONTAINER_BIN}" list | awk 'NR > 1 { print $1 }' | grep -qx "${CONTAINER_NAME}"; then
    "${CONTAINER_BIN}" start "${CONTAINER_NAME}"
fi

wait_for_novnc() {
    for _ in {1..60}; do
        if /usr/bin/nc -z 127.0.0.1 16080 2>/dev/null; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

if ! wait_for_novnc; then
    print -u2 "容器已启动，但 noVNC 在 15 秒内没有就绪。"
    "${CONTAINER_BIN}" logs "${CONTAINER_NAME}" | tail -n 80 >&2
    exit 1
fi

# Apple Container 冷启动时，管理端口可能先恢复，而公网 NAT 仍在预热。
# 如果第一次探测还到不了真实 VPN 网关，就等出口就绪后只重启本容器一次，
# 避免 UniVPN 在 NAT 未就绪时耗掉唯一一次自动拨号。
if ! "${CONTAINER_BIN}" exec "${CONTAINER_NAME}" /bin/sh -c \
    'timeout 2 nc -z -w 1 210.75.253.1 443' >/dev/null 2>&1; then
    print "正在等待 Apple Container 公网出口就绪…"
    gateway_ready=0
    for _ in {1..35}; do
        if "${CONTAINER_BIN}" exec "${CONTAINER_NAME}" /bin/sh -c \
            'timeout 2 nc -z -w 1 210.75.253.1 443' >/dev/null 2>&1; then
            gateway_ready=1
            break
        fi
        sleep 0.5
    done

    if [[ "${gateway_ready}" -ne 1 ]]; then
        print -u2 "容器仍无法连接 VPN 网关 210.75.253.1:443；宿主机代理尚未修改。"
        exit 1
    fi

    "${CONTAINER_BIN}" stop --time 10 "${CONTAINER_NAME}"
    "${CONTAINER_BIN}" start "${CONTAINER_NAME}"
    if ! wait_for_novnc; then
        print -u2 "重试后登录窗口在 15 秒内没有就绪。"
        exit 1
    fi
fi

"${CONTAINER_BIN}" cp \
    "${SCRIPT_DIR}/univpn.pac" \
    "${CONTAINER_NAME}:/usr/share/novnc/univpn.pac"

print "需要管理员密码来临时启用按网段分流；这不会启用 macOS UniVPN。"
sudo -v
sudo /usr/sbin/networksetup -setautoproxyurl "${network_service}" "${PAC_URL}"
sudo /usr/sbin/networksetup -setautoproxystate "${network_service}" on
sudo /usr/sbin/networksetup -setproxybypassdomains "${network_service}" \
    127.0.0.1 \
    192.168.0.0/16 \
    172.16.0.0/12 \
    localhost \
    '*.local' \
    '*.crashlytics.com' \
    '<local>'

/usr/bin/open 'http://127.0.0.1:16080/vnc.html?autoconnect=1&resize=scale'

print ""
print "UniVPN 隔离容器已启动。"
print "共享桌面： http://127.0.0.1:16080/vnc.html?autoconnect=1&resize=scale"
print "内网 SOCKS：127.0.0.1:15902（服务端只允许 10.10.128.0/24）"
print "停止时双击 stop.command。"
