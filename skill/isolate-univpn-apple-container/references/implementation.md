# Implementation and migration procedure

Use this reference for a fresh Apple-silicon Mac or when rebuilding the proven bundle. Adapt all environment-specific values.

## 1. Preconditions

- Confirm `uname -m` is `arm64`.
- Check Apple Container's current macOS support policy at <https://github.com/apple/container>.
- Prefer the current official release from <https://github.com/apple/container/releases>.
- Obtain UniVPN from the vendor page: <https://webtest.leagsoft.com/doc/article/103107.html>.
- Select the native Linux ARM64 build, not the macOS package and not the Linux x86_64 build.

The known working UniVPN artifact is version `10781.19.0.1214`, vendor MD5 `f8fc060b38106c37168f6741b257592b`, local SHA-256 `b9a95b722453fc766ce8bdfa3dd4a1795ccac9e0bc024a1329f1961f3d9e307c`. Treat these values as version-specific and re-check the official page on every download.

Verify the Debian package's control metadata says `Architecture: arm64`. Verify every additional ELF library with `file`; do not mix x86_64 and AArch64.

## 2. Install Apple Container conservatively

Use the official signed installer when macOS validates it. Before installation:

1. download to an attempt-specific temporary directory;
2. compare SHA-256 with the GitHub release asset digest;
3. run `pkgutil --check-signature` and `spctl -a -vv -t install`;
4. do not override Gatekeeper when validation fails.

Apple issue <https://github.com/apple/container/issues/1682> records cases where release bytes matched GitHub's digest but package-signature checks failed. In such a case, stop and ask before proceeding. A user-local extraction of the verified package payload can avoid a system-wide install, but it is a deliberate workaround and must not be silently chosen.

When using a user-local runtime, keep `bin/container` and the matching `libexec` tree together. Never copy only the CLI binary. Confirm `container --version`, then run a harmless system start/list/stop smoke test.

## 3. Prepare the ARM64 build context

The context needs:

```text
Containerfile
entrypoint.sh
danted.conf
univpn-data-root.tar
libgmcrypto.so
```

Extract the Debian `data.tar.*` member without running its maintainer scripts on macOS. Archive the extracted root tree as `univpn-data-root.tar`. Obtain `libgmcrypto.so` from a trusted ARM64 vendor/runtime source and verify it is an AArch64 ELF shared object. Do not download an unverified replacement from a random mirror.

Use Ubuntu 22.04 ARM64 or another tested compatible ARM64 base. Install only runtime dependencies: Dante, iproute2, X11 libraries, Xvfb, Openbox, xcompmgr, xdotool, x11vnc, noVNC, websockify, and minimal process/debug utilities.

## 4. Implement the entrypoint

The entrypoint must:

- start Xvfb on a private display;
- remove only exact stale display lock/socket paths from its previous clean stop;
- set a visible root background, then start Openbox and `xcompmgr -n` before UniVPN creates any window;
- fail startup if Openbox or xcompmgr immediately exits;
- start x11vnc on `5901` with explicit IPv4 and IPv6 RFB ports;
- start websockify `6080 -> 127.0.0.1:5901`;
- build the management policy route and pin the confirmed UniVPN gateway through `eth0`;
- monitor `cnem_vnic` and start/stop Dante with the VPN interface;
- launch UniVPN with the native ARM64 libraries and wait on its process;
- periodically map and raise the exact-title `^UniVPN$` main window only when hidden; never repeatedly raise it over dialogs;
- if the tested build makes its connected main window fully transparent, invoke the proven timeout-bounded UniVPN single-instance activation once when `cnem_vnic` changes from absent to present, and verify the process count remains one;
- kill only its own child processes on exit.

