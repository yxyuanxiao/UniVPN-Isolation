function isIPv4Literal(host) {
    return /^\d+\.\d+\.\d+\.\d+$/.test(host);
}

function FindProxyForURL(url, host) {
    var address = isIPv4Literal(host) ? host : dnsResolve(host);

    // Only this exact subnet is offered to the isolated UniVPN SOCKS service.
    // DIRECT is the fail-open fallback when the container is stopped or when
    // the laptop is already connected to the internal network.
    if (address && isInNet(address, "10.10.128.0", "255.255.255.0")) {
        return "SOCKS5 127.0.0.1:15902; SOCKS 127.0.0.1:15902; DIRECT";
    }

    // Preserve direct access to all other local/private destinations.
    if (isPlainHostName(host) ||
        (address && isInNet(address, "10.0.0.0", "255.0.0.0")) ||
        (address && isInNet(address, "172.16.0.0", "255.240.0.0")) ||
        (address && isInNet(address, "192.168.0.0", "255.255.0.0")) ||
        shExpMatch(host, "*.local")) {
        return "DIRECT";
    }

    // Keep the user's existing Clash Verge proxy behavior for public traffic.
    return "PROXY 127.0.0.1:7897; SOCKS5 127.0.0.1:7897; DIRECT";
}
