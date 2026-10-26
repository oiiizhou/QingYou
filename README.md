<!-- 镜像自 QingYou/README.md；请先编辑工程首页，再运行 python3 QingYou/scripts/sync_readme.py。 -->

<a id="top"></a>

<p align="center">
  <picture>
    <source type="image/svg+xml" srcset="QingYou/docs/assets/hero.svg">
    <img src="QingYou/docs/assets/hero.png" width="1280" alt="轻右 QingYou：文件之间，一切顺手。">
  </picture>
</p>

<h1 align="center">轻右 · QingYou</h1>

<p align="center">
  <strong>把常用的文件操作，放回右键菜单。</strong><br>
  新建文档、调整图片、整理 PDF，从 Finder 就近完成。<br>
  <sub>A native macOS Finder utility. Built with Swift, SwiftUI and AppKit.</sub>
</p>

<p align="center">
  <img src="QingYou/docs/assets/badge-macos.svg" alt="macOS 13+">
  <img src="QingYou/docs/assets/badge-swift.svg" alt="Swift 与 SwiftUI">
  <img src="QingYou/docs/assets/badge-license.svg" alt="MIT 开源许可">
  <img src="QingYou/docs/assets/badge-version.svg" alt="0.2.0 开发预览版">
</p>

<p align="center">
  <a href="#features">功能</a> ·
  <a href="#images">图片</a> ·
  <a href="#pdf">PDF</a> ·
  <a href="#clipboard">粘贴为文件</a> ·
  <a href="#start">开始使用</a> ·
  <a href="#build">源码构建</a> ·
  <a href="#faq">常见问题</a>
</p>

> **0.2.0 开发预览 · 2026-10-26**  
> 免费、MIT 开源，无需账号。当前提供源码与本地构建方式，**尚未发布与本文同步的正式安装包**；本地构建使用 ad-hoc 签名，尚未完成 Developer ID 签名与苹果公证。上传源码与发布下载包是两个独立步骤。

<table>
  <tr>
    <td align="center" width="25%"><strong>9 类</strong><br><sub>可配置右键功能</sub></td>
    <td align="center" width="25%"><strong>13 种</strong><br><sub>内置文件模板</sub></td>
    <td align="center" width="25%"><strong>12 项</strong><br><sub>图片与 PDF 工具</sub></td>
    <td align="center" width="25%"><strong>97 项</strong><br><sub>本地自动化检查通过</sub></td>
  </tr>
</table>

## 少打开一个窗口，少走几步

- **在当前目录开始。** 右键新建 TXT、Markdown、Word、Excel、PowerPoint 或代码文件，不先询问文件名。
- **让图片符合要求。** 设置像素范围、比例或自定义宽高，看清结果后保存副本。
- **把 PDF 整理好。** 合并、按范围拆分、压缩、重排页面，或导出图片与文字。
- **把剪贴板存下来。** 复制的文字或截图，直接生成当前目录中的文件。
- **保持安静。** 拷贝路径等简单操作没有成功弹窗；复杂任务使用独立原生窗口。

灰白平面、系统蓝、细边界，搭配真实的 macOS 窗口、菜单、焦点与快捷键。文件处理在本机完成，转换结果保留原件。

![图片调整工作台：原图与结果并排核对像素](QingYou/docs/assets/current-image-resize.png)

<details>
<summary><strong>看看独立工具窗口</strong> · 不必先进入轻右主页</summary>

![多图合成 PDF：图片顺序、纸张和逐页预览](QingYou/docs/assets/current-images-pdf.png)

![PDF 页面整理：顺序列表、页面预览与固定保存栏](QingYou/docs/assets/current-pdf-organize.png)

![深色外观与紧凑窗口中的图片调整](QingYou/docs/assets/current-image-dark.png)

</details>

<sub>工具窗口截图来自加载当前界面与模型代码的隔离验收应用，使用自制示例文件；真实 Finder 与安装验证另见验证记录。封面为品牌插画，不是界面截图。[素材来源与维护](QingYou/docs/assets/README.md)。</sub>

<a id="features"></a>

## 功能一览

