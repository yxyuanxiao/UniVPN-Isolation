#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="${PROJECT_ROOT}/app/.build/self-tests"
TEST_BINARY="${BUILD_DIR}/TrafficParserSelfTest"

/bin/mkdir -p "${BUILD_DIR}"
/usr/bin/swiftc \
    -parse-as-library \
    "${PROJECT_ROOT}/app/Sources/Models.swift" \
    "${PROJECT_ROOT}/app/Sources/Backend.swift" \
    "${PROJECT_ROOT}/app/Tests/TrafficParserSelfTest.swift" \
    -o "${TEST_BINARY}"

"${TEST_BINARY}"
