---
name: isolate-univpn-apple-container
description: Isolate LeagSoft/Huawei Security Alliance UniVPN inside Apple Container on an Apple-silicon Mac so its tunnel, default route, DNS, and reconnect behavior do not take over macOS. Build or migrate the native macOS menu bar App with start, restart, PAC recovery, noVNC login, traffic visibility, and the supplied icon. Use for UniVPN conflicts with other VPNs or proxies, unexplained VPN-unreachable states, selective access to a private IPv4 subnet such as 10.10.128.0/24, HTTP 502/PAC routing failures, loopback-only SOCKS/PAC bridging, migration to another M-series Mac, verification, troubleshooting, or complete rollback.
---

# Isolate UniVPN with Apple Container

Contain UniVPN's network mutations in an ARM64 Linux micro-VM and expose only a subnet-restricted TCP proxy to macOS. Preserve the user's existing VPN, proxy, DNS, routes, auto-login configuration, and container workloads unless the user explicitly asks to change them.

## Non-negotiable constraints

- Require Apple silicon and a native `linux/arm64` UniVPN package. Do not use x86_64 UniVPN under Rosetta; the tested x86 build produced repeated `select error(-1 4)` failures.
- Never place usernames, passwords, cookies, tokens, or private certificates in prompts, shell history, images, build contexts, logs, documentation, or skill files. Let the user enter credentials in the isolated GUI. Redact secrets already present in context.
- Preserve macOS UniVPN auto-login. Do not uninstall the host app, delete `~/.UniVPN`, disable its launch items, or change `AutoLogin` lines unless explicitly requested.
- Do not suppress an untrusted-server-certificate warning. Pause for the user to inspect and click Continue.
- Bind noVNC and SOCKS only to `127.0.0.1`.
- Enforce the requested destination CIDR twice: in host PAC selection and in the container-side Dante ACL. Default to `10.10.128.0/24` only for this known deployment; confirm or discover the subnet elsewhere.
- Treat the proxy as TCP-only. Do not claim that ICMP, UDP, or proxy-unaware applications are covered.
- Do not delete `utun` interfaces. Their count does not equal the number of active VPNs.
- Inventory before mutation. If validation fails, restore host networking and remove only artifacts created during this attempt.
- Do not delete a persistent UniVPN configuration volume without explicit permission; it contains auto-login state.

## Load the relevant references

- Read [references/architecture.md](references/architecture.md) before designing or explaining the topology.
- Read [references/implementation.md](references/implementation.md) before installing, rebuilding, or migrating the solution.
- Read [references/menubar-app.md](references/menubar-app.md) before building, packaging, migrating, or diagnosing the menu bar App, its icon, restart/PAC controls, or traffic window.
- Read [references/rollback-and-troubleshooting.md](references/rollback-and-troubleshooting.md) before cleanup, rollback, or diagnosis.

Do not load all references when the request is only a status explanation.

## Workflow

### 1. Establish scope and baseline

Determine:

- target CIDR and representative internal TCP endpoint;
- UniVPN gateway and connection profile name without exposing credentials;
- whether direct internal access must work while the container is stopped;
- existing proxy product and local ports;
- whether the user wants a fresh installation, migration of a working bundle, diagnosis, rollback, or a native menu bar App;
- the intended final project root if building an App, because the bundle records it.

Run the read-only preflight script first:

```zsh
scripts/preflight.sh
```

Capture its output in an attempt-specific directory if making changes. Also inventory all existing Apple containers, images, volumes, the current network service, PAC URL/state, bypass domains, default route, DNS, Network Extensions, and UniVPN processes. Never infer ownership from an interface name alone.

### 2. Choose the least invasive path

Use this order:

1. Reuse a verified installation bundle already present on the Mac.
2. Migrate a verified bundle from another Apple-silicon Mac, rechecking executable architectures and checksums.
3. Build from official Apple Container and UniVPN ARM64 release artifacts.

Do not install Homebrew, Docker Desktop, a second hypervisor, or unrelated packages merely for convenience. Apple Container is the intended boundary.

If the host is not Apple silicon, does not meet Apple Container's current supported macOS requirements, or no trustworthy native ARM64 UniVPN artifact exists, stop and report that this isolation path is not validated. Then execute rollback for any artifacts created in the attempt.

### 3. Build the isolated runtime

Follow [references/implementation.md](references/implementation.md). The finished design must include:

- Ubuntu ARM64 base and native ARM64 UniVPN files;
- Xvfb, Openbox, and xcompmgr started before UniVPN so its transparent windows render instead of appearing black;
- x11vnc on internal port `5901`, plus xdotool only for restoring a hidden main window;
- websockify/noVNC on internal port `6080`;
- Dante on internal port `5900`, external interface `cnem_vnic`;
- a persistent named volume mounted only at UniVPN's configuration directory;
- `CAP_NET_ADMIN` for route repair inside the container;
- a management policy-routing table that remains reachable after UniVPN changes its default route;
- an explicit host route to the UniVPN gateway through `eth0`;
- loopback-only host publishes, using `15902→5900` and `16080→6080` unless occupied;
- a PAC that selects only the target CIDR, preserves the existing public proxy, and restores direct access when stopped.

