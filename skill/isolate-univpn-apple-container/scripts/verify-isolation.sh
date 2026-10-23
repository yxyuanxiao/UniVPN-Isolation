#!/bin/zsh
set -uo pipefail

install_dir="${1:-${HOME}/Applications/UniVPN-Isolation}"
internal_host="${2:-10.10.128.1}"
internal_port="${3:-80}"
container_bin="${install_dir}/runtime/bin/container"
container_name="${UNIVPN_CONTAINER_NAME:-univpn-isolation}"
socks_port="${UNIVPN_SOCKS_PORT:-15902}"
novnc_port="${UNIVPN_NOVNC_PORT:-16080}"
pac_url="http://127.0.0.1:${novnc_port}/univpn.pac"
pac_file="${install_dir}/univpn.pac"

failures=0
warnings=0

pass() {
    print "PASS: $1"
}

fail() {
    print -u2 "FAIL: $1"
    failures=$((failures + 1))
}

warn() {
    print -u2 "WARN: $1"
    warnings=$((warnings + 1))
}

probe_port() {
    /usr/bin/nc -z 127.0.0.1 "$1" >/dev/null 2>&1
}

print "UniVPN isolation verification"
print "install_dir=${install_dir}"
print "internal_probe=${internal_host}:${internal_port}"
print ""

if [[ "$(uname -m)" == "arm64" ]]; then
    pass "host is Apple silicon (arm64)"
else
    fail "host architecture is $(uname -m), expected arm64"
fi

if probe_port "${novnc_port}"; then
    pass "noVNC is listening on 127.0.0.1:${novnc_port}"
else
    warn "noVNC is not listening on 127.0.0.1:${novnc_port}"
fi

if /usr/bin/curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
    "${pac_url}" -o /dev/null 2>/dev/null; then
    pass "loopback HTTP PAC is reachable at ${pac_url}"
    if [[ -f "${pac_file}" ]]; then
        source_pac_hash="$(/usr/bin/shasum -a 256 "${pac_file}" | /usr/bin/awk '{ print $1 }')"
        served_pac_hash="$(
            /usr/bin/curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 "${pac_url}" \
                | /usr/bin/shasum -a 256 \
                | /usr/bin/awk '{ print $1 }'
        )" || served_pac_hash=""
        if [[ -n "${served_pac_hash}" && "${served_pac_hash}" == "${source_pac_hash}" ]]; then
            pass "served PAC matches ${pac_file}"
        else
            fail "served PAC differs from ${pac_file}; republish it before enabling PAC"
        fi
    else
        warn "source PAC not found at ${pac_file}; could not compare hashes"
    fi
else
    fail "loopback HTTP PAC is not reachable at ${pac_url}"
fi

if probe_port "${socks_port}"; then
    pass "restricted SOCKS is listening on 127.0.0.1:${socks_port}"
else
    fail "restricted SOCKS is not listening; connect UniVPN and confirm its certificate prompt"
fi

proxy_output="$(/usr/sbin/scutil --proxy 2>&1)"
proxy_pac_enabled="$(
    print -r -- "${proxy_output}" \
        | /usr/bin/awk '/ProxyAutoConfigEnable[[:space:]]*:/ { print $3; exit }'
)"
proxy_pac_url="$(
    print -r -- "${proxy_output}" \
        | /usr/bin/sed -n 's/^[[:space:]]*ProxyAutoConfigURLString[[:space:]]*:[[:space:]]*//p' \
        | /usr/bin/head -n 1
)"
if [[ "${proxy_pac_enabled}" == "1" && "${proxy_pac_url}" == "${pac_url}" ]]; then
    pass "macOS is using the expected loopback HTTP PAC"
elif [[ "${proxy_pac_enabled}" == "1" ]]; then
    fail "macOS PAC is enabled with an unexpected URL: ${proxy_pac_url:-unknown}"
else
    fail "macOS PAC is not enabled; browser traffic may bypass the restricted SOCKS"
fi

if [[ -x "${container_bin}" ]]; then
    inspect_output="$(${container_bin} inspect "${container_name}" 2>&1 || true)"
    if print -r -- "${inspect_output}" | /usr/bin/grep -q '"architecture"[[:space:]]*:[[:space:]]*"arm64"'; then
        pass "container platform is arm64"
    else
        warn "could not confirm arm64 platform from container inspect"
    fi
    if print -r -- "${inspect_output}" | /usr/bin/grep -q '"hostAddress"[[:space:]]*:[[:space:]]*"127.0.0.1"'; then
        pass "container has loopback-only published port(s)"
    else
        fail "could not confirm loopback-only published ports"
    fi
else
    fail "Apple Container CLI not found at ${container_bin}"
fi

default_interface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ { print $2; exit }')"
if [[ "${default_interface}" == utun* || "${default_interface}" == cnem* ]]; then
    fail "macOS default route is on ${default_interface}; expected the normal physical/network interface"
elif [[ -n "${default_interface}" ]]; then
    pass "macOS default route remains on ${default_interface}"
else
    warn "could not determine macOS default interface"
fi

if probe_port "${socks_port}"; then
    internal_log="$(mktemp /tmp/univpn-internal-probe.XXXXXX)"
    public_log="$(mktemp /tmp/univpn-public-probe.XXXXXX)"

    /usr/bin/curl -sv \
        --proxy "socks5h://127.0.0.1:${socks_port}" \
        --connect-timeout 5 \
        --max-time 7 \
        "http://${internal_host}:${internal_port}/" \
        -o /dev/null >"${internal_log}" 2>&1 || true

    /usr/bin/curl -sv \
        --proxy "socks5h://127.0.0.1:${socks_port}" \
        --connect-timeout 5 \
        --max-time 7 \
        "http://1.1.1.1:80/" \
        -o /dev/null >"${public_log}" 2>&1 || true

    if /usr/bin/grep -Eqi "SOCKS5.*(denied|not allowed|code 2)|request rejected or failed|(cannot|can.t) complete SOCKS5 connection.*\(2\)" "${public_log}"; then
        pass "public target is rejected by the restricted SOCKS ACL"
    elif /usr/bin/grep -Eqi 'Connected to 1\.1\.1\.1|SOCKS5 request granted' "${public_log}"; then
        fail "public target may be reachable through the restricted SOCKS endpoint"
    else
        warn "public-target result was inconclusive; inspect ${public_log} before deleting it"
    fi

    if /usr/bin/grep -Eqi "SOCKS5 request granted|(cannot|can.t) complete SOCKS5 connection.*\((5|4|3)\)|Connection refused" "${internal_log}"; then
        pass "internal target was not rejected by the same ACL (service reachability may still differ)"
    else
        warn "internal-target result was inconclusive; inspect ${internal_log}"
    fi

    print "probe logs: ${internal_log} ${public_log}"
fi

print ""
print "summary: failures=${failures}, warnings=${warnings}"
if (( failures > 0 )); then
    exit 1
fi
