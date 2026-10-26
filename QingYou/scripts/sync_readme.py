"""把工程首页同步到外层工作区，保持 GitHub 首屏内容与相对链接一致。"""
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="只检查，不写入文件")
args = parser.parse_args()

project = Path(__file__).resolve().parent.parent
workspace = project.parent
if project.name != "QingYou" or not (workspace / ".git").exists():
    print("当前为独立工程，无需同步外层 README。")
    raise SystemExit(0)

content = (project / "README.md").read_text(encoding="utf-8")


def target(url):
    if re.match(r"(?:[a-z][a-z0-9+.-]*:|/|#)", url, re.I):
        return url
    return "QingYou/" + url


# 只调整链接目的地；正文、代码块和页面内锚点保持原样。
content = re.sub(r"(!?\[[^\]\n]+\]\()([^\s)]+)(\))",
                 lambda m: m[1] + target(m[2]) + m[3], content)
content = re.sub(r'((?:srcset|src|href)=")([^"]+)(")',
                 lambda m: m[1] + target(m[2]) + m[3], content)
directory_note = "将终端切换到本 README 所在的工程目录，执行："
build_comment = "# 在 QingYou 工程目录执行"
if content.count(directory_note) != 1 or content.count(build_comment) != 1:
    raise SystemExit("构建说明已变化，请先更新同步脚本中的目录提示。")
content = content.replace(directory_note, "在仓库根目录打开终端，执行（源码位于 QingYou/）：")
content = content.replace(build_comment, "# 从外层仓库根目录进入工程\ncd QingYou")
content = ("<!-- 镜像自 QingYou/README.md；请先编辑工程首页，再运行 "
           "python3 QingYou/scripts/sync_readme.py。 -->\n\n" + content)
destination = workspace / "README.md"
if args.check:
    if not destination.exists() or destination.read_text(encoding="utf-8") != content:
        raise SystemExit("外层 README 尚未同步，请运行 scripts/sync_readme.py。")
    print("外层与工程 README 已同步，相对链接和构建目录提示一致。")
else:
    destination.write_text(content, encoding="utf-8")
    print("已同步外层 README。")