Parameterize the gateway, CIDR, host ports, existing public proxy, container name, and volume name. Do not blindly reuse values from the known deployment.

### 4. Build the native menu bar App when requested

Follow [references/menubar-app.md](references/menubar-app.md). Prefer the checksummed source template in `assets/` over recreating the App. Install it with:

```zsh
scripts/install-menubar-app.sh /path/to/UniVPN-Isolation
```

Use `--no-build` when the container name, gateway, ports, CIDR, public proxy, or project root differs from the known deployment; adapt all linked runtime, PAC, and App values first. The installer must not overwrite an existing App source tree.

Retain these invariants: gateway/NAT readiness before a clean UniVPN retry, manual certificate confirmation, restricted-SOCKS readiness before PAC activation, PAC served at a loopback HTTP URL rather than `file://`, exact proxy-state restoration, and preservation of the configuration volume. Treat the traffic UI as a view of Dante TCP logs, not a system-wide packet monitor.

### 5. Hand off interactive login

Start the container, wait for noVNC, and open the loopback URL. Tell the user exactly when manual action is needed. Allow UniVPN auto-login data to persist in the named volume. Never type or retrieve the user's credentials.

Verify visually that the UniVPN window or certificate dialog is rendered, not a black rectangle. A window guard may map and raise the exact `^UniVPN$` main window when it is hidden, but must not continuously cover warning, login, or certificate dialogs.

Some UniVPN builds keep the main X11 window technically viewable while drawing it fully transparent after a successful connection. If a second, timeout-bounded invocation of the same native UniVPN binary is proven to activate the existing single instance without creating another process, invoke it once when `cnem_vnic` transitions from absent to present. Do not poll it continuously.

The certificate confirmation may recur after every container start. Treat this as an intentional security boundary, not a bug to bypass.

### 6. Enable host selection only after readiness

Do not enable PAC before noVNC is reachable. Enable the target-subnet PAC only after a complete restricted-SOCKS readiness probe succeeds. For the known App, publish the current PAC through noVNC/websockify at `http://127.0.0.1:16080/univpn.pac`, then explicitly reload it after SOCKS is ready. Do not use a local `file://` PAC.

Record the active network service before changing it. Restore the exact previous PAC state, URL, proxies, and bypass list on stop. Do not assume the service is named `Wi-Fi`.

### 7. Verify both positive and negative properties

Run:

```zsh
scripts/verify-isolation.sh \
  /path/to/UniVPN-Isolation \
  10.10.128.1 \
  80
```

Also verify manually:

- `container inspect` reports `linux/arm64`, Rosetta false, `CAP_NET_ADMIN`, loopback-only published ports, and the expected named volume;
- `cnem_vnic` exists only inside the container when connected;
- Dante starts only after `cnem_vnic` has an address;
- an allowed target receives a different SOCKS result from a public target blocked by ACL;
- macOS default route and DNS remain on the original physical/network service;
- the host UniVPN is not simultaneously connected;
- stopping the container restores the previous host proxy state;
- direct access to the target subnet works when already on the internal network and the container is stopped.
- when present, the App bundle passes `plutil` and `codesign` verification, resolves the intended project root, and uses the loopback HTTP PAC;
- the App's restart path preserves the named volume and refuses to interrupt unrelated running Apple containers;
- the traffic window reflects Dante TCP logs and clearly excludes DIRECT, other-proxy, UDP, and ICMP traffic.

A connection-refused response from an allowed internal IP can prove the SOCKS path reached the target, but it does not prove the application service itself is healthy. State that distinction.

### 8. Deliver and document

Create a user-facing `README.md` next to the start/stop scripts. Include daily use, topology, exact ports, limitations, security boundary, verification evidence, troubleshooting, rollback, and upstream sources. Never include credentials.

Install this skill under `${CODEX_HOME:-$HOME/.codex}/skills/isolate-univpn-apple-container` unless the user chooses another location. Validate it with the skill-creator validator after edits.

## Stop conditions

Stop and ask for direction before:

- deleting a persistent config volume;
- disabling or uninstalling the host UniVPN;
- overriding certificate trust;
- changing a subnet, gateway, or public-proxy policy that was not discovered or confirmed;
- replacing existing Apple Container resources with colliding names;
- applying a system-wide L3 route or packet filter beyond the proxy-based scope.

## Known working deployment values

Use these only as a reference, never as universal defaults:

```text
Container: univpn-isolation
Image: localhost/univpn-isolation:arm64-final
Volume: univpn-config
noVNC: 127.0.0.1:16080 -> 6080
Restricted SOCKS: 127.0.0.1:15902 -> 5900
Allowed target: TCP 10.10.128.0/24
Public proxy preserved: 127.0.0.1:7897
PAC URL: http://127.0.0.1:16080/univpn.pac
Apple Container CLI: 1.3.0
UniVPN package: 10781.19.0.1214, ARM64
Menu bar App template: 0.2.4 (build 7), ARM64
```
