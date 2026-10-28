#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/QingYou.app"
DESTINATION="$HOME/Applications/QingYou.app"
EXTENSION_ID="io.github.qingyou.app.finder"
if [ ! -d "$APP" ]; then bash scripts/build.sh; fi
codesign --verify --deep --strict "$APP"
if pgrep -x QingYou >/dev/null; then
    echo "请先从菜单栏退出轻右，再运行安装脚本。"
    exit 1
fi
mkdir -p "$HOME/Applications" "$HOME/.Trash"
PREVIOUS_ELECTION=$(/usr/bin/pluginkit -m -i "$EXTENSION_ID" 2>/dev/null || true)
WAS_ENABLED=false
case "$PREVIOUS_ELECTION" in +*) WAS_ENABLED=true ;; esac
if [ -e "$DESTINATION" ]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
    if [ "$ID" != "io.github.qingyou.app" ]; then echo "目标位置存在其他应用，已停止安装。"; exit 1; fi
    # 先注销旧扩展，避免更新后 Finder 暂时保留两份相同菜单。
    /usr/bin/pluginkit -r "$DESTINATION/Contents/PlugIns/QingYouFinder.appex" 2>/dev/null || true
    # 必须在注册新版之前停止旧进程；放在后面会误杀 Finder 刚启动的新版。
    /usr/bin/pkill -x QingYouFinder 2>/dev/null || true
    # 先移到废纸篓；升级失败时还能找回上一版。
    mv "$DESTINATION" "$HOME/.Trash/QingYou-$(date +%Y%m%d-%H%M%S)-$RANDOM.app"
fi
ditto "$APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
/usr/bin/pluginkit -a "$DESTINATION/Contents/PlugIns/QingYouFinder.appex"
# 只恢复原来已启用的选择，不替首次安装或已关闭扩展的用户开启开关。
if [ "$WAS_ENABLED" = true ]; then
    /usr/bin/pluginkit -e use -i "$EXTENSION_ID"
fi
echo "已安装到：$DESTINATION"
echo "打开轻右，点击「前往启用」，在系统设置中启用轻右 Finder 扩展。"
