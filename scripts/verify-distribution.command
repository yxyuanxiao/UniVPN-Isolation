#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
package_path="${1:-}"

if [[ -z "${package_path}" ]]; then
    packages=("${PROJECT_ROOT}"/dist/release/*.pkg(N))
    if (( ${#packages} != 1 )); then
        print -u2 "请指定要验证的 .pkg；当前找到 ${#packages} 个。"
        exit 2
    fi
    package_path="${packages[1]}"
fi
package_path="${package_path:A}"

[[ -f "${package_path}" ]] || {
    print -u2 "安装包不存在：${package_path}"
    exit 1
}

checksum_file="${package_path}.sha256"
if [[ -f "${checksum_file}" ]]; then
    expected_hash="$(/usr/bin/awk 'NR == 1 { print $1 }' "${checksum_file}")"
    actual_hash="$(/usr/bin/shasum -a 256 "${package_path}" | /usr/bin/awk '{ print $1 }')"
    [[ "${expected_hash}" == "${actual_hash}" ]] || {
        print -u2 "FAIL: 安装包 SHA-256 不匹配。"
        exit 1
    }
    print "PASS: 安装包 SHA-256 匹配"
else
    print -u2 "WARN: 没有找到 ${checksum_file:t}"
fi

payload_files="$(
    /usr/sbin/pkgutil --payload-files "${package_path}" \
        | /usr/bin/sed 's#^\./##'
)"
required_payload=(
    "Applications/UniVPN Isolation.app/Contents/MacOS/UniVPNMenuBar"
    "Applications/UniVPN-Isolation/runtime/bin/container"
    "Applications/UniVPN-Isolation/runtime/libexec/container"
    "Applications/UniVPN-Isolation/vendor/univpn-isolation-arm64.oci.tar"
    "Applications/UniVPN-Isolation/vendor/SHA256SUMS"
    "Applications/UniVPN-Isolation/setup-runtime.command"
    "Applications/UniVPN-Isolation/univpn.pac"
)
for required in "${required_payload[@]}"; do
    if ! print -r -- "${payload_files}" | /usr/bin/grep -Fqx "${required}"; then
        print -u2 "FAIL: 安装包缺少 ${required}"
        exit 1
    fi
done
print "PASS: 安装包载荷完整"

appledouble_count="$(
    print -r -- "${payload_files}" \
        | /usr/bin/awk '/(^|\/)\._/ { count++ } END { print count+0 }'
)"
if [[ "${appledouble_count}" != "0" ]]; then
    print "INFO: pkgbuild 使用 ${appledouble_count} 个 AppleDouble 传输记录保留 macOS 扩展属性"
fi

if /usr/sbin/pkgutil --check-signature "${package_path}"; then
    print "PASS: 安装包签名可验证"
else
    print -u2 "WARN: 安装包未使用 Developer ID Installer 签名"
fi

staged_app="${PROJECT_ROOT}/dist/package-root/Applications/UniVPN Isolation.app"
staged_runtime="${PROJECT_ROOT}/dist/package-root/Applications/UniVPN-Isolation/runtime/bin/container"
if [[ -d "${staged_app}" ]]; then
    /usr/bin/plutil -lint "${staged_app}/Contents/Info.plist"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${staged_app}"
    app_arch="$(/usr/bin/lipo -archs "${staged_app}/Contents/MacOS/UniVPNMenuBar")"
    [[ "${app_arch}" == "arm64" ]] || {
        print -u2 "FAIL: App 架构是 ${app_arch}，预期 arm64"
        exit 1
    }
    print "PASS: App Info.plist、签名与 arm64 架构有效"
fi
if [[ -x "${staged_runtime}" ]]; then
    runtime_arch="$(/usr/bin/lipo -archs "${staged_runtime}")"
    [[ "${runtime_arch}" == "arm64" ]] || {
        print -u2 "FAIL: Apple Container CLI 架构是 ${runtime_arch}，预期 arm64"
        exit 1
    }
    print "PASS: Apple Container CLI 为 arm64"
fi

print "PASS: ${package_path} 静态验证完成"
