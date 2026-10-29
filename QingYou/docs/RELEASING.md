# GitHub 上传与发布

更新：2026-10-29。源码仓库：[oiiizhou/QingYou](https://github.com/oiiizhou/QingYou)。当前预览版为 **0.2.2 / build 7**，安装包位于 [preview-0.2.2](https://github.com/oiiizhou/QingYou/releases/tag/preview-0.2.2)；上一版 `preview-0.2.1` 保留下载。

源码通过 Git 提交，应用安装包通过 **Releases** 分发。DMG、ZIP、构建日志、用户配置和签名材料不提交到源码仓库。

## 1. 核对版本与功能

此仓库外层是 Git 根目录，源码工程位于 `QingYou/`。不要在里面再初始化 Git 仓库。

发布前同步 `Sources/Core/Configuration.swift`、两个 `Resources/*-Info.plist` 的版本，并递增 `CFBundleVersion`。同步 README、版本徽章、封面、安装说明和更新记录。工程 README 是正文来源，外层首页通过脚本同步。

在源码工程目录执行：

```bash
python3 scripts/sync_readme.py
python3 scripts/verify_docs.py
python3 scripts/verify_project.py
python3 scripts/verify_templates.py
bash scripts/test.sh
```

本地检查通过后，还需要验证实际安装的 Finder 菜单、任务窗口、快捷键和升级流程。测试范围及未覆盖设备写入 [验证记录](VERIFICATION.md)，不把编译成功当作另一台 Mac 已验证。

## 2. 构建并核对安装包

```bash
ARCHS="arm64 x86_64" bash scripts/build.sh
bash scripts/package.sh
python3 scripts/verify_package.py
```

当前版本的产物：

| 文件 | 用途 |
| --- | --- |
| `dist/QingYou-0.2.2.dmg` | 推荐安装包，包含应用程序目录入口及中文安装说明 |
| `dist/QingYou-0.2.2.zip` | 同一应用的备用 ZIP |
| `dist/SHA256SUMS.txt` | 两个安装包的 SHA-256 |
| `docs/安装说明.txt` | 可作为独立附件，上传时可命名为 `INSTALL.txt` |

校验脚本实际解压 ZIP、只读挂载 DMG，检查包内程序与当前构建逐文件一致，主程序和扩展都有两种架构，签名完整，模板和许可齐全，且没有个人配置或操作历史。结果写入忽略目录 `build/package-verification.json`。

未配置 Developer ID 时采用 ad-hoc 签名、未经公证；发布说明必须写明。严格签名校验只确认完整性，不等于苹果公证。

## 3. 提交并同步源码

在外层 Git 根目录执行：

```bash
git status --short
git diff --check
git add README.md .github QingYou
git diff --cached --stat
git commit -m "Release QingYou 0.2.2 preview"
git push origin main
```

先审阅待提交清单，保留其他人的修改。不要强制推送或覆盖已有历史。已有远程时不重复 `git remote add`；用 `git remote -v` 核对仓库地址。网络断连不表示本地提交丢失，应先排查连接再重试。

在 [Actions](https://github.com/oiiizhou/QingYou/actions) 确认**本次提交**的校验、测试、双架构构建和安装包检查通过。

## 4. 上传并发布

手动发布使用 **`preview-0.2.2`**，指向已经验证的准确提交，不覆盖旧版。该标签不会触发 `v*` 自动发布，避免两份 Release 竞争。

### 网页操作

1. 打开 [新建 Release](https://github.com/oiiizhou/QingYou/releases/new)。
2. 创建 `preview-0.2.2`，Target 选择已验证的提交；标题填写「轻右 0.2.2 · 右键更快，操作更顺手」。
3. 将 [RELEASE_NOTES.md](RELEASE_NOTES.md) 的内容填入发布说明。
4. 在 **Attach binaries** 中上传 DMG、ZIP、SHA256SUMS.txt 和安装说明，等待附件上传完成。
5. 选择 **Pre-release**。先保存草稿，核对版本和附件，再发布。

说明编辑器里的图片附件入口用于正文配图，安装包应放进下面的二进制附件区域。

### GitHub CLI

先完成 `gh auth login`。以下命令在外层根目录执行，`--target` 固定为当前提交：

```bash
cp QingYou/docs/安装说明.txt QingYou/dist/INSTALL.txt
gh release create preview-0.2.2 \
  --target "$(git rev-parse HEAD)" --draft --prerelease \
  --title "轻右 0.2.2 · 右键更快，操作更顺手" \
  --notes-file QingYou/docs/RELEASE_NOTES.md \
  QingYou/dist/QingYou-0.2.2.dmg QingYou/dist/QingYou-0.2.2.zip \
  QingYou/dist/SHA256SUMS.txt QingYou/dist/INSTALL.txt

# 核对草稿附件、标签和提交后公开发布
gh release edit preview-0.2.2 --draft=false
```

发布后重新下载附件，对照 SHA256SUMS.txt，确认 README 下载链接可访问。GitHub 自动附带的 **Source code (zip / tar.gz)** 是源码，不是应用安装包。

## 自动发布与正式签名

仓库工作流在 main 推送、PR 或手动触发时校验、测试、构建、打包并验证产物。根目录与工程内保留相同 workflow，支持两种布局；GitHub 只执行根目录那份。

**推送 `v*` 标签会自动创建预览 Release**，标签必须严格等于应用版本前加 `v`。使用这种方式时不要再手动创建同一版本发布。GitHub 托管不会提供苹果签名或公证。

正式分发需由维护者准备 Developer ID Application 证书及 notarytool profile，再使用：

```bash
ARCHS="arm64 x86_64" SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="qingyou-notary" bash scripts/notarize.sh
```

该项目尚未实测完成 Developer ID 公证流程。证书私钥、Apple Account 密码与公证凭据不写入源码或日志。

发布步骤参考 [GitHub 官方文档](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)；网络下载安装检查参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。
