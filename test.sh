#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -module-cache-path "${TMPDIR:-/private/tmp}/sunlift-swift-cache" Sources/Localization.swift Sources/Policy.swift Sources/DisplayGain.swift Tests/main.swift -o build/policy-tests
build/policy-tests

# Separate processes exercise Foundation's real bundle language selection without
# changing the user's global or app preferences. These tests never touch a display.
LOCALIZATION_STAGING=$(mktemp -d "${TMPDIR:-/private/tmp}/picnic-localization-tests.XXXXXX")
trap 'rm -rf "$LOCALIZATION_STAGING"' EXIT
LOCALIZATION_APP="$LOCALIZATION_STAGING/LocalizationTests.app"
mkdir -p "$LOCALIZATION_APP/Contents/MacOS" "$LOCALIZATION_APP/Contents/Resources"
cp Info.plist "$LOCALIZATION_APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string LocalizationTests "$LOCALIZATION_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.picnic.LocalizationTests "$LOCALIZATION_APP/Contents/Info.plist"
cp -R Resources/*.lproj "$LOCALIZATION_APP/Contents/Resources/"
xcrun swiftc -module-cache-path "${TMPDIR:-/private/tmp}/sunlift-swift-cache" Sources/Localization.swift Tests/Localization/main.swift -o "$LOCALIZATION_APP/Contents/MacOS/LocalizationTests"
for language_case in 'en|(en-US)' 'ja|(ja-JP)' 'zh-Hans|(zh-Hans-JP)' 'en|(fr-FR)' 'ja|(fr-FR, ja-JP)'; do
    PICNIC_EXPECT_LANGUAGE="${language_case%%|*}" "$LOCALIZATION_APP/Contents/MacOS/LocalizationTests" -AppleLanguages "${language_case#*|}"
done
