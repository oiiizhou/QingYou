"""校验版本与 bundle 元数据，避免给 GitHub 发布错版本的安装包。"""
import os
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
with (root / "Resources/App-Info.plist").open("rb") as file:
    app = plistlib.load(file)
with (root / "Resources/Extension-Info.plist").open("rb") as file:
    extension = plistlib.load(file)
source = (root / "Sources/Core/Configuration.swift").read_text()
version = re.search(r'static let version = "([^"]+)"', source).group(1)
assert app["CFBundleShortVersionString"] == extension["CFBundleShortVersionString"] == version
assert app["CFBundleVersion"] == extension["CFBundleVersion"]
assert app.get("LSUIElement") is True, "主程序应以后台辅助应用身份启动，避免右键操作闪现 Dock 图标"
assert extension["CFBundleIdentifier"].startswith(app["CFBundleIdentifier"] + ".")
assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.FinderSync"
if os.environ.get("GITHUB_REF_TYPE") == "tag":
    assert os.environ["GITHUB_REF_NAME"] == "v" + version, "Git 标签与程序版本不一致"
print(f"✓ 主程序、扩展与源码版本一致：{version}")
