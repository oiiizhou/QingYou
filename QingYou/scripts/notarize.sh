#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${SIGN_IDENTITY:-}" ] || [ "$SIGN_IDENTITY" = "-" ]; then
    echo "请指定 Developer ID Application 签名身份 SIGN_IDENTITY。"; exit 1
fi
if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "请指定已保存在钥匙串中的公证凭据名称 NOTARY_PROFILE。"; exit 1
fi
bash scripts/build.sh
ditto -c -k --sequesterRsrc --keepParent build/QingYou.app build/notarization.zip
xcrun notarytool submit build/notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/QingYou.app
xcrun stapler validate build/QingYou.app
bash scripts/package.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/QingYou.app/Contents/Info.plist)
xcrun notarytool submit "dist/QingYou-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "dist/QingYou-$VERSION.dmg"
(cd dist && shasum -a 256 "QingYou-$VERSION.zip" "QingYou-$VERSION.dmg" > SHA256SUMS.txt)
