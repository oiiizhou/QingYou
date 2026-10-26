# macOS 原生界面重构

本轮方向由用户明确指定，直接执行；无需重新选择配色或布局。采用 SwiftUI 和 AppKit 实现，未引入 Web 框架。

## Direction contract

THESIS：面向 Finder 文件工作流的效率工具，操作优先、状态清楚。保留菜单、模板、工具、日志和设置的真实数据与行为。

OWN-WORLD：SF / 苹方系统字体；浅灰画布、白色内容、系统蓝操作、绿色就绪提示；统一 1 pt 边框，取消装饰渐变、光晕和浮起卡片。

STORY：打开后确认 Finder 连接状态；从真实数量进入菜单、模板、工具；搜索原有功能；完成操作后查看原有记录。

FIRST VIEWPORT：220 pt 固定侧栏、系统紧凑工具栏与交通灯；左侧产品/当前页面面包屑，右侧搜索与原有操作。12 pt 外侧灰色画布边、白色主平面，内容 24 pt 边距：浅灰横幅、三项统计、扩展状态、双列快捷入口。

FORM：用户指定的 macOS 效率软件结构。系统原生控件负责窗口和键盘行为。悬停只改变底色或边框；120–180 ms 反馈，减少动态效果时关闭动画。深色映射保持相同层级；降低透明度时侧栏使用实色。

FINISH：构建与原有测试通过；独立预览检查首页、搜索、工具箱、设置和明暗外观；审阅并记录最终设计规范。

## 组件检查点

- 外壳：用户随时能定位当前页面；面包屑与导航一致，系统控制仍可关闭、最小化与全屏。侧栏仅负责定位，蓝色仅表达选择和操作。
- 首页：文件工具和 Finder 状态优先；真实统计可进入对应页面，统计数字使用等宽数字；卡片 12 pt 圆角、16–24 pt 内边距。
- 工具：标题、说明和运行按钮三级结构；不适用工具禁用但保留可读说明；拖入只是暂存，原有接受规则不变。
- 设置与 PDF：继续使用原有 Picker、Toggle、TextField、PDFKit 与列表；只统一强调色、边界和表面，不改业务回调。

## 实现位置

- Sources/App/DesignSystem.swift：语义色、边界、悬停、按钮、侧栏和快捷入口标签。
- Sources/App/SettingsView.swift：外壳、面包屑、搜索、首页以及原有页面。
- Sources/App/ToolTile.swift：统一工具卡片。
- Sources/App/EntryPoint.swift：系统紧凑窗口工具栏。

系统窗口与工具栏参考：[Windows](https://developer.apple.com/design/human-interface-guidelines/windows)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)。
