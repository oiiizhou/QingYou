#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/QingYou.app"
if [ ! -d "$APP" ]; then bash scripts/build.sh; fi
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
STAGING="$(mktemp -d "$PWD/build/package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/QingYou.app"
ln -s /Applications "$STAGING/Applications"
cp docs/安装说明.txt "$STAGING/安装说明.txt"
cp LICENSE "$STAGING/LICENSE.txt"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/QingYou-$VERSION.zip"
hdiutil create -quiet -volname "轻右 $VERSION" -srcfolder "$STAGING" -ov -format UDZO "dist/QingYou-$VERSION.dmg"
(cd dist && shasum -a 256 "QingYou-$VERSION.zip" "QingYou-$VERSION.dmg" > SHA256SUMS.txt)
echo "安装包已生成到 $PWD/dist"
