# GitHub 上传与发布

更新：2026-10-26。当前代码 0.2.0，源码仓库为 [oiiizhou/QingYou](https://github.com/oiiizhou/QingYou)。本地已生成 Apple Silicon + Intel 通用测试包，97 项自动化检查及已记录的实机流程通过；GitHub Releases 尚未发布该包，尚无 Developer ID 签名或公证。

## 在网页上传当前测试安装包

安装包通过 **Releases** 分发；不要将 DMG、ZIP 提交到源码目录，也不需要修改 `.gitignore`。

1. 先将准备发布的源码与文档更新提交到 `main`，核对该提交对应本地测试包的功能。当前 README 更新不改变应用二进制，无需为排版重新打包。
2. 打开 [新建 Release](https://github.com/oiiizhou/QingYou/releases/new)。如果先进入 Releases 页面，点击 **Create a new release** 或 **Draft a new release**。
3. 创建标签 **`preview-0.2.0`**，Target 选择 **`main`**，标题填写 **`轻右 0.2.0 · 首个公开测试版`**。
4. 在说明区域填写下面的发布说明。
5. 将工程目录 `dist/QingYou-0.2.0-test-20261026/` 中的以下四个文件拖入附件区域：
   - `QingYou-0.2.0-universal-test-20261026.dmg`，推荐给普通用户。
   - `QingYou-0.2.0-universal-test-20261026.zip`，应用 ZIP 备用包。
   - `SHA256SUMS.txt`。
   - `安装测试说明.txt`。
6. 勾选 **This is a pre-release**，等附件上传完成后检查名称和说明，再点击 **Publish release**。也可以先点 **Save draft** 保存草稿。

手动上传使用 `preview-0.2.0` 标签，不会触发现有的 `v*` 自动打包发布流程。之后的更新使用新标签，不覆盖已经分享的测试包。发布后，将版本页面链接发给用户；GitHub 自动附带的 **Source code (zip)** 和 **Source code (tar.gz)** 是源码，不是应用安装包。

发布完成后，将工程 README 的“尚未发布／尚待上传”状态改为实际发布状态，并补充该版本的下载链接；运行 `python3 scripts/sync_readme.py` 同步外层首页，再提交文档更新。

流程依据 [GitHub 官方发布说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。本指南只说明步骤，不会代替维护者创建或公开 Release。

### 可直接填写的发布说明

```markdown
轻右的首个公开测试版：将新建文档、图片处理与 PDF 工具放进 Finder 右键菜单。

### 下载与安装
- 推荐下载 QingYou-0.2.0-universal-test-20261026.dmg。
- 打开 DMG，将 QingYou.app 拖入「应用程序」，启动后通过「管理扩展」开启 Finder 扩展。
- 不要下载 Source code，除非你想自行编译。

### 环境与验证
- macOS 13 及以上；PDF 压缩需要 macOS 13.4 及以上。
- 通用包包含 Apple Silicon 与 Intel 架构；目前实机验收为 Apple Silicon / macOS 26.3，Intel 仍待实机验证。
- 本地 97 项自动化检查通过，部分图片与 PDF 流程已实测。

### 测试版状态
- 使用 ad-hoc 签名，尚未完成 Developer ID 签名与 Apple 公证，下载后首次打开可能遇到系统来源检查。
- 新图片／页面列表请先用上下箭头排序；新建文件可按 Return 改名，自动进入改名仍待复测。
- 另一台 Mac 的完整下载安装流程尚待验证，欢迎通过 Issues 反馈。
- PDF 重写不保证保留书签、交互表单或数字签名，原件会保留。

附件中的 SHA256SUMS.txt 可用于核对 DMG 与 ZIP。更多功能、限制与验证范围请参阅仓库 README。
```

## 先上传源码

当前工作区 Git 根目录在外层，源码位于 `QingYou/`。推荐保留现有结构整体上传；外层 README 已同步，根工作流会定位工程。若另建独立仓库，可在工作区之外复制 `QingYou/` 的源码内容（排除 build、dist 等），再初始化；不要在现有仓库中创建嵌套 Git 仓库。

本项目源码已经上传。下面保留首次接入本地仓库的通用步骤；已有远程与提交时，不要重复初始化。

### 本地检查

在源码工程内执行：

```bash
python3 scripts/sync_readme.py
python3 scripts/verify_docs.py
python3 scripts/verify_project.py
python3 scripts/verify_templates.py
bash scripts/test.sh
```

检查 README 图片和相对链接、忽略规则、待提交清单。源码、模板、许可证和文档可以入库；build、dist、日志、用户配置、签名材料与凭据不入库。`.gitignore` 不会自动移除已经跟踪的文件，首次提交前仍应查看清单。

### 首次推送示例

在 GitHub 创建空仓库，不预置 README／许可／gitignore，以便接入现有文件。以下命令是人工执行的模板，远程地址必须换成实际仓库，不要直接照抄占位地址。

在**外层仓库根目录**执行：

```bash
git status --short
git add .gitignore README.md LICENSE CONTRIBUTING.md .github QingYou
git diff --cached --stat
git commit -m "Initial QingYou developer preview"
git remote add origin https://github.com/YOUR-ACCOUNT/QingYou.git
git push -u origin main
```

已有远程或提交时先检查 `git remote -v` 和当前分支，不重复初始化、不覆盖现有历史。流程参考 [GitHub 官方说明](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)。

仓库描述可用：**原生 macOS Finder 右键工具：新建文档、粘贴为文件、图片处理与 PDF 工作台，Swift 编写，MIT 开源。**
建议主题词：`macos`、`swift`、`swiftui`、`finder-extension`、`productivity`、`pdf`、`image-processing`。分享封面可选 `QingYou/docs/assets/social-preview.png`。

## 通过 CI 自动构建与发布

现有工作流在 main 推送、PR 或手动触发时校验文档／模板、运行测试、构建双架构、打包并上传 Actions artifact。工作流配置存在不等于云端运行已通过，本地记录不能替代 CI 状态。

**推送 `v*` 标签会自动创建 GitHub 预览发布。** 尚不准备发布安装包时只推送代码分支，不推版本标签。上传源码不要求签名证书，GitHub 托管也不会为应用提供苹果签名或公证。

工程和外层各保留一份相同 workflow，以支持两种目录布局；GitHub 只执行实际仓库根目录的 `.github/workflows/`。

## 准备安装包时

```bash
# 在源码工程内执行
bash scripts/test.sh
python3 scripts/verify_project.py
python3 scripts/verify_templates.py
ARCHS="arm64 x86_64" bash scripts/build.sh
bash scripts/package.sh
```

产物为 `dist/` 中的 DMG、ZIP 与 `SHA256SUMS.txt`。未配置 Developer ID 时是 ad-hoc 签名、未公证预览包；发布说明应明确来源、系统与架构、功能限制和验证范围。不要将本机能启动等同于网络下载后能安装。

发布前同步 `Product.version`、两个 Info.plist 的版本号、递增 `CFBundleVersion`，并确保标签与应用版本一致。Bundle ID 是应用、扩展、请求及权限身份的一部分；仅准备上传源码不需要改动。若决定更换命名空间，应统一迁移配置和脚本，并评估旧版升级与授权影响。

## Developer ID 与公证

在发布者机器的钥匙串中准备有效 Developer ID Application 证书及 notarytool profile 后，按实际身份配置：

```bash
ARCHS="arm64 x86_64" SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="qingyou-notary" bash scripts/notarize.sh
```

脚本提供构建签名、提交公证、装订与重打包流程；本项目尚未实测完成此流程。证书私钥、Apple Account 密码和公证凭据不写入源码、仓库或日志。macOS 下载程序的检查说明见 [Apple 官方文档](https://support.apple.com/zh-cn/102445)。

## 发布前仍需验证

- 另一台 Mac 从网络下载、首次打开、Finder 扩展及文件夹权限。
- Intel、较早 macOS、外接盘与网络盘、大文件和只读目录。
- 新顺序列表拖动、自动名称编辑与终端服务提示。
- 复杂 PDF、签名／表单边界、OCR 排版准确率与辅助功能。
- 升级、登录启动、退出和卸载，用户原件及模板保留。

详见 [验证记录](VERIFICATION.md) 与 [更新说明](RELEASE_NOTES.md)。
