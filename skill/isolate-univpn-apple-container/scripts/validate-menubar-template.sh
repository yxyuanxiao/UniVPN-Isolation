#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
skill_dir="${script_dir:h}"
archive="${skill_dir}/assets/menubar-app-template.tar.gz"
checksum_file="${skill_dir}/assets/menubar-app-template.sha256"

expected_checksum="$(/usr/bin/awk 'NR == 1 { print $1 }' "${checksum_file}")"
actual_checksum="$(/usr/bin/shasum -a 256 "${archive}" | /usr/bin/awk '{ print $1 }')"
if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
    print -u2 "FAIL: template checksum mismatch"
    exit 1
fi

archive_listing="$(/usr/bin/tar -tzf "${archive}")"
required_entries=(
    "app/Package.swift"
    "app/Info.plist"
    "app/Assets/IvacyVPN-T6s4AC9Km1.icns"
    "app/Sources/AdminAuthorization.swift"
    "app/Sources/AppModel.swift"
    "app/Sources/Backend.swift"
    "app/Sources/Models.swift"
    "app/Sources/Views.swift"
    "app/Sources/Windows.swift"
    "build-menubar-app.command"
)

for required in "${required_entries[@]}"; do
    if ! print -r -- "${archive_listing}" | /usr/bin/grep -qx "${required}"; then
        print -u2 "FAIL: missing ${required}"
        exit 1
    fi
done

if print -r -- "${archive_listing}" | /usr/bin/grep -Eq '(^|/)\.build(/|$)|(^|/)dist(/|$)'; then
    print -u2 "FAIL: template contains build output"
    exit 1
fi

/usr/bin/tar -xOzf "${archive}" build-menubar-app.command | /bin/zsh -n
/usr/bin/tar -xOzf "${archive}" app/Info.plist | /usr/bin/plutil -lint -

backend_source="$(/usr/bin/tar -xOzf "${archive}" app/Sources/Backend.swift)"
model_source="$(/usr/bin/tar -xOzf "${archive}" app/Sources/Models.swift)"
if ! print -r -- "${backend_source}" | /usr/bin/grep -q 'waitForRestrictedSOCKS'; then
    print -u2 "FAIL: template lacks SOCKS readiness gate"
    exit 1
fi
if ! print -r -- "${backend_source}" | /usr/bin/grep -q 'publishPAC'; then
    print -u2 "FAIL: template lacks loopback PAC publishing"
    exit 1
fi
if ! print -r -- "${model_source}" | /usr/bin/grep -q 'http://127.0.0.1:16080/univpn.pac'; then
    print -u2 "FAIL: template lacks loopback HTTP PAC URL"
    exit 1
fi

print "PASS: menu bar template structure and SHA-256 are valid"
