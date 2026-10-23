#!/bin/zsh
set -u

install_dir="${1:-${UNIVPN_ISOLATION_ROOT:-}}"

print_section() {
    print ""
    print "## $1"
}

print "UniVPN Apple Container preflight (read-only)"
print "timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ -n "${install_dir}" ]]; then
    print "requested install dir: ${install_dir}"
fi

print_section "Host"
print "architecture: $(uname -m)"
print "macOS: $(sw_vers -productVersion 2>/dev/null || print unknown)"

print_section "Default route"
/sbin/route -n get default 2>&1 | /usr/bin/sed -n '1,30p'

print_section "DNS"
/usr/sbin/scutil --dns 2>&1 | /usr/bin/sed -n '1,100p'

print_section "System proxy"
/usr/sbin/scutil --proxy 2>&1 | /usr/bin/sed -n '1,120p'

print_section "Network services"
/usr/sbin/networksetup -listnetworkserviceorder 2>&1 | /usr/bin/sed -n '1,120p'

print_section "Tunnel interfaces"
/sbin/ifconfig -l 2>/dev/null | /usr/bin/tr ' ' '\n' | /usr/bin/grep '^utun' || print "no utun interfaces listed"

print_section "UniVPN processes"
host_vpn_processes="$(/bin/ps -axo pid=,comm= 2>/dev/null | /usr/bin/awk '
    $2 ~ /(^|\/)(UniVPN|UniVPNCS)$/ || $2 ~ /(^|\/)cnem/ { print }
')"
if [[ -n "${host_vpn_processes}" ]]; then
    print -r -- "${host_vpn_processes}"
else
    print "no matching processes"
fi

print_section "Host UniVPN auto-login flags (values only; no credentials)"
if [[ -f "${HOME}/.UniVPN/sysconfig.ini" ]]; then
    /usr/bin/awk '
        /^[[:space:]]*AutoLogin[[:space:]]*=/ {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            print FNR ":" line
        }
    ' "${HOME}/.UniVPN/sysconfig.ini"
else
    print "host config not present"
fi

print_section "Apple Container CLI candidates"
container_candidates=(/usr/local/bin/container)
if [[ -n "${install_dir}" ]]; then
    container_candidates+=("${install_dir:A}/runtime/bin/container")
fi
container_candidates+=("${HOME}/Applications/UniVPN-Isolation/runtime/bin/container")

typeset -A seen_container_candidates
for candidate in "${container_candidates[@]}"; do
    if [[ -n "${seen_container_candidates[${candidate}]:-}" ]]; then
        continue
    fi
    seen_container_candidates[${candidate}]=1
    if [[ -x "${candidate}" ]]; then
        print "${candidate}"
        "${candidate}" --version 2>&1
    fi
done

print ""
print "Preflight complete. Do not treat the utun count as the active VPN count."
