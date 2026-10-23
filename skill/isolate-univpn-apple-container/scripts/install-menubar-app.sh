#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
skill_dir="${script_dir:h}"
archive="${skill_dir}/assets/menubar-app-template.tar.gz"
checksum_file="${skill_dir}/assets/menubar-app-template.sha256"
build_app=1
project_root=""

usage() {
    print "用法：${0:t} [--no-build] /path/to/UniVPN-Isolation"
    print ""
    print "默认安装并构建已验证的菜单栏 App 模板。"
    print "若目标部署的容器名、网关或端口不同，使用 --no-build，"
    print "先按 references/menubar-app.md 适配模板，再运行构建脚本。"
}

while (( $# > 0 )); do
    case "$1" in
        --no-build)
            build_app=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            print -u2 "未知参数：$1"
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "${project_root}" ]]; then
                print -u2 "只能指定一个项目目录。"
                exit 2
            fi
            project_root="${1:A}"
            ;;
    esac
    shift
done

if [[ -z "${project_root}" ]]; then
    usage >&2
    exit 2
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "菜单栏 App 模板只验证过 Apple silicon（arm64）。"
    exit 1
fi

if [[ ! -d "${project_root}" ]]; then
    print -u2 "项目目录不存在：${project_root}"
    exit 1
fi

for required in \
    "${project_root}/runtime/bin/container" \
    "${project_root}/univpn.pac" \
    "${project_root}/stop.command"; do
    if [[ ! -e "${required}" ]]; then
        print -u2 "缺少 App 运行依赖：${required}"
        exit 1
    fi
done

if [[ -e "${project_root}/app" || -e "${project_root}/build-menubar-app.command" ]]; then
    print -u2 "目标目录已有 app/ 或 build-menubar-app.command；拒绝覆盖。"
    print -u2 "请先审阅并手工合并，或选择一个没有 App 源码的项目目录。"
    exit 1
fi

if [[ ! -r "${archive}" || ! -r "${checksum_file}" ]]; then
    print -u2 "技能缺少菜单栏 App 模板或校验文件。"
    exit 1
fi

expected_checksum="$(/usr/bin/awk 'NR == 1 { print $1 }' "${checksum_file}")"
actual_checksum="$(/usr/bin/shasum -a 256 "${archive}" | /usr/bin/awk '{ print $1 }')"
if [[ -z "${expected_checksum}" || "${actual_checksum}" != "${expected_checksum}" ]]; then
    print -u2 "菜单栏 App 模板 SHA-256 校验失败；没有解包。"
    exit 1
fi

COPYFILE_DISABLE=1 /usr/bin/tar -xzf "${archive}" -C "${project_root}"
/bin/chmod +x "${project_root}/build-menubar-app.command"

print "已安装菜单栏 App 源码：${project_root}/app"

if (( build_app == 0 )); then
    print "已跳过构建。完成环境参数适配后运行："
    print "  ${project_root}/build-menubar-app.command"
    exit 0
fi

if [[ ! -x /usr/bin/swift ]]; then
    print -u2 "找不到 Swift 工具链；源码已安装，但尚未构建。"
    exit 1
fi

"${project_root}/build-menubar-app.command"
app_bundle="${project_root}/dist/UniVPN Isolation.app"
/usr/bin/plutil -lint "${app_bundle}/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${app_bundle}"

print "菜单栏 App 已生成并通过签名验证：${app_bundle}"
