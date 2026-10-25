#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -module-cache-path "${TMPDIR:-/private/tmp}/sunlift-swift-cache" Sources/Policy.swift Sources/DisplayGain.swift Tests/main.swift -o build/policy-tests
build/policy-tests
