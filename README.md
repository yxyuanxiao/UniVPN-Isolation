# UniVPN Apple Container 隔离方案

本目录是一套已经在 Apple 芯片 Mac 上验证过的 UniVPN 隔离方案。Linux ARM64 版 UniVPN 在 Apple Container 的轻量 Linux 虚拟机中运行；它创建的虚拟网卡、默认路由、DNS 和自动重连都留在容器里，不接管 macOS 的全局流量。

当前只把 `10.10.128.0/24` 的 TCP 流量交给容器内 VPN。公网流量继续按原有 Clash Verge 设置处理，其他局域网地址保持直连。

> 账号、密码不会写入脚本、镜像或本文档。登录状态只保存在 Apple Container 命名卷 `univpn-config` 中。macOS 原版 UniVPN 的自动登录设置也没有被移除。

## 安装包

本项目现在可以生成 Apple 芯片 Mac 使用的 `.pkg`。安装后，菜单栏 App 位于 `/Applications/UniVPN Isolation.app`，运行支持文件位于 `/Applications/UniVPN-Isolation/`。

```zsh
./scripts/build-distribution.command
./scripts/verify-distribution.command
./scripts/run-self-tests.command
```

产物写入 `dist/release/`，同时生成 SHA-256 文件。安装后先运行 `/Applications/UniVPN-Isolation/setup-runtime.command`，它会校验并导入离线 OCI 镜像，只在不存在时创建持久卷与隔离容器，然后再打开菜单栏 App。完整说明见 [INSTALL.md](INSTALL.md)。

源码仓库不提交 Apple Container 运行时、UniVPN 厂商二进制、OCI 镜像、登录卷、Swift 缓存或安装包。这些本机发行输入由 `.gitignore` 隔离；有关第三方分发边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 日常使用

### 菜单栏 App

开发构建位于 `dist/UniVPN Isolation.app`，安装包版本位于 `/Applications/UniVPN Isolation.app`。打开后不会出现在 Dock；菜单栏盾牌图标会显示未启动、等待登录、已连接或故障状态。

这个 App 可以复制到 `/Applications`，编译时已经记录当前项目运行目录；如果以后移动整个 `UniVPN-Isolation` 目录，需要重新运行构建命令更新路径。

