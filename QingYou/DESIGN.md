---
name: 轻右 QingYou
description: macOS 原生文件效率工具的当前设计系统
colors:
  accent: '#007AFF'
  success: '#34C759'
  canvas: '#F6F6F8'
  surface: '#FFFFFF'
  banner: '#F5F5F7'
  input: '#F2F2F7'
  sidebar: '#EBEBEC'
  border: rgba(210, 210, 215, 0.6)
  canvas-dark: '#202022'
  surface-dark: '#29292C'
  banner-dark: '#303033'
  input-dark: '#353538'
  sidebar-dark: '#252527'
  border-dark: rgba(85, 85, 91, 0.6)
typography:
  headline:
    fontFamily: system-ui
    fontSize: 22pt
    fontWeight: 600
  title:
    fontFamily: system-ui
    fontSize: 13pt
    fontWeight: 500
  body:
    fontFamily: system-ui
    fontSize: 13pt
    fontWeight: 400
  detail:
    fontFamily: system-ui
    fontSize: 12pt
    fontWeight: 400
  caption:
    fontFamily: system-ui
    fontSize: 11pt
    fontWeight: 400
  action:
    fontFamily: system-ui
    fontSize: 12pt
    fontWeight: 500
rounded:
  control: 7pt
  surface: 12pt
spacing:
  compact: 8pt
  gap: 12pt
  card: 16pt
  tool: 18pt
  panel: 20pt
  page: 24pt
components:
  button-primary:
    backgroundColor: '{colors.accent}'
    textColor: '#FFFFFF'
    typography: '{typography.action}'
    rounded: '{rounded.control}'
    padding: 0pt 12pt
  button-secondary:
    backgroundColor: '{colors.surface}'
    typography: '{typography.action}'
    rounded: '{rounded.control}'
    padding: 0pt 12pt
  search-field:
    backgroundColor: '{colors.input}'
    typography: '{typography.detail}'
    rounded: '{rounded.control}'
    padding: 0pt 9pt
    width: 200pt
    height: 30pt
  sidebar-item:
    typography: '{typography.body}'
    rounded: '{rounded.control}'
    padding: 0pt 12pt
    height: 36pt
  surface-card:
    backgroundColor: '{colors.surface}'
    rounded: '{rounded.surface}'
    padding: '{spacing.panel}'
  quick-entry:
    backgroundColor: '{colors.surface}'
    rounded: '{rounded.surface}'
    padding: '{spacing.card}'
  tool-tile:
    backgroundColor: '{colors.surface}'
    rounded: '{rounded.surface}'
    padding: '{spacing.tool}'
---

# Design System: 轻右 QingYou

## Overview

**Creative North Star: "macOS 原生效率软件"**

以用户确定的 macOS 原生效率软件风格为准：系统窗口、系统字体、紧凑工具栏和固定侧栏共同组织文件工作流。浅灰画布衬托白色内容，蓝色标识操作与关键选择，绿色说明真实就绪或成功状态。

本文从已实现的 SwiftUI / AppKit 代码提炼复用规则。单位均为 macOS 逻辑点（pt），不是屏幕像素；系统决定字体度量、窗口控件及原生菜单的具体呈现。YAML 中 system-ui 仅是 Font.system 的可移植描述，不要求加载网页字体。

**Key Characteristics:**

- 固定侧栏与真实系统交通灯。
- 灰色画布、白色内容、细边界，默认无阴影。
- 系统字体与 SF Symbols；状态来自实际数据。
- 明暗外观、减少动态效果与降低透明度遵从系统设置。

证据范围：`Sources/App/DesignSystem.swift`、`SettingsView.swift`、`ToolTile.swift`、`EntryPoint.swift`。本文描述本轮主程序外壳与这些共享组件，其他独立工作窗口沿用原生控件；不把首页特定文案提升为产品承诺。

## Colors

色值以 YAML 为规范；未固定的文字、警示色与系统材质继续由 AppKit / SwiftUI 语义色提供。

### Primary

- **系统蓝（accent）**：主按钮、关键选中和少量 SF Symbols 功能图标。选中底色由该色乘以 0.11，不另造蓝色卡片系列。

### Neutral

- **画布灰（canvas）**：主内容平面之外的背景。
- **内容白（surface）**：主内容平面、卡片及普通按钮。
- **横幅灰（banner）**：首页引导横幅，与白色内容仅作轻微区分。
- **输入灰（input）**：搜索输入与禁用按钮底色。
- **侧栏灰（sidebar）**：侧栏材质的基础色及降低透明度时的实色。
- **细边界（border）**：浅色边界为指定灰色的 60% 不透明度，圆角容器统一 1 pt 描边。
- **深色成对值（*-dark）**：在 `.darkAqua` 解析时逐项替换相应中性色；accent 与 success 不变。不要用整体反相替代成对映射。
- **语义文字**：主文字 `.primary`，辅助文字 `.secondary`，弱指引 `.tertiary`。它们是原生动态颜色，不固定成十六进制常量。

