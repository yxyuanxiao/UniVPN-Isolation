#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
VERSION="$(/usr/bin/tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")"
DIST_DIR="${PROJECT_ROOT}/dist"
PKG_ROOT="${DIST_DIR}/package-root"
COMPONENT_DIR="${DIST_DIR}/components"
RELEASE_DIR="${DIST_DIR}/release"
SUPPORT_ROOT="${PKG_ROOT}/Applications/UniVPN-Isolation"
APP_DESTINATION="${PKG_ROOT}/Applications/UniVPN Isolation.app"
COMPONENT_PKG="${COMPONENT_DIR}/UniVPN-Isolation.pkg"
COMPONENT_PLIST="${COMPONENT_DIR}/component.plist"
FINAL_PKG="${RELEASE_DIR}/UniVPN-Isolation-${VERSION}-arm64.pkg"
IMAGE_ARCHIVE="${PROJECT_ROOT}/vendor/univpn-isolation-arm64.oci.tar"
CHECKSUM_FILE="${PROJECT_ROOT}/vendor/SHA256SUMS"
IMAGE_REF="localhost/univpn-isolation:arm64-final"
CONTAINER_BIN="${PROJECT_ROOT}/runtime/bin/container"
APP_SIGN_IDENTITY="${UNIVPN_APP_SIGN_IDENTITY:--}"
INSTALLER_IDENTITY="${UNIVPN_INSTALLER_IDENTITY:-}"

fail() {
    print -u2 "发行构建失败：$1"
    exit 1
}

[[ "$(uname -m)" == "arm64" ]] || fail "仅支持在 Apple silicon 上构建。"
[[ -n "${VERSION}" ]] || fail "VERSION 为空。"

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_ROOT}/app/Info.plist")"
[[ "${plist_version}" == "${VERSION}" ]] \
    || fail "VERSION (${VERSION}) 与 App 版本 (${plist_version}) 不一致。"

required_paths=(
    "${CONTAINER_BIN}"
    "${PROJECT_ROOT}/runtime/libexec/container"
    "${PROJECT_ROOT}/univpn.pac"
    "${PROJECT_ROOT}/setup-runtime.command"
    "${PROJECT_ROOT}/stop.command"
    "${PROJECT_ROOT}/app/Assets/IvacyVPN-T6s4AC9Km1.icns"
)
for required in "${required_paths[@]}"; do
    [[ -e "${required}" ]] || fail "缺少发行输入：${required}"
done

if [[ ! -f "${IMAGE_ARCHIVE}" ]]; then
    print "未发现本地 OCI 归档，正在从 ${IMAGE_REF} 导出…"
    was_running=0
    if "${CONTAINER_BIN}" system status >/dev/null 2>&1; then
        was_running=1
    else
        "${CONTAINER_BIN}" system start
    fi

    if ! "${CONTAINER_BIN}" image list \
        | /usr/bin/awk 'NR > 1 && $1 == "localhost/univpn-isolation" && $2 == "arm64-final" { found=1 } END { exit !found }'; then
        (( was_running == 0 )) && "${CONTAINER_BIN}" system stop >/dev/null 2>&1 || true
        fail "本机没有 ${IMAGE_REF}，请先验证或重建容器镜像。"
    fi

    "${CONTAINER_BIN}" image save \
        --platform linux/arm64 \
        --output "${IMAGE_ARCHIVE}" \
        "${IMAGE_REF}"

    if (( was_running == 0 )); then
        running_count="$("${CONTAINER_BIN}" list | /usr/bin/awk 'NR > 1 { count++ } END { print count+0 }')"
        if [[ "${running_count}" == "0" ]]; then
            "${CONTAINER_BIN}" system stop
        else
            print -u2 "Apple Container 原先未运行，但现在检测到工作负载；保留后台运行。"
        fi
    fi
fi

image_hash="$(/usr/bin/shasum -a 256 "${IMAGE_ARCHIVE}" | /usr/bin/awk '{ print $1 }')"
print -r -- "${image_hash}  univpn-isolation-arm64.oci.tar" > "${CHECKSUM_FILE}"

print "正在项目最终目录原地编译菜单栏 App…"
UNIVPN_PROJECT_ROOT_OVERRIDE="/Applications/UniVPN-Isolation" \
UNIVPN_APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY}" \
    "${PROJECT_ROOT}/build-menubar-app.command"

APP_SOURCE="${DIST_DIR}/UniVPN Isolation.app"
/usr/bin/plutil -lint "${APP_SOURCE}/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_SOURCE}"
embedded_root="$(/usr/libexec/PlistBuddy -c 'Print :UniVPNProjectRoot' "${APP_SOURCE}/Contents/Info.plist")"
[[ "${embedded_root}" == "/Applications/UniVPN-Isolation" ]] \
    || fail "App 内嵌运行目录不正确：${embedded_root}"

