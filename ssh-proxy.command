#!/bin/zsh
set -euo pipefail

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

# Dante only listens while the isolated VPN interface is connected. When it is
# available, route SSH through the restricted SOCKS service. Otherwise connect
# directly so the same SSH aliases keep working on the physical intranet.
if /usr/bin/nc -z -G 1 "${socks_host}" "${socks_port}" >/dev/null 2>&1; then
    exec /usr/bin/nc \
        -G 10 \
        -X 5 \
        -x "${socks_host}:${socks_port}" \
        "${target_host}" \
        "${target_port}"
fi

exec /usr/bin/nc -G 10 "${target_host}" "${target_port}"
