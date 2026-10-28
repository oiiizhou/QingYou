# README 视觉资源与维护

更新：2026-10-28。品牌封面延续应用图标的深青与薄荷 Q，软件界面采用灰白、系统蓝和原生控件；插画与界面截图分别标注，不将插画当作运行画面。

## 当前公开展示

| 文件 | 来源与用途 |
| --- | --- |
| hero.svg / hero.png | 项目原创矢量品牌封面及 2 倍导出，不是 UI 截图 |
| social-preview.png | 品牌封面的 1280 × 640 分享图 |
| badge-*.svg | 随仓库提供的静态平台、语言、许可和开发版本标识 |
| current-image-resize.png | 当前工具代码的隔离原生验收窗口，使用自制示例 JPEG |
| current-pdf-organize.png | 同一验收应用的 PDF 页面整理，自制 6 页示例文档 |
| current-image-dark.png | 当前代码的深色紧凑窗口和同一图片夹具 |
| current-images-pdf.png | 多图合成 PDF 的原生任务窗口 |
| current-pdf-compress.png | PDF 压缩实际对比，示例可能没有体积收益 |
| workflow.svg / workflow.png | 早期原创流程插画，当前首页未引用 |
| app-icon.png | 现有图标预览 |

当前 README 不再引用早期 `v0.2-*.png` 截图；这些文件仅作本地历史留存并由忽略规则排除。`badges.svg / badges.png` 同为早期素材，不能作为在线 CI 状态。

工具截图的示例文件、相机信息与 PDF 内容均为自制夹具，非用户文档；临时路径不是应用固定保存位置。截图与源文件来源散列记录在 [provenance.json](provenance.json)。图片自身没有经过 AI 改绘。

## 更新方式

替换截图前核对当前业务代码、窗口大小、明暗外观、示例文件来源与保存路径。不要公开个人文件名、真实 GPS、账号、操作历史或开发者个人路径，也不要把测试替身状态写成生产运行证据。

封面保留 SVG 源；在工程目录运行以下命令重新导出品牌图，不修改截图：

```bash
swift scripts/render_readme_assets.swift
```

工程首页是唯一正文来源，外层镜像使用：

```bash
python3 scripts/sync_readme.py
python3 scripts/verify_docs.py
```

所有图片本地随仓库提供，无远程图片服务或动态徽章。版本统计注明本地验证日期；下载入口指向已发布版本的安装包，版本徽章与程序元数据同步。