for path_to_clean in "${PKG_ROOT}" "${COMPONENT_DIR}"; do
    case "${path_to_clean}" in
        "${DIST_DIR}/package-root"|"${DIST_DIR}/components")
            /bin/rm -rf -- "${path_to_clean}"
            ;;
        *)
            fail "拒绝清理非预期目录：${path_to_clean}"
            ;;
    esac
done

/bin/mkdir -p "${SUPPORT_ROOT}" "${COMPONENT_DIR}" "${RELEASE_DIR}"
/usr/bin/ditto "${PROJECT_ROOT}/runtime" "${SUPPORT_ROOT}/runtime"
/bin/mkdir -p "${SUPPORT_ROOT}/vendor"
/bin/cp -p "${IMAGE_ARCHIVE}" "${SUPPORT_ROOT}/vendor/"
/bin/cp -p "${CHECKSUM_FILE}" "${SUPPORT_ROOT}/vendor/"

support_files=(
    README.md
    INSTALL.md
    THIRD_PARTY_NOTICES.md
    VERSION
    univpn.pac
    setup-runtime.command
    start.command
    stop.command
    status.command
    ssh-proxy.command
)
for support_file in "${support_files[@]}"; do
    /bin/cp -p "${PROJECT_ROOT}/${support_file}" "${SUPPORT_ROOT}/${support_file}"
done
/usr/bin/ditto "${APP_SOURCE}" "${APP_DESTINATION}"

/bin/chmod 0755 \
    "${SUPPORT_ROOT}/setup-runtime.command" \
    "${SUPPORT_ROOT}/start.command" \
    "${SUPPORT_ROOT}/stop.command" \
    "${SUPPORT_ROOT}/status.command" \
    "${SUPPORT_ROOT}/ssh-proxy.command"

# The staging root is generated exclusively for this package. Strip removable
# Finder and quarantine xattrs before packaging. macOS may retain protected
# provenance metadata and pkgbuild can encode that as AppleDouble transport
# records; those records restore metadata rather than becoming user files.
/usr/bin/xattr -cr "${PKG_ROOT}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DESTINATION}"

# Component packages relocate bundles by identifier unless told otherwise. An
# older development copy may have the same bundle identifier, so explicitly
# pin the menu bar app to /Applications instead of allowing Installer to update
# whichever matching copy Spotlight finds first.
/usr/bin/pkgbuild --analyze --root "${PKG_ROOT}" "${COMPONENT_PLIST}"
component_bundle_path="$(/usr/bin/plutil -extract '0.RootRelativeBundlePath' raw -o - "${COMPONENT_PLIST}")"
[[ "${component_bundle_path}" == "Applications/UniVPN Isolation.app" ]] \
    || fail "组件分析返回了意外的 App 路径：${component_bundle_path}"
/usr/bin/plutil -replace '0.BundleIsRelocatable' -bool NO "${COMPONENT_PLIST}"
component_relocatable="$(/usr/bin/plutil -extract '0.BundleIsRelocatable' raw -o - "${COMPONENT_PLIST}")"
[[ "${component_relocatable}" == "false" ]] \
    || fail "未能禁止 Installer 重定位菜单栏 App。"

pkgbuild_args=(
    --root "${PKG_ROOT}"
    --component-plist "${COMPONENT_PLIST}"
    --scripts "${PROJECT_ROOT}/packaging/scripts"
    --identifier com.yxyuanxiao.univpn-isolation
    --version "${VERSION}"
    --install-location /
    --ownership recommended
)
if [[ -n "${INSTALLER_IDENTITY}" ]]; then
    pkgbuild_args+=(--sign "${INSTALLER_IDENTITY}")
fi
pkgbuild_args+=("${COMPONENT_PKG}")

COPYFILE_DISABLE=1 /usr/bin/pkgbuild "${pkgbuild_args[@]}"
/usr/bin/ditto "${COMPONENT_PKG}" "${FINAL_PKG}"

package_hash="$(/usr/bin/shasum -a 256 "${FINAL_PKG}" | /usr/bin/awk '{ print $1 }')"
print -r -- "${package_hash}  ${FINAL_PKG:t}" > "${FINAL_PKG}.sha256"

"${PROJECT_ROOT}/scripts/verify-distribution.command" "${FINAL_PKG}"

if [[ "${UNIVPN_KEEP_PACKAGE_STAGING:-0}" != "1" ]]; then
    for generated_path in "${PKG_ROOT}" "${COMPONENT_DIR}"; do
        case "${generated_path}" in
            "${DIST_DIR}/package-root"|"${DIST_DIR}/components")
                /bin/rm -rf -- "${generated_path}"
                ;;
            *)
                fail "拒绝清理非预期目录：${generated_path}"
                ;;
        esac
    done
fi

print ""
print "发行包：${FINAL_PKG}"
print "SHA-256：${package_hash}"
if [[ -z "${INSTALLER_IDENTITY}" ]]; then
    print "注意：当前 .pkg 未使用 Developer ID Installer 签名，也未公证。"
fi
