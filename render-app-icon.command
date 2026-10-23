#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
ASSET_DIR="${PROJECT_ROOT}/app/Assets"
ICONSET_DIR="${ASSET_DIR}/UniVPNIsolation.iconset"
MASTER_PNG="${ASSET_DIR}/AppIcon-1024.png"
RENDERER_BIN="/tmp/univpn-isolation-icon-renderer"

/bin/mkdir -p "${ICONSET_DIR}"
/usr/bin/swiftc "${PROJECT_ROOT}/app/Tools/RenderAppIcon.swift" -o "${RENDERER_BIN}"
"${RENDERER_BIN}" "${MASTER_PNG}"

for item in \
    '16:icon_16x16.png' \
    '32:icon_16x16@2x.png' \
    '32:icon_32x32.png' \
    '64:icon_32x32@2x.png' \
    '128:icon_128x128.png' \
    '256:icon_128x128@2x.png' \
    '256:icon_256x256.png' \
    '512:icon_256x256@2x.png' \
    '512:icon_512x512.png' \
    '1024:icon_512x512@2x.png'; do
    size="${item%%:*}"
    name="${item#*:}"
    /usr/bin/sips -z "${size}" "${size}" "${MASTER_PNG}" --out "${ICONSET_DIR}/${name}" >/dev/null
done

/usr/bin/iconutil -c icns "${ICONSET_DIR}" -o "${ASSET_DIR}/UniVPNIsolation.icns"
print "已生成：${ASSET_DIR}/UniVPNIsolation.icns"