For readiness reporting, prefer a complete SOCKS5 request. In the known deployment, requesting a public IP through the restricted proxy must return curl code 97 because Dante rejects it; that response proves both SOCKS processing and the negative ACL. A raw TCP connect to a published Apple Container port can succeed even when no process is listening in the guest, so `nc -z` alone produces false positives. Avoid hand-rolled `nc` greetings on macOS unless stdin lifetime and BSD `printf` byte escaping are handled and tested.

Parameterize the gateway. Never reuse `210.75.253.1` unless it is discovered or confirmed for the target environment.

## 5. Restrict Dante

Use `internal: eth0 port = 5900` and `external: cnem_vnic`. Permit clients reaching the published port, but permit SOCKS `connect` only to the requested CIDR, then block everything else. Log connect, disconnect, and errors during validation.

Do not add `0.0.0.0/0` as a SOCKS pass rule. Do not expose the host publish beyond loopback.

## 6. Build and create

For Apple Container 1.3.0, the known command shape is:

```zsh
container build --arch arm64 \
  --tag localhost/univpn-isolation:arm64-final \
  /path/to/build-context

container volume create univpn-config

container create \
  --name univpn-isolation \
  --arch arm64 \
  --cpus 4 \
  --memory 1G \
  --init \
  --cap-add CAP_NET_ADMIN \
  --network default,mtu=1280 \
  --volume univpn-config:/root/.config/cn.com.huawei-security-commercial-alliance.univpn \
  --publish 127.0.0.1:15902:5900 \
  --publish 127.0.0.1:16080:6080 \
  localhost/univpn-isolation:arm64-final
```

Before creating resources, check for name and port collisions. If a volume already exists, do not assume ownership. If migrating existing auto-login state, copy it only through a deliberate, user-approved method and preserve permissions.

## 7. Host start/stop scripts

The start script should:

1. resolve its own directory;
2. detect the current default interface and corresponding network service;
3. record the service and the complete pre-change proxy state;
4. start Apple Container and the named container;
5. wait for noVNC, publish the current PAC into noVNC/websockify, and wait for the restricted SOCKS endpoint with a complete SOCKS probe;
6. enable or reload the loopback HTTP PAC only for the active service after SOCKS is ready;
7. remove `10.0.0.0/8` from bypass only while needed so `10.10.128.0/24` reaches PAC;
8. open the loopback noVNC URL.

The stop script should restore the recorded state exactly, stop the container, and optionally stop Apple Container only if this workflow started it and no unrelated workloads need it. A static reconstruction of the old proxy state is acceptable only for a single known machine and must be documented as such.

Use `http://127.0.0.1:16080/univpn.pac` for the known port layout. Do not use `file://`, because browser PAC loading/caching can fail and silently route internal traffic to the existing public proxy.

## 8. Native menu bar App

After the runtime passes verification, follow [menubar-app.md](menubar-app.md). The skill's checksummed source template can reproduce the known ARM64 App with start, restart, PAC reload, stop, noVNC login, recent Dante traffic, and the selected icon:

```zsh
scripts/install-menubar-app.sh /path/to/UniVPN-Isolation
```

Use `--no-build` and adapt constants before building on a different deployment. Build from the final project location, because `Info.plist` records the absolute runtime root. Keep the source-only template free of credentials, vendor packages, `.build`, and `dist` output.

## 9. Verification gate

Do not call the solution complete until all of these are true:

- noVNC is reachable locally;
- the user can manually confirm the server certificate;
- UniVPN connects and `cnem_vnic` receives an IPv4 address;
- restricted SOCKS appears only after VPN connection;
- target-CIDR traffic is accepted;
- public traffic through this SOCKS is denied by Dante;
- macOS default route, DNS, and other VPN/proxy behavior remain unchanged;
- stop restores the original proxy state;
- restart preserves auto-login state;
- a complete stop/start test does not revive the x11vnc IPv6 port conflict.
- the browser receives the loopback HTTP PAC and the internal URL does not fall through to the public proxy;
- if present, the App bundle's `Info.plist` and ad-hoc signature validate and its traffic UI matches Dante logs.