### Status

- **系统绿（success）**：Finder 已启用、成功反馈和工具适用性标记；同时提供文字或可访问性标签。
- 错误和警示沿用现有系统 `.orange`，未扩展为自定义状态色板。

**The 操作与状态各司其职 Rule.** 蓝色用于主操作、关键选中及少量功能图标；绿色用于就绪或成功状态，不能只为装饰制造状态。

## Typography

**Display Font:** 无独立展示字体；首页横幅使用系统字体。
**Body Font:** macOS `Font.system`，由系统提供 SF 与中文回退字体。
**Label/Mono Font:** 系统字体；统计采用 `.monospacedDigit()`，路径采用 `.system(..., design: .monospaced)`。

**Character:** 紧凑、可读的桌面工具文字。沿用系统度量，不设置全局字距、固定行高、全大写标题或网页式字体栈。

### Hierarchy

- **Headline**：页面和搜索结果标题，半粗体，见 headline。
- **Title**：条目与快捷入口标题，中等字重；工具卡标题使用同字号半粗体。
- **Body**：导航与主要控件文字，常规字重；选中导航改中等字重。
- **Detail**：说明、搜索文字与面包屑；面包屑当前项使用中等字重。
- **Caption**：辅助说明、分组名与状态；分组名可用中等字重。
- **Action**：SoftActionStyle 按钮标签，中等字重。

首页横幅的系统半粗体 24 pt、统计的半粗体等宽数字 26 pt 是当前组件局部值；不作为通用字号扩散。工具说明允许多行。原有 `.headline`、`.callout`、`.caption` 等语义字体继续采用系统度量。

**The 系统文字优先 Rule.** 沿用 Font.system 和系统语义文字颜色；数字统计使用 monospacedDigit，不把单个横幅或统计数字的字号扩展成全局显示字体。

## Layout

- **平台与窗口**：macOS 13+，SwiftUI `NavigationSplitView` 嵌入 AppKit `NSHostingController`。设置窗口挂载后以 `setContentSize` 设定首次内容尺寸 1040 × 760 pt，窗口最小 900 × 700 pt；SwiftUI 根视图最小 880 × 660 pt，最终窗口边界由 NSWindow 管理。
- **侧栏**：固定 220 pt；导航行的图标占位 20 pt、图文间距 10 pt。侧栏分组是功能分类，不是额外品牌标语。
- **工具栏**：`NSWindow.toolbarStyle = .unifiedCompact`，标题隐藏、标题栏透明；使用真实系统交通灯。左侧产品 / 当前页面面包屑，右侧原有操作与搜索框。
- **内容**：白色 ScrollView 平面置于灰色画布内，水平外边 12 pt、顶部 8 pt、底部 12 pt。内层内容最大宽度 920 pt，再加四周 24 pt 内边距；更宽时居中。内容垂直间距通常 20 pt。
- **容器密度**：通用卡片 20 pt 内边距；快捷入口与统计卡 16 pt；工具卡 18 pt；横幅 24 pt。复用 spacing 中的实际值，而非强制所有间距落在单一网格。
- **页面组合**：首页当前采用灰横幅、三个等宽统计、Finder 状态条与两个快捷入口。这是首页结构；其他页面仍按任务组织。工具卡使用最小 240 pt 的自适应网格，列间距 14 pt；快捷入口固定为两列、间距 12 pt。
- **尺寸适配**：窗口缩小时内容滚动、工具网格减少列数；没有移动端断点或 iOS 折叠导航规范。

## Elevation & Depth

共享表面默认无阴影。用画布、内容、横幅之间的灰度差和细边界表达层级；侧栏以原生 `NSVisualEffectView` 的 `.sidebar` 材质提供环境感，混合模式为 `.behindWindow`、跟随窗口活跃状态，材质叠加不透明度 0.75。降低透明度时不创建材质层，保留实色侧栏。

悬停不产生位移或缩放。HoverSurface 使用 `.primary.opacity(0.22)` 的中性 1 pt 覆盖边界；普通按钮或导航悬停使用 `.primary.opacity(0.045)` 底色。减少动态效果时自定义动画置为 nil。按钮按下动画 100 ms、悬停 120 ms，页面切换与拖放反馈 180 ms。

**The 平面层级 Rule.** 用底色、1 pt 边界和原生侧栏材质区分区域；悬停仅改变底色或边界，不加入浮起位移、渐变或大阴影。

## Shapes

