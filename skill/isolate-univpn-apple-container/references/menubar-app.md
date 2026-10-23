# Native menu bar App

Use this reference when the user asks to package the isolated runtime as a macOS App, put controls in the menu bar, add restart or PAC recovery, inspect forwarded traffic, use the supplied icon, or reproduce the App on another Apple-silicon Mac.

## Preconditions and installation

Build the App only after the container runtime itself has passed the isolation verification gate. The target project root must already contain:

```text
runtime/bin/container
univpn.pac
stop.command
```

It also needs Apple silicon, macOS 13 or later, and an installed Swift toolchain. The skill contains a source-only, checksummed template. It does not contain `.build`, `dist`, credentials, cookies, the UniVPN package, or the Apple Container runtime.

For the known deployment, install and build it in the real project directory:

```zsh
scripts/install-menubar-app.sh /path/to/UniVPN-Isolation
```

The installer refuses to overwrite an existing `app/` directory or `build-menubar-app.command`. Review and merge an existing App manually.

If any deployment value differs, extract without building:

```zsh
scripts/install-menubar-app.sh --no-build /path/to/UniVPN-Isolation
rg -n 'univpn-isolation|210\.75\.253\.1|15902|16080|10\.10\.128|7897' \
  /path/to/UniVPN-Isolation/app \
  /path/to/UniVPN-Isolation/univpn.pac \
  /path/to/UniVPN-Isolation/build-context
```

Adapt the container name, VPN gateway, SOCKS/noVNC ports, target CIDR, public proxy, and project root consistently. Re-run the runtime verification gate before building. Do not blindly reuse the known values.

## Included template

`assets/menubar-app-template.tar.gz` contains:

- a Swift Package using SwiftUI and AppKit;
- a menu bar controller plus traffic and login windows;
- privileged `networksetup` calls through macOS Authorization Services;
- runtime/PAC/proxy-state orchestration;
- the exact requested `IvacyVPN-T6s4AC9Km1.icns` asset;
- `build-menubar-app.command` for an ARM64 release build and ad-hoc signed `.app` bundle.

Validate the immutable template before installing it:

```zsh
scripts/validate-menubar-template.sh
```

The icon was selected from <https://macosicons.com/zh?icon=T6s4AC9Km1>. Confirm that the intended redistribution and trademark use are acceptable for the target environment; substitute another user-approved `.icns` when necessary.

## Required lifecycle behavior

Start must:

1. capture the exact active network service, PAC state, URL, and bypass domains;
2. start Apple Container and the isolated UniVPN container;
3. wait for noVNC;
4. probe the real VPN gateway while Apple Container NAT warms up;
5. if the first gateway probe fails, wait until it succeeds and restart only the isolated container once so UniVPN gets a clean connection attempt;
6. copy the project PAC to `/usr/share/novnc/univpn.pac` so websockify serves the current file;
7. show noVNC for login and manual certificate confirmation;
8. wait for the restricted SOCKS listener, not merely a published TCP port;
9. then enable or refresh PAC.

Restart must preserve the named configuration volume and proxy recovery snapshot. It must refuse to restart Apple Container's system service while unrelated containers are running. After a backend restart, wait for gateway readiness, optionally restart only the isolated container once, publish PAC again, wait for restricted SOCKS, and reload PAC if it was active.

Stop must first restore the saved proxy state exactly. If restoration fails, retain the snapshot and report recovery instructions instead of deleting evidence. Stop only resources owned by this workflow; never remove the persistent UniVPN configuration volume.

## PAC and the HTTP 502 failure mode

The App must use this loopback HTTP URL for the known port layout:

```text
http://127.0.0.1:16080/univpn.pac
```

Do not regress to a `file://` PAC. Some browsers fail to apply a local-file PAC reliably and then fall through to the user's public proxy. In the known deployment, an internal URL could return HTTP 502 from Clash on `127.0.0.1:7897` even though direct SOCKS on `127.0.0.1:15902` worked. Serving PAC through the already loopback-bound noVNC/websockify endpoint and explicitly reloading it avoids that ambiguity.

Keep both noVNC/PAC HTTP and restricted SOCKS bound to `127.0.0.1`. Copy the current PAC into the container after every start and restart. Never enable PAC before the restricted SOCKS readiness gate has completed.

When diagnosing a browser-only 502, compare the same internal URL through:

1. explicit restricted SOCKS `127.0.0.1:15902`;
2. the current public proxy such as `127.0.0.1:7897`;
3. direct access;
4. the browser after PAC reload.

If restricted SOCKS succeeds but the public proxy returns 502, the VPN path is healthy and PAC was not selected or applied. Do not rebuild the container or erase login state for that symptom.

## Traffic window limitations

The traffic window parses the tail of `/tmp/danted.log` and shows recent TCP `connect` sessions accepted, rejected, or errored by the restricted proxy. Therefore it reports only traffic that actually reached `127.0.0.1:15902` and Dante. It cannot report:

- destinations selected as `DIRECT` by PAC;
- public traffic handled by Clash or another proxy;
- UDP, ICMP/ping, raw sockets, or proxy-unaware applications;
- browser tabs or user identities unless the application itself logs them.

State these limits in the UI and documentation. Do not claim it is a system-wide packet monitor.

## Build and verification

Build only from the final project path because the bundle records `UniVPNProjectRoot` in `Info.plist`:

```zsh
/path/to/UniVPN-Isolation/build-menubar-app.command
plutil -lint '/path/to/UniVPN-Isolation/dist/UniVPN Isolation.app/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 \
  '/path/to/UniVPN-Isolation/dist/UniVPN Isolation.app'
```

The template uses ad-hoc signing, so Gatekeeper distribution outside the local Mac may require a Developer ID signature and notarization. Rebuild when the project root moves instead of copying a bundle with a stale absolute root.

Also verify:

- the App status distinguishes noVNC readiness from restricted SOCKS readiness;
- start, restart, manual `重新加载分流 PAC…`, and stop all work;
- the certificate prompt remains manual;
- the target endpoint works through restricted SOCKS and a public target is denied;
- the browser uses the loopback HTTP PAC for the target URL;
- macOS default route and DNS remain unchanged;
- stop restores the exact previous PAC URL/state and bypass list;
- the traffic window matches Dante logs and states its visibility limits.

## Maintaining the template

When a newer verified App becomes the reference implementation:

1. update source files and the version/build values in `app/Info.plist` in the real project;
2. verify the real project App in place;
3. rebuild `assets/menubar-app-template.tar.gz` from source files only, excluding `.build` and `dist`;
4. update `assets/menubar-app-template.sha256`;
5. run `scripts/validate-menubar-template.sh` and the skill-creator validator;
6. record the new behavior and migration notes here.

Do not place credentials, config-volume contents, downloaded vendor packages, or machine-specific proxy snapshots in the skill archive.
