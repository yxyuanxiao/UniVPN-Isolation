#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_ID="cn.com.huawei-security-commercial-alliance.univpn"
readonly APP_DIR="/opt/apps/${APP_ID}/files"
readonly VPN_GATEWAY="210.75.253.1"
readonly PRIVATE_TABLE="100"

child_pids=()

cleanup() {
    local pid
    for pid in "${child_pids[@]:-}"; do
        kill "${pid}" 2>/dev/null || true
    done
    pkill -x danted 2>/dev/null || true
}
trap cleanup EXIT INT TERM

configure_management_routes() {
    local guest_ip guest_subnet guest_gateway
    guest_ip="$(ip -4 -o addr show dev eth0 scope global | awk 'NR == 1 { split($4, a, "/"); print a[1] }')"
    guest_subnet="$(ip -4 route show dev eth0 proto kernel scope link | awk 'NR == 1 { print $1 }')"
    guest_gateway="$(ip -4 route show default dev eth0 | awk 'NR == 1 { print $3 }')"

    test -n "${guest_ip}"
    test -n "${guest_subnet}"
    test -n "${guest_gateway}"

    ip route replace table "${PRIVATE_TABLE}" "${guest_subnet}" dev eth0 src "${guest_ip}"
    ip route replace table "${PRIVATE_TABLE}" default via "${guest_gateway}" dev eth0

    if ! ip rule show | grep -Fq "to ${guest_subnet} lookup ${PRIVATE_TABLE}"; then
        ip rule add priority 10 to "${guest_subnet}" lookup "${PRIVATE_TABLE}"
    fi

    ip route replace "${VPN_GATEWAY}/32" via "${guest_gateway}" dev eth0
}

proxy_guard() {
    local active_vip=""
    local observed_vip

    while true; do
        configure_management_routes || true
        observed_vip="$(ip -4 -o addr show dev cnem_vnic scope global 2>/dev/null | awk 'NR == 1 { print $4 }' || true)"

        if test -n "${observed_vip}" && test "${observed_vip}" != "${active_vip}"; then
            pkill -x danted 2>/dev/null || true
            danted -D -f /etc/univpn-danted.conf
            active_vip="${observed_vip}"
        elif test -z "${observed_vip}" && test -n "${active_vip}"; then
            pkill -x danted 2>/dev/null || true
            active_vip=""
        fi

        sleep 2
    done
}

ui_guard() {
    local main_window=""
    local visible_windows=""
    local vpn_was_up=0

    while true; do
        main_window="$(DISPLAY=:99 xdotool search --name '^UniVPN$' 2>/dev/null | head -n 1 || true)"
        if test -n "${main_window}"; then
            visible_windows="$(DISPLAY=:99 xdotool search --onlyvisible --name '^UniVPN$' 2>/dev/null || true)"
            if ! printf '%s\n' "${visible_windows}" | grep -qx "${main_window}"; then
                DISPLAY=:99 xdotool windowmap "${main_window}" 2>/dev/null || true
                DISPLAY=:99 xdotool windowraise "${main_window}" 2>/dev/null || true
            fi
        fi

        if ip -4 -o addr show dev cnem_vnic scope global >/dev/null 2>&1; then
            if test "${vpn_was_up}" -eq 0; then
                sleep 1
                timeout 3 env \
                    HOME=/root \
                    USER=root \
                    LOGNAME=root \
                    DISPLAY=:99 \
                    LD_PRELOAD=/lib/aarch64-linux-gnu/libm.so.6:/lib/aarch64-linux-gnu/libfreetype.so.6 \
                    LD_LIBRARY_PATH="${APP_DIR}/lib" \
                    "${APP_DIR}/UniVPN" --help >/tmp/univpn-show.log 2>&1 || true
                vpn_was_up=1
            fi
        else
            vpn_was_up=0
        fi

        sleep 2
    done
}

mkdir -p "/root/.config/${APP_ID}"

# Exact stale X11 paths from a previous clean container stop.
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

Xvfb :99 -screen 0 1280x800x24 -nolisten tcp -ac &
child_pids+=("$!")

for _ in $(seq 1 50); do
    test -S /tmp/.X11-unix/X99 && break
    sleep 0.1
done

env HOME=/root DISPLAY=:99 xsetroot -solid '#263445'

env HOME=/root DISPLAY=:99 openbox >/tmp/openbox.log 2>&1 &
openbox_pid="$!"
child_pids+=("${openbox_pid}")

env HOME=/root DISPLAY=:99 xcompmgr -n >/tmp/xcompmgr.log 2>&1 &
xcompmgr_pid="$!"
child_pids+=("${xcompmgr_pid}")

sleep 0.2
if ! kill -0 "${openbox_pid}" 2>/dev/null; then
    cat /tmp/openbox.log >&2
    exit 1
fi
if ! kill -0 "${xcompmgr_pid}" 2>/dev/null; then
    cat /tmp/xcompmgr.log >&2
    exit 1
fi

x11vnc \
    -display :99 \
    -forever \
    -shared \
    -rfbport 5901 \
    -rfbportv6 5901 \
    -nopw \
    -listen 127.0.0.1 \
    -listen6 ::1 \
    -noshm \
    -noxdamage \
    -quiet \
    -o /tmp/x11vnc.log &
child_pids+=("$!")

websockify \
    --web=/usr/share/novnc \
    --log-file=/tmp/websockify.log \
    6080 \
    127.0.0.1:5901 &
child_pids+=("$!")

configure_management_routes
proxy_guard &
child_pids+=("$!")

cd "${APP_DIR}"
env \
    HOME=/root \
    USER=root \
    LOGNAME=root \
    DISPLAY=:99 \
    LD_PRELOAD=/lib/aarch64-linux-gnu/libm.so.6:/lib/aarch64-linux-gnu/libfreetype.so.6 \
    LD_LIBRARY_PATH="${APP_DIR}/lib" \
    ./UniVPN &
univpn_pid="$!"
child_pids+=("${univpn_pid}")

ui_guard &
child_pids+=("$!")

wait "${univpn_pid}"
