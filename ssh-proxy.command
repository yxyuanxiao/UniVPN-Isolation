#!/bin/zsh
set -euo pipefail

isolation_routing_mode() {
    /usr/bin/awk '
        $1 == "ProxyAutoConfigEnable" && $2 == ":" { enabled = ($3 == "1") }
        $1 == "ProxyAutoConfigURLString" && $2 == ":" { url = $3 }
        END {
            if (enabled && url == "http://127.0.0.1:16080/univpn.pac") print "proxy"
            else print "direct"
        }
    '
}

# Read-only diagnostic: feed the output of scutil --proxy on stdin.
if [[ "${1:-}" == "--routing-mode" ]]; then
    isolation_routing_mode
    exit 0
fi

readonly target_host="${1:-}"
readonly target_port="${2:-}"
readonly socks_host="127.0.0.1"
readonly socks_port="15902"

if [[ "${target_host}" != 10.10.128.* ]]; then
    print -u2 "拒绝连接非目标网段：${target_host:-<empty>}"
    exit 64
fi

if [[ -z "${target_port}" || "${target_port}" != <-> ]]; then
    print -u2 "无效的 SSH 目标端口：${target_port:-<empty>}"
    exit 64
fi

# Follow the user's isolation switch, exactly like proxy-aware browsers.
# A listening port does not mean the user enabled isolation. While enabled,
# never silently switch to direct access just because the VPN is reconnecting.
readonly routing_mode="$(/usr/sbin/scutil --proxy | isolation_routing_mode)"
if [[ "${routing_mode}" == "proxy" ]]; then
    exec /usr/bin/nc \
        -G 10 \
        -X 5 \
        -x "${socks_host}:${socks_port}" \
        "${target_host}" \
        "${target_port}"
fi

exec /usr/bin/nc -G 10 "${target_host}" "${target_port}"
