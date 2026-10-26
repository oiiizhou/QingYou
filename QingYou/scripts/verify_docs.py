"""检查公开文档的本地链接、显式锚点和首页同步；无需第三方依赖。"""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import subprocess

project = Path(__file__).resolve().parent.parent
files = [project / name for name in ['README.md', 'CONTRIBUTING.md', 'DESIGN.md', 'PRODUCT.md']]
files += sorted((project / 'docs').rglob('*.md'))
workspace = project.parent
if project.name == 'QingYou' and (workspace / '.git').exists():
    files += [workspace / 'README.md', workspace / 'CONTRIBUTING.md']


def prose(text):
    lines, fence = [], None
    for line in text.splitlines():
        marker = re.match(r'^\s*(`{3,}|~{3,})', line)
        if marker:
            kind = marker[1][0]
            if fence is None:
                fence = kind
            elif fence == kind:
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return '\n'.join(lines)


failures = []
checked = 0
for source in files:
    text = prose(source.read_text(encoding='utf-8'))
    urls = re.findall(r'!?\[[^\]\n]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)', text)
    urls += re.findall(r'(?:src|srcset|href)="([^"]+)"', text)
    for url in urls:
        url = url.strip('<>')
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc:
            continue
        target = (source.parent / unquote(parsed.path)).resolve() if parsed.path else source
        checked += 1
        if not target.exists():
            failures.append(f'{source.relative_to(project) if source.is_relative_to(project) else source.name}: 缺少 {url}')
            continue
        # README 的公开导航使用显式 id，避免依赖渲染器的中文标题 slug 差异。
        if parsed.fragment and target.suffix == '.md':
            body = target.read_text(encoding='utf-8')
            anchors = set(re.findall(r'\bid=[\"\x27]([^\"\x27]+)', body))
            if anchors and parsed.fragment not in anchors:
                failures.append(f'{source.name}: 缺少锚点 {url}')
if failures:
    raise SystemExit('\n'.join(failures))
subprocess.run(['python3', str(project / 'scripts/sync_readme.py'), '--check'], check=True)
print(f'✓ {len(files)} 份 Markdown 文档、{checked} 个本地链接／锚点检查通过。')
