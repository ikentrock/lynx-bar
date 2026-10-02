#!/bin/zsh
# Compiles and runs Lynx Bar's standalone script tests.
#
# Each test is Scripts/Tests/<Name>/main.swift, compiled together with
# Scripts/Tests/Support/*.swift and the app sources listed below.
# Set LYNX_TEST_CERT to a code-signing certificate's SHA-1 to also test
# certificate signing (e.g. from `security find-identity -p codesigning`).
set -euo pipefail
cd "${0:A:h}"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
failed=0

build() { # name, sources...
    local name=$1; shift
    swiftc -swift-version 5 -o "$OUT/$name" Tests/Support/*.swift "Tests/$name/main.swift" "$@"
}

run() { # name
    "$OUT/$1" || failed=1
}

build PeerCodeRequirement ../Shared/Services/MenuBarItemServiceIdentity.swift ../Shared/Services/PeerCodeRequirement.swift
run PeerCodeRequirement
if [[ -n ${LYNX_TEST_CERT:-} ]]; then
    codesign --force --sign "$LYNX_TEST_CERT" "$OUT/PeerCodeRequirement" 2>/dev/null
    EXPECT_CERT_SHA1=$LYNX_TEST_CERT "$OUT/PeerCodeRequirement" || failed=1
fi

exit $failed