容器采用 surface 圆角，按钮、搜索与导航行采用 control 圆角，均使用 `RoundedRectangle`。Surface 的边界用 `strokeBorder`，宽度 1 pt。主内容是有细边界的平面，不增加投影。图标来自 SF Symbols；窗口控制来自 NSWindow，不绘制替身。

工具拖放区沿用 1 pt 虚线（5 / 4 pt），指明可接收文件的区域；拖入时使用低不透明度 accent 底色与 accent 边界。这是交互状态，不扩展成装饰容器样式。

## Components

### Buttons

紧凑桌面按钮，最小高度 30 pt、水平内边距 12 pt，使用 control 圆角。

- **主按钮**：`SoftActionStyle(prominent: true)`，accent 底、白字、无可见边界。悬停时 accent 不透明度 0.88，按下时 0.75。
- **普通按钮**：`SoftActionStyle()`，surface 底、原生主文字、细边界；按下底色为 `.primary.opacity(0.09)`。
- **禁用**：input 底与 `.secondary` 文字，不触发动作；工具卡仍保留不可用原因。
- **原生控件**：其他 Button、Toggle、Picker、Menu 的尺寸与焦点由 macOS 管理，不强制套用自定义按钮。

### Inputs / Fields

搜索框为 200 × 30 pt，水平内边距 9 pt，input 底、control 圆角。焦点时边界为 accent 的 0.65 不透明度；输入文字随明暗使用黑 / 白的 0.85，提示与图标为 0.55。支持 ⌘F 聚焦、Escape 清空并退出焦点；有内容时出现清除按钮。其他 TextField 保留既有原生行为。

### Navigation

`SidebarNavigationItem` 是整行可点击的原生 Button，36 pt 高。未选中为普通文字和次级图标；选中为中等字重、蓝色图标及 accent 0.11 底色，并带 `.isSelected` 可访问性特征。悬停仅用中性底色；左侧导航与工具栏面包屑显示同一页面状态。

### Cards / Containers

`Surface` 提供 surface 底、surface 圆角和细边界；内容容器按 Layout 中已有密度填充。`HoverSurface` 只用于可交互或对应交互内容的容器，enabled 为 false 时不显示悬停边界。通用卡片不因表面相同就自动变成整卡按钮。

### Quick Entry

`QuickEntryLabel` 使用 18 pt SF Symbol、13 pt 中等字重标题、11 pt 说明与方向指引；整张内容形状可命中，最小高度 72 pt。新建文件使用原生 Menu，配合 `.menuStyle(.button).buttonStyle(.plain)` 和隐藏默认指示器，仍由原生菜单承载真实模板动作；其他入口使用 Button。

### Tool Tile

`ToolTile` 使用图标、标题、说明和独立动作按钮。工具说明至少 36 pt 高并允许换行，18 pt 内边距，底部按钮保留原始操作。仅适用文件的工具可运行；不适用时图标变为次级色，按钮禁用并说明原因。适用标记沿用 success 并提供标签，不改变卡片背景。

### Metrics / Status

统计值来自启用的菜单项、启用的模板和可用工具列表，统计卡为可导航的 Button。Finder 状态来自扩展状态，绿点和文字同步；刷新和管理扩展是独立原生按钮。处理进度与完成提示位于底部 activityBar，使用系统 `.bar` 材质，并提供原有结果操作。

## Do's and Don'ts

### Do:

- **Do** 使用 SwiftUI / AppKit 原生窗口、菜单、焦点和键盘响应；保留 NSWindow 的关闭、最小化、全屏和拖动行为。
- **Do** 复用语义色与 Surface、SoftActionStyle、SidebarNavigationItem、QuickEntryLabel；深色外观使用既有成对映射。
- **Do** 让文字可换行、卡片可滚动；用真实统计、可读状态文字与控件语义补充颜色。
- **Do** 在减少动态效果时停用自定义动画，在降低透明度时使用实色侧栏。

### Don't:

- **Don't** 添加装饰渐变、光晕、大阴影、浮起卡片或大写英文标语。
- **Don't** 把蓝色铺满内容或把未完成的状态涂成绿色；普通悬停边界保持中性。
- **Don't** 用仿制交通灯替代 NSWindow 控制，也不要把 SF Symbols 替换成表情字符。
- **Don't** 把 sidecar 的 HTML/CSS 或预览色阶作为运行时设计源；不得将当前 macOS 界面写成 iOS 或网页实现。

规范边界：规范 token 层未新增未使用的色阶、品牌承诺、全局字号或移动端行为。sidecar 的色阶和 HTML/CSS 仅用于规范面板展示，不能准确复现 AppKit 材质、系统菜单、SF Symbols、系统字体度量及真实焦点；运行时依据仍是上述 SwiftUI / AppKit 源文件。此扫描未发现需要固化为规则的额外视觉缺陷，也未修复其他窗口的潜在漂移。
