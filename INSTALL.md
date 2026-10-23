# 安装与分发

本项目提供 Apple 芯片 Mac 使用的 `.pkg` 安装包。安装包把菜单栏 App 安装到：

```text
/Applications/UniVPN Isolation.app
```

运行时、离线 OCI 镜像和维护命令安装到：

```text
/Applications/UniVPN-Isolation/
```

## 用户安装

1. 核对安装包旁边 `.sha256` 文件中的 SHA-256。
2. 使用 macOS Installer 打开 `.pkg`。
3. 安装后运行 `/Applications/UniVPN-Isolation/setup-runtime.command`。
4. 初始化成功后打开 `/Applications/UniVPN Isolation.app`。
5. 在 noVNC 登录页人工确认 UniVPN 登录和服务器证书提示。

首次初始化只在资源不存在时导入镜像、创建 `univpn-config` 命名卷和 `univpn-isolation` 容器。它不会覆盖同名容器，也不会删除配置卷。

当前本机没有 Developer ID Application / Installer 证书，因此默认生成的是 ad-hoc 签名 App 和未签名 `.pkg`。它适合受控环境或本机分发，但不是已经通过 Gatekeeper 公证的互联网发行版。若 macOS 拒绝安装，不要关闭系统级安全机制；应使用自己的 Apple Developer 证书重新签名并公证。

## 本地构建

构建必须在最终项目目录执行：

```zsh
./scripts/build-distribution.command
./scripts/verify-distribution.command
```

构建脚本会：

- 原地编译 ARM64 菜单栏 App；
- 把 App 的运行根目录固定为 `/Applications/UniVPN-Isolation`；
- 从已验证的 `localhost/univpn-isolation:arm64-final` 导出离线 OCI 镜像；
- 只把运行必需文件放进安装包，不包含源码、登录卷、日志或代理快照；
- 生成安装包和 SHA-256 文件。

如本机已有 Developer ID 证书：

```zsh
UNIVPN_APP_SIGN_IDENTITY='Developer ID Application: ...' \
UNIVPN_INSTALLER_IDENTITY='Developer ID Installer: ...' \
./scripts/build-distribution.command
```

签名后仍需按 Apple 的流程使用 `notarytool` 提交公证并 stapler。项目不会保存 Apple ID、App Store Connect 密钥或公证凭据。

## Git 仓库边界

Git 只跟踪 App、容器定义、脚本、文档和 skill。以下文件保留在本机并由发行脚本消费，不提交到 GitHub：

- Apple Container 运行时；
- UniVPN `.deb`、解包文件树和额外运行库；
- 导出的 OCI 镜像；
- Swift 构建缓存、安装包、状态文件和登录卷。

这既控制仓库体积，也避免把厂商二进制和机器状态混进源码历史。
