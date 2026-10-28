"""验证通用 DMG／ZIP 的实际内容，而不只检查文件是否生成。"""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import tempfile
import zipfile

project = Path(__file__).resolve().parent.parent
app = project / "build/QingYou.app"
dist = project / "dist"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*arguments):
    return subprocess.check_output([str(arg) for arg in arguments], stderr=subprocess.STDOUT)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def payload(bundle):
    result = {}
    for path in sorted(bundle.rglob("*")):
        relative = path.relative_to(bundle).as_posix()
        if path.is_symlink():
            result[relative] = ("link", str(path.readlink()))
        elif path.is_file():
            result[relative] = ("file", sha256(path))
    return result


metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
version = metadata["CFBundleShortVersionString"]
build = metadata["CFBundleVersion"]
reference = payload(app)


def check_bundle(bundle):
    run("codesign", "--verify", "--deep", "--strict", "--all-architectures", bundle)
    for binary in ["Contents/MacOS/QingYou",
                   "Contents/PlugIns/QingYouFinder.appex/Contents/MacOS/QingYouFinder"]:
        architectures = set(run("xcrun", "lipo", "-archs", bundle / binary).decode().split())
        require(architectures == {"arm64", "x86_64"}, f"缺少通用架构：{binary}")
    extension = plistlib.loads((bundle / "Contents/PlugIns/QingYouFinder.appex/Contents/Info.plist").read_bytes())
    require(extension["CFBundleShortVersionString"] == version
            and extension["CFBundleVersion"] == build, "主程序与扩展版本不一致")
    require(len(list((bundle / "Contents/Resources/Templates").glob("Blank.*"))) == 6,
            "Office 模板不完整")
    require((bundle / "Contents/Resources/LICENSE.txt").read_bytes() == (project / "LICENSE").read_bytes(),
            "应用内许可不一致")
    require(payload(bundle) == reference, "安装包内程序与当前构建不一致")
    require(not any(path.name in {"settings.json", "history.json"} for path in bundle.rglob("*")),
            "安装包不应包含个人配置或操作历史")


check_bundle(app)
artifacts = [dist / f"QingYou-{version}.{suffix}" for suffix in ["dmg", "zip"]]
manifest = {}
for line in (dist / "SHA256SUMS.txt").read_text().splitlines():
    digest, name = line.split(maxsplit=1)
    manifest[name] = digest
require(set(manifest) == {path.name for path in artifacts}, "校验清单与当前版本不一致")
for path in artifacts:
    require(sha256(path) == manifest[path.name], f"校验值不匹配：{path.name}")

with tempfile.TemporaryDirectory(prefix="verify-package-", dir=project / "build") as directory:
    folder = Path(directory)
    with zipfile.ZipFile(artifacts[1]) as archive:
        require(archive.testzip() is None, "ZIP 完整性检查失败")
        require(all(not name.startswith("/") and ".." not in Path(name).parts
                    for name in archive.namelist()), "ZIP 存在不安全的解压路径")
    run("ditto", "-x", "-k", artifacts[1], folder / "zip")
    check_bundle(folder / "zip/QingYou.app")
    run("hdiutil", "verify", artifacts[0])
    mount = folder / "mounted"
    mount.mkdir()
    # 只读挂载，并在内容检查失败时同样卸载。
    run("hdiutil", "attach", "-readonly", "-nobrowse", "-plist", "-mountpoint", mount, artifacts[0])
    try:
        check_bundle(mount / "QingYou.app")
        require((mount / "Applications").is_symlink()
                and (mount / "Applications").readlink() == Path("/Applications"), "缺少应用程序安装入口")
        for source, packaged in [(project / "LICENSE", "LICENSE.txt"),
                                 (project / "docs/安装说明.txt", "安装说明.txt")]:
            require((mount / packaged).read_bytes() == source.read_bytes(), f"附件不一致：{packaged}")
    finally:
        run("hdiutil", "detach", mount)

report = {"version": version, "build": build, "architectures": ["arm64", "x86_64"],
          "checks": ["strict signatures", "universal binaries", "matching app payloads",
                     "ZIP integrity", "read-only DMG mount", "templates and license", "SHA-256"],
          "artifacts": {path.name: {"bytes": path.stat().st_size, "sha256": manifest[path.name]}
                        for path in artifacts}}
(project / "build/package-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"✓ {version}（build {build}）DMG／ZIP 实际内容、双架构、签名与 SHA-256 校验通过。")
