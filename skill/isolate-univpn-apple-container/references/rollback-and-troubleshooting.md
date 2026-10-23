# Rollback and troubleshooting

## Rollback ledger

Before mutation, record:

- attempt directory and downloaded files;
- packages or runtimes installed, including exact paths;
- Apple Container resources created by this attempt;
- pre-existing containers, images, volumes, and networks;
- active macOS network service;
- complete `scutil --proxy` output;
- PAC enabled state and URL;
- HTTP, HTTPS, and SOCKS proxy endpoints;
- proxy bypass domains;
- default route, DNS, and relevant private routes;
- host UniVPN running state and only the non-secret `AutoLogin` setting.

Never capture passwords or the contents of credential stores.

## Rollback order

1. Disable the attempt's PAC and restore the exact previous proxy configuration.
2. Confirm default route and DNS match the baseline.
3. Stop test containers created by the attempt.
4. Delete only test containers and images whose ownership is proven by the ledger.
5. Preserve persistent UniVPN configuration volumes unless the user explicitly authorizes deletion.
6. Stop Apple Container only if the attempt started it and no unrelated containers use it.
7. Remove the attempt-specific user-local runtime and build directory if they were created for this test.
8. Uninstall additional software installed solely for the attempt, using its documented uninstaller when available.
9. Confirm the original host UniVPN remains installed and its auto-login setting is unchanged.

Do not prune globally. Do not remove unknown volumes, images, Network Extensions, launch agents, or `utun` interfaces.

## noVNC shows “cannot connect”

Check in this order:

1. Host publish is loopback `16080 -> 6080`.
2. websockify listens on container port 6080.
3. x11vnc listens on `127.0.0.1:5901` and `[::1]:5901`.
4. Xvfb has created its display socket.
5. Container logs and `/tmp/websockify.log` do not show an address conflict.

If x11vnc unexpectedly binds another IPv6 port, set both `-rfbport 5901` and `-rfbportv6 5901`. Keep Dante on 5900.

## noVNC connects but the UniVPN view is black

Check that `openbox`, `xcompmgr -n`, and UniVPN are all running and that Openbox/xcompmgr started before UniVPN. A solid X root background plus a fully rendered certificate or login dialog confirms composition is working. A black UniVPN rectangle means the transparent window was created without a compositor; restart the container after fixing startup order rather than installing packages only into the mutable running container.

Use xdotool only to map the exact-title `^UniVPN$` main window when it is hidden. Do not continuously raise it, because that can cover certificate and login dialogs.

If `xwininfo` says the main window is `IsViewable` and `WM_STATE` is normal but the desktop is still blank, UniVPN may be drawing the connected window fully transparent after minimizing to its tray. First prove that a timeout-bounded second invocation activates the existing single instance and that the UniVPN process count remains one. Then invoke that activation once on the `cnem_vnic` absent-to-present transition. Do not add a periodic activation loop, and do not require a full desktop panel only to work around this state.

## noVNC works but SOCKS is absent

This usually means `cnem_vnic` is absent or has no IPv4 address. Check the GUI for the manual certificate prompt and connection state. Check the entrypoint's interface monitor and Dante log. Do not start Dante on `eth0` as a workaround; that breaks the isolation guarantee.

## SOCKS dies when VPN connects

Inspect the container route tables and policy rules. Ensure the Apple Container management subnet has a high-priority lookup in the private table and that the VPN gateway `/32` remains routed via `eth0`. Verify replies to published-port clients do not follow `cnem_vnic`.

## UniVPN says “Fail to establish the VPN connection” after start

First probe the real VPN gateway from inside the container, not only the noVNC or published host ports. A cold `container system start` can restore management connectivity before vmnet NAT can reach the gateway; UniVPN may consume its single automatic attempt during that warm-up.

If the gateway is initially unreachable, leave host proxy settings unchanged, wait until the gateway succeeds, then restart only the isolated container once. Do not delete the persistent configuration volume, reinstall UniVPN, or reboot macOS as the first response. If the gateway never becomes reachable, inspect the host's current network, gateway address, container route pin, and vendor availability.

The native App template includes this bounded NAT warm-up recovery. Its manual restart control also refuses to restart Apple Container's system service if unrelated containers are running.

## Target is allowed but service still fails

Distinguish layers:

- SOCKS code indicating ACL denial means the target rule is wrong or Dante did not match it.
- SOCKS accept followed by connection refused means routing reached the target but the remote port is closed.
- timeout after SOCKS accept suggests VPN route, firewall, or remote reachability issues.
- a browser-only failure may be PAC caching or an application that ignores system proxy settings.

Flush/reload PAC only after inspecting the current proxy state. Do not reboot as the first diagnostic step.

## Browser shows HTTP 502 for an internal IP

Test the identical URL through restricted SOCKS, the existing public proxy, and direct access. If `127.0.0.1:15902` reaches the target but a public proxy such as `127.0.0.1:7897` returns 502, the container/VPN path is healthy and the browser did not select the intended PAC rule.

Check that:

1. the configured PAC URL is `http://127.0.0.1:16080/univpn.pac`, not `file://`;
2. noVNC/websockify serves that path only on loopback;
3. the project PAC was copied to `/usr/share/novnc/univpn.pac` after the latest start;
4. the source and served PAC hashes match;
5. the restricted SOCKS readiness gate completed before PAC was enabled;
6. the App's `重新加载分流 PAC…` action toggles and restores the current active service's PAC.

Do not clear login state or rebuild the container merely for this symptom. Browser caches and applications that ignore macOS system proxy settings must be diagnosed separately.

## Public target succeeds through restricted SOCKS

Treat this as a security failure. Stop or unpublish the SOCKS endpoint immediately, inspect Dante rule order, confirm `external: cnem_vnic`, and do not re-enable PAC until a negative public-target test is blocked.

## Host networking changed

Compare current route, DNS, PAC, proxy endpoints, and bypass list to the baseline. The container may mutate its own route and DNS, never macOS's. If the host default route points to UniVPN or the host UniVPN process is active, stop the host client only if the user authorized it; otherwise report the conflict and ask.

## Auto-login disappeared

Check whether the expected named volume is still mounted at UniVPN's configuration directory. Do not recreate or delete it. If a new empty volume was accidentally mounted, stop and preserve both volumes for recovery. Never ask the user to paste credentials into a terminal or prompt.