| 场景 | 功能 | 使用方式 |
| :--- | :--- | :--- |
| 新建文档 | 13 种模板、自定义模板、WPS 打开偏好 | 直接创建“未命名”文件，冲突自动编号 |
| 拷贝路径 | 完整路径、多选逐行拷贝 | 顶层入口，静默完成 |
| 文件整理 | 剪切粘贴、拷贝到、移动到 | 同名保留两份或跳过，支持最近一批移动的撤销 |
| 粘贴为文件 | 文字 → TXT、图片 → PNG、文字 → Markdown | 当前目录落盘，不改变剪贴板内容 |
| 打开终端 | 当前目录打开 Terminal | 调用系统文件夹终端服务 |
| 图片调整 | 像素、比例、格式、质量、旋转、翻转 | 单张／多张，预览后保存副本 |
| 图片信息 | 文件时间、EXIF、相机、镜头、位置 | 只显示实际记录，支持另存去除位置的副本 |
| 图片转 PDF | 多图排序、纸张、方向、边距 | 每张图片生成一页 |
| PDF 工作台 | 合并、范围拆分、压缩、页面整理 | 独立原生窗口与 PDFKit 预览 |
| PDF 导出 | 页面图片、已有文字、扫描页 OCR | 按页码范围和输入顺序导出 |
| 显示与个性化 | 隐藏属性、文件夹图标 | 可恢复默认图标 |
| 操作记录 | 最近 100 条本地记录、结果定位 | 无云同步 |

### 文件模板

| 类型 | 内置格式 |
| :--- | :--- |
| 文本与笔记 | `.txt` · `.md` |
| 文字文档 | `.doc` · `.docx` |
| 电子表格 | `.xls` · `.xlsx` · `.csv` |
| 演示文稿 | `.ppt` · `.pptx` |
| 代码与配置 | `.py` · `.json` · `.yaml` · `.sh` |

六种 Office 模板随源码提供，是真实的文档格式；日常构建不依赖 Office 或 WPS。检测到 WPS 时，可以优先用它打开新建办公文档，该偏好默认开启，仅设置当前文件的打开关联。

