#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCHS="${ARCHS:-$(uname -m)}"
APP="$ROOT/build/QingYou.app"
EXT="$APP/Contents/PlugIns/QingYouFinder.appex"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
mkdir -p "$ROOT/build/objects"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Extension-Info.plist "$EXT/Contents/Info.plist"
# 只带入已验证的空白模板，Office 编辑时产生的锁文件不能跟随应用分发。
rm -rf "$APP/Contents/Resources/Templates"
mkdir -p "$APP/Contents/Resources/Templates"
cp Resources/Templates/Blank.* "$APP/Contents/Resources/Templates/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
APP_BINARIES=()
EXT_BINARIES=()
for ARCH in $ARCHS; do
    echo "编译 $ARCH 主程序…"
    xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" \
        -module-name QingYou Sources/Core/*.swift Sources/App/*.swift \
        -o "$ROOT/build/objects/QingYou-$ARCH"
    echo "编译 $ARCH Finder 扩展…"
    xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" \
        -module-name QingYouFinder -parse-as-library \
        -Xlinker -e -Xlinker _NSExtensionMain \
        Sources/Core/*.swift Sources/FinderExtension/*.swift \
        -o "$ROOT/build/objects/QingYouFinder-$ARCH"
    APP_BINARIES+=("$ROOT/build/objects/QingYou-$ARCH")
    EXT_BINARIES+=("$ROOT/build/objects/QingYouFinder-$ARCH")
done
xcrun lipo -create "${APP_BINARIES[@]}" -output "$APP/Contents/MacOS/QingYou"
xcrun lipo -create "${EXT_BINARIES[@]}" -output "$EXT/Contents/MacOS/QingYouFinder"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
codesign "${SIGN_FLAGS[@]}" \
    --entitlements Resources/Extension.entitlements "$EXT"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
echo "构建完成：$APP"
