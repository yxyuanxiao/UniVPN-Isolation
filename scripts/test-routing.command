#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

check_mode() {
    local expected_mode="$1"
    local proxy_output="$2"
    local actual_mode
    actual_mode="$(print -r -- "${proxy_output}" | /bin/zsh "${PROJECT_ROOT}/ssh-proxy.command" --routing-mode)"
    [[ "${actual_mode}" == "${expected_mode}" ]] || {
        print -u2 "FAIL: expected ${expected_mode}, got ${actual_mode}"
        exit 1
    }
}

check_mode direct '<dictionary> {}'
check_mode direct $'ProxyAutoConfigEnable : 0\nProxyAutoConfigURLString : http://127.0.0.1:16080/univpn.pac'
check_mode direct $'ProxyAutoConfigEnable : 1\nProxyAutoConfigURLString : http://127.0.0.1:33331/commands/pac'
check_mode direct $'ProxyAutoConfigEnable : 1'
check_mode proxy $'ProxyAutoConfigEnable : 1\nProxyAutoConfigURLString : http://127.0.0.1:16080/univpn.pac'
check_mode proxy $'  ProxyAutoConfigURLString : http://127.0.0.1:16080/univpn.pac\n  ProxyAutoConfigEnable : 1'
print 'PASS: SSH follows only the isolation PAC switch, not port availability'

/usr/bin/osascript -l JavaScript - "${PROJECT_ROOT}/univpn.pac" <<'JAVASCRIPT'
ObjC.import('Foundation');

function dnsResolve(host) {
    return host === 'training.example' ? '10.10.128.2' : null;
}
function isPlainHostName(host) { return host.indexOf('.') < 0; }
function shExpMatch(host, pattern) { return pattern === '*.local' && /\.local$/.test(host); }
function ipv4(value) {
    return value.split('.').reduce(function (number, octet) { return (number << 8) | Number(octet); }, 0);
}
function isInNet(host, address, mask) { return (ipv4(host) & ipv4(mask)) === (ipv4(address) & ipv4(mask)); }

function run(argv) {
    var source = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
    if (!source) throw new Error('Cannot read PAC');
    eval(ObjC.unwrap(source));

    var isolated = 'SOCKS5 127.0.0.1:15902; SOCKS 127.0.0.1:15902';
    var publicProxy = 'PROXY 127.0.0.1:7897; SOCKS5 127.0.0.1:7897; DIRECT';
    [
        ['10.10.128.2', isolated], ['10.10.128.255', isolated],
        ['training.example', isolated], ['10.10.129.2', 'DIRECT'],
        ['192.168.3.1', 'DIRECT'], ['172.20.10.1', 'DIRECT'],
        ['printer.local', 'DIRECT'], ['printer', 'DIRECT'],
        ['1.1.1.1', publicProxy]
    ].forEach(function (entry) {
        var result = FindProxyForURL('http://' + entry[0] + '/', entry[0]);
        if (result !== entry[1]) throw new Error('Wrong PAC route for ' + entry[0] + ': ' + result);
    });
    return 'PASS: target subnet uses UniVPN without direct fallback; other private/public routes preserved';
}
JAVASCRIPT