App 当前使用 [macOS Icons 上的 Ivacy VPN 图标（T6s4AC9Km1）](https://macosicons.com/zh?icon=T6s4AC9Km1)；原始 `.icns` 和预览 PNG 保存在 `app/Assets/`。之前的自绘图标和生成脚本仍保留为备份，但构建流程不再调用。

菜单提供：

- 启动与停止隔离 VPN；
- 在不改动宿主机代理和持久配置卷的前提下重启隔离连接与 Apple Container 网络后台；
- 在 App 内打开 UniVPN/noVNC 登录窗口；
- 查看实际进入容器 Dante SOCKS 的最近 TCP 目标 IP、端口和 ACL 结果；
- 刷新状态以及打开项目目录。

App 启动 VPN 前会把当前网络服务的 PAC URL、PAC 开关和代理绕过列表保存到 `~/Library/Application Support/UniVPN Isolation/proxy-before-start.json`。它会先显示登录窗口，等 `cnem_vnic` 与受限 SOCKS 真正就绪后再通过管理员授权启用并刷新 PAC，避免浏览器在 VPN 尚未连接时把 `127.0.0.1:15902` 记为不可用代理。PAC 由同一个回环 noVNC 服务通过 `http://127.0.0.1:16080/univpn.pac` 提供，避免 Chromium 忽略本地 `file://` PAC 后错误落到 Clash `7897`。该端点和 noVNC 一样只发布在本机 `127.0.0.1`。停止时通过 macOS 管理员授权原样恢复；恢复成功后才删除快照。

0.2.6 修复停止时 `** Error: The parameters were not valid.`：启动前未配置 PAC 地址时，通过 SystemConfiguration 删除 PAC URL 键并恢复关闭状态及绕过列表，避免向 `networksetup` 传入空 URL。恢复操作只修改本 App 管理的 PAC 和绕过字段，保留 Clash 的 HTTP、HTTPS、SOCKS 等其他配置。

如果 App 第一次打开时容器已经由旧 `start.command` 启动，它只观察该会话，不会伪造恢复快照。菜单里的“用旧脚本停止本次会话…”用于完成这一次过渡；之后由 App 启动的会话都由 App 精确恢复。

“重启隔离连接…”会先确认当前没有其他运行中的 Apple Container，再停止当前容器、重启 Apple Container 后台并重新启动同一个容器。它保留 `univpn-config` 卷以及 App 的代理恢复快照；重启后若再次出现服务器证书提示，仍需人工检查并确认。若检测到其他运行容器，App 会拒绝重启后台，避免中断无关工作。

0.2.7 起，是否代理由手动启停隔离 VPN 决定：启动并完成登录、启用本应用 PAC 后，`10.10.128.*` 的网页和 SSH 连接使用 UniVPN；停止并恢复代理设置后直连。仅打开菜单栏 App 不会启用代理。隔离已启用但 VPN 暂时断线时，目标网段连接失败，不自动回退直连，也不根据是否身处内网自动切换。连接恢复后可选择“重新加载分流 PAC…”并刷新页面。

某些冷启动中，Apple Container 的管理端口会先恢复，而公网 NAT 约需几十秒才可用。普通启动和重启流程都会检查真实 VPN 网关 `210.75.253.1:443`；若第一次检查时网关尚不可达，就等 NAT 就绪后只重启当前容器一次，再交还登录界面。这样可以避免 UniVPN 在公网出口未就绪时耗掉唯一一次自动拨号。

流量窗口只表示实际经过 `127.0.0.1:15902` 的 TCP 连接。它看不到 `DIRECT`、Clash 公网流量、UDP、ICMP，也不能据此判断整个 macOS 的总流量。

重新编译：

```zsh
./build-menubar-app.command
```

App 会记录编译时指定的运行根目录。开发构建默认使用当前项目目录；发行构建固定使用 `/Applications/UniVPN-Isolation`，因此不要把已安装的 App 单独移动到另一台 Mac 而不安装其支持目录。

### 启动

双击 `start.command`：

1. 输入一次 macOS 管理员密码，用于临时启用 PAC 分流。
2. 浏览器会打开 `http://127.0.0.1:16080/vnc.html?autoconnect=1&resize=scale`。
3. UniVPN 会沿用容器卷里的自动登录状态。
4. 若出现“不受信任的服务器证书”，请人工确认 `Continue`。本方案不会自动忽略证书警告。
5. 连接成功后访问 `10.10.128.xxx`。

noVNC 不需要密码；它只监听本机回环地址，其他设备不能连接。不要再使用旧的 `127.0.0.1:15900` 屏幕共享入口。

隔离桌面会保留 UniVPN 主窗口：Openbox 负责窗口管理，xcompmgr 负责 UniVPN 透明界面的正确合成；连接成功、`cnem_vnic` 刚出现时，窗口守护逻辑会通过 UniVPN 单实例入口唤回自动缩到托盘的主界面。该动作每次连接只执行一次，不会周期性抢焦点，也不会自动确认服务器证书或代替用户登录。

### 查看状态

双击 `status.command`，或在终端执行：

```zsh
./status.command
```

连接成功时应看到：

- noVNC：`127.0.0.1:16080` 已就绪
- 受限 SOCKS5：`127.0.0.1:15902` 已就绪
- 容器：`univpn-isolation` 为 running

`status.command` 会发起完整 SOCKS5 请求并确认公网目标被容器 ACL 拒绝，而不是只检查端口能否建立 TCP；因此证书尚未确认、VPN 未连接或公网限制失效时，不会误报“受限 SOCKS：已就绪”。

### 停止

双击 `stop.command`。它会：

1. 停止 `univpn-isolation`；
2. 停止 Apple Container 后台系统；
3. 关闭本方案的 PAC；
4. 恢复 Clash Verge 原来的代理绕过列表，包括 `10.0.0.0/8`。

容器停止后，`10.10.128.0/24` 不再转给 VPN。电脑已经直接接入内网时，可以不启动容器，直接访问该网段。

### SSH

`~/.ssh/config` 已为 `10.10.128.*` 安装永久规则，因此原有 SSH 命令和主机别名不需要改写：

```zsh
ssh -p 25899 root@10.10.128.2
ssh 10.10.128.2_main
```

规则调用本目录的 `ssh-proxy.command`：

- 本应用 PAC 分流开关已启用时，SSH 通过隔离容器的受限 SOCKS 连接；
- 隔离分流未启用时，SSH 直接连接，哪怕本地 SOCKS 端口仍在监听；
- 隔离分流已启用但 SOCKS 不可用时，连接失败，不自动改为直连；
- 该规则只匹配 `10.10.128.*`，不会影响其他 SSH 主机；
- `ping` 仍不会经过 SOCKS，因为它使用 ICMP 而不是 TCP。

只读检查当前 SSH 选择：`/usr/sbin/scutil --proxy | ./ssh-proxy.command --routing-mode`，输出为 `proxy` 或 `direct`。切换影响新建连接，已有 SSH 会话不会迁移路径。

## 数据流

```text
支持 macOS 系统代理的应用
          │
          ├─ 目标 10.10.128.0/24
          │       ↓
          │  127.0.0.1:15902 SOCKS5
          │       ↓
          │  Apple Container / Dante ACL
          │       ↓
          │  cnem_vnic / UniVPN
          │       ↓
          │  10.10.128.0/24
          │
          ├─ 其他私网地址 ───────────────→ DIRECT
          │
          └─ 公网 ──────────────────────→ Clash 127.0.0.1:7897

macOS 默认路由与 DNS ───────────────────→ 保持原样
```

这是应用代理分流，不是 macOS 上新增一条全局三层 VPN 路由。因此：

- 浏览器和遵循系统代理的应用会自动使用该方案。
- `ping`、UDP 和完全忽略系统代理的程序不会经过 SOCKS。
- 命令行程序可显式使用 `socks5h://127.0.0.1:15902`。
- 当前 PAC 主要面向 `10.10.128.xxx` 的 IP 地址。如果以后使用只能由内网 DNS 解析的域名，应单独增加域名规则。

## 已验证的安全边界

本方案有两道范围限制：

1. PAC 只把 `10.10.128.0/24` 交给本地 SOCKS。
2. 容器内 Dante 服务端再次硬性拒绝该网段之外的目标。

验证结果：

- 通过 SOCKS 请求 `10.10.128.1:80` 返回“目标端口拒绝”，说明请求已经穿过 SOCKS 并到达内网侧；
- 通过同一 SOCKS 请求 `1.1.1.1:80` 被 Dante 以规则拒绝；
- macOS 默认路由、DNS 和公网出口未改成 UniVPN；
- 两个宿主机端口都只发布在 `127.0.0.1`；
- macOS 原版 UniVPN 未同时运行。

## 当前固定配置

| 项目 | 值 |
|---|---|
| Apple Container CLI | `1.3.0`，commit `d6de569` |
| 容器 | `univpn-isolation` |
| 镜像 | `localhost/univpn-isolation:arm64-final` |
| 平台 | `linux/arm64`，未启用 Rosetta |
| 资源 | 4 CPU、1 GiB 内存、MTU 1280 |
| Linux capability | `CAP_NET_ADMIN` |
| 配置卷 | `univpn-config` |
| noVNC | `127.0.0.1:16080` → 容器 `6080` |
| 受限 SOCKS5 | `127.0.0.1:15902` → 容器 `5900` |
| 允许目标 | 仅 TCP `10.10.128.0/24` |
| 当前 UniVPN ARM64 包 | `10781.19.0.1214` |
| ARM64 包 MD5 | `f8fc060b38106c37168f6741b257592b` |
| ARM64 包 SHA-256 | `b9a95b722453fc766ce8bdfa3dd4a1795ccac9e0bc024a1329f1961f3d9e307c` |

MD5 与厂商当前下载页公布值一致；升级软件包时必须重新从厂商页面核对，不能沿用旧校验值。

## 文件说明

```text
UniVPN-Isolation/
├── README.md                 本文档
├── INSTALL.md                安装包、签名和首次初始化说明
├── THIRD_PARTY_NOTICES.md    第三方组件及分发边界
├── VERSION                   发行版本唯一来源
├── app/                      Swift 菜单栏 App 源码和图标
├── packaging/                macOS pkg 安装脚本
├── scripts/                  发行构建与静态验证脚本
├── skill/                    可复制给其他 Codex agent 的完整 skill
├── setup-runtime.command     新机器首次导入镜像并创建容器
├── start.command             启动容器、启用 PAC、打开 noVNC
├── stop.command              停止容器并恢复原代理绕过规则
├── status.command            只读状态检查
├── univpn.pac                10.10.128.0/24 / Clash / DIRECT 分流
├── runtime/                  本机 Apple Container 1.3.0（不进 Git）
├── vendor/                   本机 OCI 发行资产（归档不进 Git）
├── build/
│   ├── Containerfile
│   ├── entrypoint.sh         Xvfb、noVNC、管理路由、UniVPN 启动
│   ├── danted.conf           服务端网段 ACL
│   ├── libgmcrypto.so        ARM64 运行库（不进 Git）
│   ├── univpn-data-root.tar  ARM64 UniVPN 文件树（不进 Git）
│   └── univpn-*.deb          经校验的原始软件包（不进 Git）
└── state/                    本机运行状态（不进 Git）
```

## 关键实现细节

### 为什么必须用原生 ARM64

不要改用 x86_64 UniVPN 加 Rosetta。实测其核心进程会反复出现 `select error(-1 4)`，连接事件循环不可靠。镜像、UniVPN 可执行文件和 `libgmcrypto.so` 都应为 ARM64。

### 为什么需要管理路由保护

UniVPN 连接后会在容器内改默认路由。`entrypoint.sh` 使用独立策略路由表保留 Apple Container 管理网段，并把 VPN 网关固定经 `eth0` 访问，否则端口转发可能在 VPN 连接后突然变成“不可达”。

Dante 只有在 `cnem_vnic` 出现后才启动；VPN 断开时 SOCKS 也停止，避免错误地经容器普通出口转发。

### noVNC 的端口安排

x11vnc 使用容器内 `5901`，同时显式设置 `-rfbportv6 5901`；websockify 将 `6080` 转到 `127.0.0.1:5901`。Dante 单独使用 `5900`。不要让 x11vnc 的隐式 IPv6 listener 抢占 Dante 端口。

### `utun0` 到 `utun7` 是什么

macOS 的 `utun` 是系统和 Network Extension 创建的虚拟隧道接口。iCloud Private Relay、内容过滤器、代理/VPN、连续互通等都可能持有它们；编号不会在服务退出后立即“补洞”。看到 8 个 `utun` 不等于同时运行 8 个 VPN，也不要盲目删除。判断冲突应看进程、Network Extension、默认路由、DNS 和具体路由归属。

## 原 macOS 客户端的故障机制

以下结论来自本机 UniVPN 手册、客户端二进制中的路由模式字符串，以及已经脱敏的本机运行日志。它们解释了原客户端为什么会与现有网络环境冲突、为什么有时只有重启电脑才能恢复，也说明了本方案为什么把 UniVPN 整体放进 Apple Container。

### SSL VPN 的隧道分离不是客户端单方面决定的

本机手册给出的关键限制是：最常见的 SSL VPN 场景中，“隧道分离”策略由单位的 VPN 网关下发，客户端不能自行完整决定哪些网段进入隧道。客户端二进制确实包含“全路由”“手工路由”“分离路由”三套处理逻辑，但出现这些逻辑不代表普通用户可以在本机强制覆盖网关策略。

因此，本方案没有修改单位网关或伪造 UniVPN 自身的分离路由配置。选择性转发是在 UniVPN 外部实现的：UniVPN 可以在容器内部按网关要求接管容器网络，而 macOS 只通过 PAC 和受限 Dante SOCKS 把 `10.10.128.0/24` 的 TCP 请求送入容器。两层 ACL 还会阻止公网目标误入 VPN。

### 与 Clash 的冲突面

调查时 Clash Verge 的状态是“系统代理开启、TUN 关闭”。这意味着当时更不像两个三层虚拟网卡在争抢 macOS 默认路由；应优先检查 UniVPN 公网连接服务器、内网 IP 或内网域名是否被系统代理/PAC 错误接管，以及 UniVPN 断线后留下的路由是否使它自己的服务器失去出口。

当前方案把这两个风险拆开：UniVPN 公网网关在容器内被固定经 `eth0` 访问；macOS 侧 PAC 只把 `10.10.128.0/24` 交给容器，其余公网继续交给 Clash，其他私网保持直连。Clash 若以后启用 TUN，应重新运行隔离验证，不能沿用“只有系统代理”的判断。

### 为什么客户端还活着，却无法重新拨号

原生客户端启动后会拉起 `UniVPNPromoteService` 和 `UniVPNCS`；UI 与这两个后台组件通过本机 `29191` 端口组成一条 RPC 通信链。历史配置和日志也会被这些进程重新载入。任何一个组件状态失步，都可能出现 UI 仍在、但拨号链已经不能工作的假存活状态。

本机日志记录了完整的失败链：

1. 隧道掉线后反复出现 `ReConnect but GetVip Failed` 和 `nem module reconnect fail`。
2. 重启客户端时，旧服务仍占用 `29191`，新服务报告 `fail to Bind port`。
3. 随后 UI 报告 `UI and RPC connection failed`，所以只退出再打开界面并不能恢复后台链。

这解释了为什么过去重启整机有效：重启会同时结束残留服务、释放 `29191` 并清理异常路由；它并不证明必须重启 macOS 内核。日志分析只提取了配置键名、路由模式和错误码，本文档及 skill 都不保存账号、密码或原始未脱敏日志。

### “VPN 服务器可能无法到达”不是密码错误

该提示出现时，底层 socket 的 macOS `ErrorCode 51` 表示 `Network is unreachable`。结合前后的重连日志，故障顺序是：全隧道路由在断线重连时没有正确恢复，UniVPN 连自己的公网网关也找不到出口；随后残留服务继续占用 `29191`。这与密码校验失败不是同一类错误。

Apple Container 将上述故障域限制在轻量虚拟机里。需要 VPN 时运行 `start.command`；不需要或已经直连内网时运行 `stop.command`。如果 UniVPN 再次卡死，停止并重启容器即可同时重置容器内进程、RPC 端口和路由，而不必重启 Mac，也不会移除原 macOS UniVPN 的自动登录设置。

### 证据范围

- 路由模式和分离策略边界来自本机手册与当前客户端二进制；最终下发策略仍以单位 VPN 网关为准。
- 进程名、`29191`、重连错误和 `ErrorCode 51` 来自本机当次故障日志，只用于解释已经观察到的故障链。
- 上游公开页面用于核对 Apple Container 版本、UniVPN ARM64 软件包和校验值；它不能替代单位管理员对网关策略的说明。

## 故障排查

### noVNC 页面无法连接

1. 运行 `status.command`。
2. 确认访问的是 `http://127.0.0.1:16080/...`，不是 macOS 屏幕共享端口。
3. 查看容器日志：

   ```zsh
   ./runtime/bin/container logs univpn-isolation
   ```

4. 若日志出现 `Address already in use`，检查 `entrypoint.sh` 中 x11vnc 是否仍使用独立的 `5901` IPv4/IPv6 端口。

### noVNC 已连接但画面全黑

纯黑根桌面或黑色 UniVPN 窗口不是正常的状态显示。检查容器内 `openbox` 和 `xcompmgr -n` 是否都在运行；UniVPN 必须在合成器启动后创建窗口。修复后应能看到主界面、断线警告或证书确认框，而不是黑色矩形。

### noVNC 正常，但 SOCKS 未就绪

通常表示 UniVPN 尚未连接：

- 在 noVNC 内确认服务器证书警告；
- 查看 UniVPN 是否显示已连接；
- 确认容器内出现 `cnem_vnic`；
- 不要通过关闭证书校验来自动化这一步。

### 浏览器能访问，某个应用不能访问

该应用可能不遵循 macOS PAC，或使用 UDP/ICMP。为它显式设置 SOCKS5 `127.0.0.1:15902`；若应用完全不支持代理，则需要另做按进程的三层转发，当前方案不会偷偷修改系统全局路由。

### 停止后代理异常

先再次运行 `stop.command`。然后检查：

```zsh
scutil --proxy
networksetup -getproxybypassdomains Wi-Fi
```

正常情况下 PAC 为关闭，`10.0.0.0/8` 已回到绕过列表，原 Clash HTTP/HTTPS/SOCKS 配置仍在。

## 重建容器

日常使用不需要重建。只有 `Containerfile`、`entrypoint.sh`、`danted.conf` 或 UniVPN 包改变时才执行。

```zsh
PROJECT_ROOT="$PWD"
BIN="${PROJECT_ROOT}/runtime/bin/container"
BUILD="${PROJECT_ROOT}/build"

"$BIN" build --arch arm64 \
  --tag localhost/univpn-isolation:arm64-final \
  "$BUILD"
```

重建镜像不会自动替换现有容器配置。重建或删除容器前先检查 `container inspect univpn-isolation` 并保留 `univpn-config` 卷。删除卷会丢失自动登录状态；除非用户明确要求，不要删除。

创建同等配置时的关键参数是：

```zsh
"$BIN" create \
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

不要直接复制上述命令覆盖现有容器；先停止、核对并保留命名卷。

## 回滚原则

如果在另一台 Mac 上验证 Apple Container 失败，应恢复验证前状态：

- 恢复原系统代理/PAC 和绕过列表；
- 停止并删除本方案创建的测试容器；
- 只删除本方案创建且确认未被使用的镜像、卷和用户目录运行时；
- 卸载或删除为了测试额外安装的依赖；
- 不删除原 macOS UniVPN，不修改其自动登录；
- 不碰无法明确归属的 `utun`、Network Extension 或用户已有容器。

## 给其他 Codex agent

可复用 skill 有两份内容一致的副本：

```text
~/.codex/skills/isolate-univpn-apple-container/
./skill/isolate-univpn-apple-container/
```

第一份供当前 Codex 自动发现；第二份随本方案保存，便于复制到另一台 M 系列 Mac。迁移时把第二个目录完整复制到目标机器的 `~/.codex/skills/`，不要复制本机登录卷、日志或任何凭据。

可用类似提示调用：

```text
使用 $isolate-univpn-apple-container，在这台 M 系列 Mac 上隔离 UniVPN，
只代理 10.10.128.0/24，并保留原 UniVPN 自动登录；失败时完整回滚。
```

## 上游资料

- [Apple Container 项目与系统要求](https://github.com/apple/container)
- [Apple Container 1.3.0 发布页](https://github.com/apple/container/releases/tag/1.3.0)
- [Apple Container 安装包签名异常记录](https://github.com/apple/container/issues/1682)
- [UniVPN 官方下载与 ARM64 包校验值](https://webtest.leagsoft.com/doc/article/103107.html)
