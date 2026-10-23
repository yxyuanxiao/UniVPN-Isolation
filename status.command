#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CONTAINER_BIN="${SCRIPT_DIR}/runtime/bin/container"

print "Apple Container："
"${CONTAINER_BIN}" list --all 2>/dev/null || print "  系统未运行"

print ""
if /usr/bin/nc -z 127.0.0.1 16080 2>/dev/null; then
    print "noVNC：已就绪（127.0.0.1:16080）"
else
    print "noVNC：未运行"
fi

socks_probe_status=0
/usr/bin/curl \
    --silent \
    --show-error \
    --socks5-hostname 127.0.0.1:15902 \
    --connect-timeout 2 \
    --max-time 3 \
    --output /dev/null \
    http://1.1.1.1/ >/dev/null 2>&1 || socks_probe_status="$?"
if [[ "${socks_probe_status}" -eq 97 ]]; then
    print "受限 SOCKS：已就绪（127.0.0.1:15902）"
else
    print "受限 SOCKS：未就绪（VPN 尚未连接或容器未运行）"
fi

print ""
print "macOS 当前代理摘要："
/usr/sbin/scutil --proxy | sed -n '1,80p'
