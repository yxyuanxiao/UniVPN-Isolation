# Architecture and invariants

## Desired traffic flow

```text
proxy-aware macOS application
    |
    +-- target CIDR ---> loopback HTTP PAC ---> loopback SOCKS
    |                                             |
    |                                      Apple Container
    |                                             |
    |                                      Dante ACL (same CIDR)
    |                                             |
    |                                        cnem_vnic
    |                                             |
    |                                      private network
    |
    +-- other private CIDRs ------------------> DIRECT
    |
    +-- public destinations ------------------> existing public proxy or DIRECT

macOS route table and DNS --------------------> unchanged
```

UniVPN is allowed to replace the default route and DNS inside its own Linux micro-VM. It must not run on macOS at the same time as the isolated instance.

## Why a proxy bridge is used

Apple Container gives each Linux container its own lightweight VM and network namespace. A loopback-published SOCKS service crosses the VM boundary without adding another macOS VPN tunnel or global route. PAC supplies destination selection for proxy-aware applications.

This is deliberately not a transparent L3 tunnel:

- SOCKS/Dante handles TCP `CONNECT` only in this setup.
- `ping`, raw sockets, and UDP do not traverse it.
- applications that ignore macOS system proxy settings need an explicit SOCKS setting.
- internal IP literals are reliable; internal-only DNS names require explicit PAC suffix rules or another DNS design.

## Defense in depth

Enforce the destination at two layers:

1. PAC chooses the target CIDR.
2. Dante `socks pass` permits only the same CIDR, followed by an unconditional block.

Publish both noVNC and SOCKS on `127.0.0.1`, never `0.0.0.0`. Keep no credentials in the image. Persist GUI configuration and auto-login only in a named volume.

## Surviving UniVPN route takeover

When UniVPN connects, it may replace Linux's default route with `cnem_vnic`. That can break replies for Apple Container port forwarding and can make the VPN gateway recursively route through the VPN.

The entrypoint must repeatedly:

1. discover the container's `eth0` address, connected subnet, and gateway;
2. populate a private policy-routing table with that subnet and an `eth0` default route;
3. add a high-priority rule for traffic destined to the Apple Container management subnet;
4. pin the UniVPN gateway `/32` route through the original `eth0` gateway;
5. start Dante only after `cnem_vnic` has a global IPv4 address;
6. stop Dante when `cnem_vnic` disappears.

Dante's `external` interface must be `cnem_vnic`; otherwise accepted traffic can escape through the ordinary container interface.

## Port layout

The known working layout intentionally separates VNC and SOCKS:

| Purpose | Container | Host |
|---|---:|---:|
| x11vnc backend | 5901 | not published |
| restricted Dante SOCKS | 5900 | 127.0.0.1:15902 |
| noVNC/websockify | 6080 | 127.0.0.1:16080 |

x11vnc must specify both `-rfbport 5901` and `-rfbportv6 5901`, then listen on `127.0.0.1` and `::1`. Without the explicit IPv6 port, x11vnc can open an unexpected listener that conflicts with Dante.

## PAC policy

For the known deployment:

1. Resolve IPv4 literals directly.
2. If the destination is within `10.10.128.0/24`, return the restricted SOCKS endpoint, optionally followed by `DIRECT` for fail-open/direct-intranet behavior.
3. Return `DIRECT` for other local/private destinations.
4. Return the user's existing Clash/proxy endpoint for public traffic.

Serve the PAC from the loopback-only noVNC/websockify HTTP endpoint, such as `http://127.0.0.1:16080/univpn.pac`, and copy the current source PAC into the container after every start or restart. Do not use `file://`: a browser that does not load or refresh it may fall through to the public proxy, producing an HTTP 502 for an internal target even when restricted SOCKS is healthy. Activate or reload PAC only after a complete SOCKS readiness probe.

Record and restore the exact pre-existing PAC state and bypass domains. Do not hardcode `Wi-Fi`; map the current default interface to its network service.

## Menu bar control plane

The optional native App is a control plane, not the network boundary. It snapshots proxy state, orchestrates Apple Container, exposes noVNC for manual login, waits for the VPN gateway and Dante, publishes/reloads PAC, and renders recent Dante log entries. The container network namespace, Dante ACL, loopback publishes, and persistent named volume remain the security and state boundaries.

On a cold Apple Container start, vmnet NAT can accept management traffic before the real VPN gateway is reachable. The App must wait for the gateway and may restart only the isolated container once so UniVPN retries on a stable path. It must not restart the Apple Container system service while unrelated containers are running.

## `utun` interpretation

`utun` interfaces are allocated by macOS Network Extension and system features. Numbering is historical and sparse. Several interfaces can exist without several connected VPNs. Diagnose ownership using processes, system extensions, route entries, DNS resolvers, and active Network Extension state. Never try to delete arbitrary `utun` interfaces as cleanup.
