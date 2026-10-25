#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build dist
CACHE="${TMPDIR:-/private/tmp}/sunlift-swift-cache"
mkdir -p "$CACHE"
xcrun clang -O2 -target arm64-apple-macos14.0 -c Sources/AmbientSensor.c -o build/AmbientSensor.o
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$CACHE" \
  -import-objc-header Sources/AmbientSensor.h Sources/*.swift build/AmbientSensor.o \
  -framework AppKit -framework SwiftUI -framework MetalKit -framework IOKit -framework ServiceManagement -o build/SunLift
STAGING=$(mktemp -d "${TMPDIR:-/private/tmp}/sunlift-package.XXXXXX")
APP="$STAGING/Picnic.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/SunLift "$APP/Contents/MacOS/SunLift"
cp Info.plist "$APP/Contents/Info.plist"
cp 使用说明.txt "$APP/Contents/Resources/使用说明.txt"
cp NOTICES.txt "$APP/Contents/Resources/NOTICES.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Assets/Picnic.icns "$APP/Contents/Resources/Picnic.icns"
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "dist/Picnic.zip"
print "Signed app: $APP"
print "Archive: $PWD/dist/Picnic.zip"