例如右键创建演示文稿，会直接得到 `未命名.pptx`；重名时为 `未命名 2.pptx`。创建后会在 Finder 中选中，按 **Return** 使用系统改名。自动进入名称编辑已接入，但完整交互仍待进一步验证，见[已知限制](#limits)。

自定义模板支持启用、排序和命名；文字模板支持 `{{name}}`、`{{date}}` 占位符。

<a id="images"></a>

## 图片：调整之前，先看结果

Finder 右键选择 **“调整图片…”**。选中的图片会直接带入；没有适用选区时，用系统文件选择器补充输入。多个图片使用同一套参数批量处理。

| 调整方式 | 适用情况 |
| :--- | :--- |
| 限制最大宽高 | 如不超过 1920 × 1080，按比例缩小到范围内，不裁切 |
| 按百分比 | 将图片调整为 50% 等指定比例 |
| 自定义像素 | 锁定比例时宽高联动；解锁后独立设置宽高，可能改变图片形状 |

默认不放大小图。还可选择 PNG／JPEG／HEIC、调整有损质量、旋转、水平翻转，或去除副本中的位置。JPEG 使用白色背景处理透明区域，PNG 保留透明通道。

“沿用原格式”支持 PNG、JPEG、HEIC、TIFF；其他源格式会在确认前要求选择输出格式，不会悄悄转换。动态或多页图片在此工作台中需要先导出为单张。

**图片信息。** 分别显示文件创建／修改时间、EXIF 拍摄时间、像素、大小、色彩、相机、镜头、曝光及文件中的位置字段。缺失的地点、时区不会推测；只有主动点击地图按钮才打开地图。去除位置会另存重编码副本，保留原件及无关的作者／版权字段。

**图片合并为 PDF。** 添加多张图片，通过上下箭头调整顺序，再选择 A4、US Letter 或随图片尺寸、横竖方向和边距，逐页预览后生成 `图片合并.pdf`。图片按最长边 3200 像素以内处理，适合阅读与分享，不定位于原始分辨率印刷归档。

<a id="pdf"></a>

## PDF：先看清，再导出

**合并、拆分、压缩、页面整理**直接出现在 Finder 右键菜单中；导出图片与文字位于“导出 PDF”中。空白处也有入口，所需文件可以随后选择。

| 操作 | 可以做什么 | 结果 |
| :--- | :--- | :--- |
| 合并 PDF… | 添加多份 PDF、调整顺序，原文与合并结果并排查看 | `合并PDF.pdf` |
| 拆分 PDF… | 为每份结果填写范围与可选名称 | 原名＋页码，或自定义文件名 |
| 压缩 PDF… | 三种系统图片优化组合、实际体积对比 | `原名-压缩.pdf` |
| 整理 PDF 页面… | 重排、旋转、删除、插入其他 PDF 页面 | `原名-整理.pdf` |
| 导出 PDF → 导出为图片… | PNG／JPEG、72／144／300 DPI | `原名-页面图片` 文件夹 |
| 导出 PDF → 提取文字… | 提取已有文字，可补充识别无文字层页面 | `原名-文字.txt` |

### 拆分按范围，而不是强制一页一份

| 输入 | 结果 |
| :--- | :--- |
| `1-3` | 第 1 至 3 页合成一份 |
| `1-3,5` | 第 1 至 3 页与第 5 页合成一份 |
| 再添加一行 `4-6` | 额外生成包含第 4 至 6 页的另一份 |

拆分可为每份结果单独命名，输入与预览联动；越界、重复或无效范围会就地说明并禁用导出。图片和文字导出也支持 `3,1` 等顺序；页面图片用 `0001-原第3页.png` 的名称保留导出顺序及原页码。

压缩使用 **macOS 13.4+** 的 PDFKit 图片优化，保留文字与矢量，体积不保证更小，窗口会如实提示。OCR 在本机执行，复杂排版、表格与手写内容需要校对。

结果保存在右键所在目录；从工具箱启动时默认保存到第一份所选文件所在目录。同名自动编号，原件保留。新工具窗口支持进度、取消和先暂存后提交；失败或取消时回滚本次输出。新页面／图片顺序列表建议先用已验证的上下箭头，拖动实测状态见[验证范围](#verification)。

<a id="clipboard"></a>

## 粘贴为文件，和 ⌘V 有什么区别？

**⌘V 粘贴已复制的文件；“粘贴为文件”把剪贴板里的内容变成文件。**

| 剪贴板内容 | 右键操作 | 生成文件 |
| :--- | :--- | :--- |
| 网页／聊天／编辑器中复制的文字 | 粘贴为文件 | `未命名.txt`，UTF-8 |
| 复制的截图或图片 | 粘贴为文件 | `未命名.png` |
| Markdown 文字 | 按住 ⌥，选择“粘贴为 Markdown” | `未命名.md` |
| Finder 中已复制的文件 | 使用系统 ⌘V 或“粘贴文件到此处” | 不重复转换 |

没有可用内容时菜单禁用。新文件在当前目录创建，同名自动编号；不清空剪贴板，不显示成功弹窗。

<a id="start"></a>

## 开始使用

### 1. 构建并安装

目前请[从源码构建](#build)。尚无与本文同步的正式下载包，不需要购买或注册账号。

| 环境 | 当前状态 |
| :--- | :--- |
| 最低部署目标 | macOS 13；PDF 压缩需 13.4+ |
| 本地实机验证 | Apple Silicon / macOS 26.3 |
| Intel | 构建脚本支持，尚待实机验证 |
| 构建工具 | Xcode Command Line Tools 或完整 Xcode |
| 运行依赖 | 系统框架，无额外第三方运行时 |

### 2. 启用 Finder 扩展

1. 打开轻右，点击首页 **“管理扩展”**。
2. 按系统引导开启 **“轻右 Finder 扩展”**。
3. 返回 Finder，在文件、文件夹或空白处右击。

默认直接显示功能；也可在“右键菜单”中收纳到“轻右”子菜单。菜单生效范围默认为用户主目录与 `/Volumes`，包含子目录。未启用扩展时，主程序工具箱仍可独立使用。

### 3. 调成自己的习惯

- **右键菜单**：功能开关、顺序、收纳方式，以及日常精简／图文工作／全部功能预设。
- **文件模板**：模板名称、启用状态、自定义模板与 WPS 偏好。
- **通用设置**：登录启动、新建后打开或编辑名称、重名策略与反馈。

首次运行默认申请登录启动，只申请一次；手动关闭后不再自动开启。登录启动驻留菜单栏，普通打开显示主窗口。

| 快捷键 | 行为 |
| :--- | :--- |
| **⌘W** | 关闭当前窗口，保留其他窗口与菜单栏驻留 |
| **⌘Q** | 退出轻右 |
| **⌘,** | 打开轻右设置 |
| **Return** | Finder 中编辑所选文件名；任务窗口中执行可用的默认操作 |
| **Esc** | 新任务窗口中取消或请求取消处理 |

<a id="permissions"></a>

## 文件留在本机

文件转换、PDF 与文字识别在本机执行，无需账号，没有内置广告或遥测。主动点击地图、帮助或仓库链接时会打开对应外部应用或页面。

| 权限／系统集成 | 用途 |
| :--- | :--- |
| Finder 扩展 | 接入右键菜单 |
| 文稿、桌面等文件夹访问 | 处理这些目录中由你选择的文件，由 macOS 按需询问 |
| 辅助功能（可选） | 尝试自动进入 Finder 名称编辑，不用于图片或 PDF 算法 |
| 登录项 | 根据偏好登录启动 |

自动名称编辑只在 Finder 前台、单选及完整路径与新文件匹配时尝试；不能确认则保留选中，按 Return 改名。本地开发签名会随构建变化，更新后系统可能重新确认文件夹或辅助功能权限，不能把旧开关视为新构建已授权。

设置、自定义模板与最近操作记录保存于：

```text
~/Library/Application Support/QingYou/
├── settings.json
├── history.json
└── Templates/
```

历史可能包含处理过的文件名与路径，存于本机；报告问题时请移除个人信息。

<a id="verification"></a>

## 验证范围

以下为 **2026-10-26 本地记录**，不是 GitHub CI 通过徽章。

| 检查 | 结果 |
| :--- | :--- |
| 自动化检查 | **97 项通过**：57 项核心与媒体、23 项应用集成、17 项新工作台 |
| 六种 Office 模板 | OOXML／复合二进制结构校验通过 |
| 实际图片导出 | 2400 × 1600 → 1200 × 800，重新读取像素正确 |
| 实际 PDF 输出 | 两图 B→A 合成、页面重排／删除／旋转、压缩后页数与文字保持 |
| 范围导出 | `3,1` 的文件名、144 DPI 图片、TXT 顺序正确 |
| 扫描页 OCR | 无文字层的自制英文扫描 PDF 成功识别，不代表复杂文档准确率 |
| 原生交互 | 明暗与紧凑窗口、错误输入、真实 Finder 入口、输入框聚焦时 ⌘W |
| 本地安装 | 主程序与扩展匹配构建，严格签名校验通过，设置保留 |

<a id="limits"></a>

### 正在完善的部分

- **新列表拖动排序**：图片合成和页面整理的拖动尚未通过桌面实测，请先用上下箭头。原有 PDF 合并列表另有历史拖动验证，两者不混用结论。
- **自动进入文件名编辑**：已实现选择与路径校验，当前构建完整交互仍待复测，Return 可用。
- **终端入口**：已接入系统服务，实际权限提示及不同系统语言仍需更多设备验证。
- **平台覆盖**：Intel、较早 macOS、外接盘、网络盘、大文件、多显示器和完整辅助功能组合仍需补测。
- **PDF 兼容性**：不保证重写后保留原书签、交互表单或数字签名；签署文档应保留原件。锁定或损坏文件会说明错误。
- **动态图片**：调整／图片合成工作台拒绝多帧输入；旧的一键 PNG／JPEG 转换仅处理首帧且不保留全部元数据。
- **分发**：尚无 Developer ID 签名、公证和另一台 Mac 的完整下载安装验证。

[完整验证记录](QingYou/docs/VERIFICATION.md) · [更新记录](QingYou/docs/RELEASE_NOTES.md)

<a id="build"></a>

## 从源码构建

在仓库根目录打开终端，执行（源码位于 QingYou/）：

```bash
# 从外层仓库根目录进入工程
cd QingYou
bash scripts/build.sh

# 从菜单栏退出正在运行的轻右后安装
bash scripts/install.sh
```

生成 `build/QingYou.app`，安装到 `~/Applications/QingYou.app`。脚本按本机架构构建；日常构建无需 Python 第三方包、Office 或 WPS。当前验证使用 Swift 6.2.3，以 Swift 5 语言模式编译。

<details>
<summary><strong>测试、双架构构建与模板校验</strong></summary>

```bash
bash scripts/test.sh
python3 scripts/verify_project.py
python3 scripts/verify_templates.py
python3 scripts/verify_docs.py

# 支持构建通用版本；本地通过不等于完成 Intel 实机验证
ARCHS="arm64 x86_64" bash scripts/build.sh
```

应用使用系统 AppKit、SwiftUI、FinderSync、PDFKit、ImageIO 和 Vision。重新生成办公模板所需的开发依赖见[架构说明](QingYou/docs/ARCHITECTURE.md)。

</details>

<details>
<summary><strong>工程结构</strong></summary>

```text
QingYou/
├── Sources/
│   ├── Core/             配置、请求、文件与 PDF 基础操作
│   ├── App/              原生界面、任务调度、图片与 PDF 工作台
│   └── FinderExtension/  右键菜单与请求投递
├── Resources/            图标、权限声明、有效办公模板
├── Tests/                临时目录与独立剪贴板中的测试
├── scripts/              构建、安装、校验、文档同步与打包
├── docs/                 说明、架构、验证与截图
├── .github/              构建与预览版发布工作流
├── CONTRIBUTING.md
├── README.md
└── LICENSE
```

Finder 扩展负责菜单与请求，耗时任务由主程序执行。新工作台具有独立后台队列、预览代次与取消令牌；不在 Finder 进程内执行转换。

</details>

<a id="faq"></a>

## 常见问题

<details>
<summary><strong>能直接从 GitHub 下载使用吗？</strong></summary>

源码上传后可以下载并自行构建；可直接安装的 DMG／ZIP 需要另行发布到 Releases。目前没有正式下载包，也没有有效的下载按钮。GitHub 托管不等于苹果签名或公证，未来预览包会标明签名与验证状态。

</details>

<details>
<summary><strong>右键没有轻右的功能？</strong></summary>

在首页确认扩展状态，检查“右键菜单”的功能开关、通用设置中的生效目录；重新打开 Finder 窗口，再刷新扩展状态。也请检查同类扩展是否造成重复菜单。PDF 与图片工作台入口在空白处也可用，会随后选择文件。

</details>

<details>
<summary><strong>为什么读取文稿里的文件一直等待？</strong></summary>

查看 macOS 是否正在等待文件夹访问确认。开发版更新可能改变本地签名，系统会重新判断授权。本地已观察到允许文稿访问后恢复读取与导出；请根据自己的文件访问需求决定授权。不要将此权限和可选的辅助功能混淆。

</details>

<details>
<summary><strong>终端服务暂不可用怎么办？</strong></summary>

在系统设置“键盘 → 键盘快捷键 → 服务”中检查“新建位于文件夹位置的终端窗口”。系统语言和版本可能影响名称。当前入口调用 Terminal 的系统服务，提示行为仍有待更多实机覆盖。

</details>

<details>
<summary><strong>撤销和取消会恢复什么？</strong></summary>

撤销用于本次启动内最近一批移动，执行前会核对文件身份及原位置。图片／PDF 另存副本，不纳入移动撤销。新工具窗口的取消会请求停止后台任务，并回滚本次尚未完成的输出；已导出完成的结果由你自行保留或移除。

</details>

<details>
<summary><strong>macOS 提示无法验证开发者？</strong></summary>

当前本地构建没有 Developer ID 签名或苹果公证。从互联网下载时，macOS 仍会检查程序来源。请先核对来源及说明，参阅 [Apple 的安全打开 App 文档](https://support.apple.com/zh-cn/102445)。

</details>

<details>
<summary><strong>如何卸载？</strong></summary>

退出轻右后将应用移到废纸篓，或在工程目录执行 `bash scripts/uninstall.sh`。卸载脚本保留设置、自定义模板、操作记录和工作文件；需要清理本地配置时先自行备份。

</details>

## 参与改进与发布

欢迎反馈可复现的问题、改善文档和提交 Pull Request。[贡献指南](QingYou/CONTRIBUTING.md) 包含开发约定、测试与问题报告信息；[GitHub 发布指南](QingYou/docs/RELEASING.md) 区分首次上传源码、CI 构建和安装包发布。

[架构与开发约定](QingYou/docs/ARCHITECTURE.md) · [设计系统](QingYou/DESIGN.md) · [工具窗口设计](QingYou/docs/MEDIA_WORKSPACES.md)

## 开源许可

源码采用 [MIT License](QingYou/LICENSE)。轻右为独立实现，未包含其他右键工具的二进制程序、图标或模板资源。品牌图标、展示插画与自制示例截图的来源见[视觉资源说明](QingYou/docs/assets/README.md)。

---

<p align="center">
  <strong>轻右 QingYou</strong><br>
  <sub>文件留在本机，操作就在手边。</sub><br><br>
  <a href="#top">返回顶部 ↑</a>
</p>
