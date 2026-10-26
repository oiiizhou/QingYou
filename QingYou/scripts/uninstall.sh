#!/bin/bash
set -euo pipefail
APP="$HOME/Applications/QingYou.app"
if pgrep -x QingYou >/dev/null; then echo "请先从菜单栏退出轻右。"; exit 1; fi
if [ ! -d "$APP" ]; then echo "未找到 $APP；如果安装在其他目录，请手动移到废纸篓。"; exit 0; fi
ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
if [ "$ID" != "io.github.qingyou.app" ]; then echo "应用标识不匹配，已停止。"; exit 1; fi
/usr/bin/pluginkit -e ignore -i io.github.qingyou.app.finder
/usr/bin/pluginkit -r "$APP/Contents/PlugIns/QingYouFinder.appex"
mkdir -p "$HOME/.Trash"
mv "$APP" "$HOME/.Trash/QingYou-$(date +%Y%m%d-%H%M%S)-$RANDOM.app"
echo "应用已移到废纸篓。设置、模板和记录仍保留在 Library/Application Support/QingYou。"
