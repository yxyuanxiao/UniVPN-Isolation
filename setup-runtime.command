#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
CONTAINER_BIN="${PROJECT_ROOT}/runtime/bin/container"
IMAGE_ARCHIVE="${PROJECT_ROOT}/vendor/univpn-isolation-arm64.oci.tar"
CHECKSUM_FILE="${PROJECT_ROOT}/vendor/SHA256SUMS"
IMAGE_NAME="localhost/univpn-isolation"
IMAGE_TAG="arm64-final"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
CONTAINER_NAME="univpn-isolation"
VOLUME_NAME="univpn-config"

fail() {
    print -u2 "初始化失败：$1"
    exit 1
}

if [[ "$(uname -m)" != "arm64" ]]; then
    fail "仅支持 Apple silicon（arm64）。"
fi

for required in "${CONTAINER_BIN}" "${IMAGE_ARCHIVE}" "${CHECKSUM_FILE}"; do
    [[ -e "${required}" ]] || fail "缺少安装文件：${required}"
done
[[ -x "${CONTAINER_BIN}" ]] || fail "Apple Container CLI 不可执行：${CONTAINER_BIN}"

expected_hash="$(/usr/bin/awk '$2 == "univpn-isolation-arm64.oci.tar" { print $1; exit }' "${CHECKSUM_FILE}")"
actual_hash="$(/usr/bin/shasum -a 256 "${IMAGE_ARCHIVE}" | /usr/bin/awk '{ print $1 }')"
if [[ -z "${expected_hash}" || "${actual_hash}" != "${expected_hash}" ]]; then
    fail "OCI 镜像 SHA-256 校验失败。"
fi

print "正在启动 Apple Container 后台…"
system_start_output="$("${CONTAINER_BIN}" system start 2>&1)" || {
    normalized="${system_start_output:l}"
    if [[ "${normalized}" != *already* && "${normalized}" != *running* ]]; then
        print -u2 -- "${system_start_output}"
        fail "Apple Container 后台无法启动。"
    fi
}

container_exists=0
if "${CONTAINER_BIN}" list --all \
    | /usr/bin/awk 'NR > 1 { print $1 }' \
    | /usr/bin/grep -qx "${CONTAINER_NAME}"; then
    container_exists=1
fi

if (( container_exists == 1 )); then
    inspect_output="$("${CONTAINER_BIN}" inspect "${CONTAINER_NAME}")"
    required_patterns=(
        '"architecture" : "arm64"'
        '"CAP_NET_ADMIN"'
        '"hostAddress" : "127.0.0.1"'
        '"hostPort" : 15902'
        '"hostPort" : 16080'
        '"name" : "univpn-config"'
        '"rosetta" : false'
    )
    for pattern in "${required_patterns[@]}"; do
        if ! print -r -- "${inspect_output}" | /usr/bin/grep -Fq "${pattern}"; then
            fail "已有同名容器，但配置不符合隔离安全边界；没有覆盖它。缺少：${pattern}"
        fi
    done
    print "检测到配置正确的 ${CONTAINER_NAME}；保留并复用。"
    print "初始化完成。现在可以打开 /Applications/UniVPN Isolation.app。"
    exit 0
fi

if ! "${CONTAINER_BIN}" image list \
    | /usr/bin/awk -v name="${IMAGE_NAME}" -v tag="${IMAGE_TAG}" \
        'NR > 1 && $1 == name && $2 == tag { found=1 } END { exit !found }'; then
    print "正在导入离线 ARM64 镜像…"
    "${CONTAINER_BIN}" image load --input "${IMAGE_ARCHIVE}"
fi

if ! "${CONTAINER_BIN}" volume list \
    | /usr/bin/awk -v volume="${VOLUME_NAME}" \
        'NR > 1 && $1 == volume { found=1 } END { exit !found }'; then
    print "正在创建持久配置卷 ${VOLUME_NAME}…"
    "${CONTAINER_BIN}" volume create "${VOLUME_NAME}"
else
    print "保留已有配置卷 ${VOLUME_NAME}。"
fi

print "正在创建受限容器 ${CONTAINER_NAME}…"
"${CONTAINER_BIN}" create \
    --name "${CONTAINER_NAME}" \
    --arch arm64 \
    --cpus 4 \
    --memory 1G \
    --init \
    --cap-add CAP_NET_ADMIN \
    --network default,mtu=1280 \
    --volume "${VOLUME_NAME}:/root/.config/cn.com.huawei-security-commercial-alliance.univpn" \
    --publish 127.0.0.1:15902:5900 \
    --publish 127.0.0.1:16080:6080 \
    "${IMAGE_REF}"

print ""
print "初始化完成。配置卷会保留 UniVPN 登录状态。"
print "现在可以打开 /Applications/UniVPN Isolation.app；证书确认仍需人工完成。"
