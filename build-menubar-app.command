#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
PACKAGE_DIR="${PROJECT_ROOT}/app"
DIST_DIR="${UNIVPN_DIST_DIR:-${PROJECT_ROOT}/dist}"
APP_BUNDLE="${DIST_DIR}/UniVPN Isolation.app"
RUNTIME_ROOT="${UNIVPN_PROJECT_ROOT_OVERRIDE:-${PROJECT_ROOT}}"
SIGN_IDENTITY="${UNIVPN_APP_SIGN_IDENTITY:--}"

cd "${PACKAGE_DIR}"
/usr/bin/swift build -c release --arch arm64
BIN_DIR="$(/usr/bin/swift build -c release --arch arm64 --show-bin-path)"

if [[ -e "${APP_BUNDLE}" ]]; then
    if [[ "${APP_BUNDLE}" != "${PROJECT_ROOT}/dist/UniVPN Isolation.app" ]]; then
        print -u2 "拒绝清理非预期路径：${APP_BUNDLE}"
        exit 1
    fi
    /bin/rm -rf -- "${APP_BUNDLE}"
fi

/bin/mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
/bin/cp "${BIN_DIR}/UniVPNMenuBar" "${APP_BUNDLE}/Contents/MacOS/UniVPNMenuBar"
/bin/cp "${PACKAGE_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
/bin/cp "${PACKAGE_DIR}/Assets/IvacyVPN-T6s4AC9Km1.icns" "${APP_BUNDLE}/Contents/Resources/UniVPNIsolation.icns"
/usr/bin/plutil -replace UniVPNProjectRoot -string "${RUNTIME_ROOT}" "${APP_BUNDLE}/Contents/Info.plist"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    /usr/bin/codesign --force --sign - "${APP_BUNDLE}"
else
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "${SIGN_IDENTITY}" \
        "${APP_BUNDLE}"
fi

print "已生成：${APP_BUNDLE}"
print "运行目录：${RUNTIME_ROOT}"
