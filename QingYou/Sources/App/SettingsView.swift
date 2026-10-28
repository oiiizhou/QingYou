import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let qingYouFocusSearch = Notification.Name("QingYou.focusSearch")
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case overview, menu, templates, favorites, applications, tools, history, preferences
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "开始使用"
        case .menu: return "右键菜单"
        case .templates: return "文件模板"
        case .favorites: return "常用目录"
        case .applications: return "打开方式"
        case .tools: return "工具箱"
        case .history: return "操作记录"
        case .preferences: return "通用设置"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .menu: return "cursorarrow.click.2"
        case .templates: return "doc.on.doc"
        case .favorites: return "star"
        case .applications: return "arrow.up.forward.app"
        case .tools: return "wrench.and.screwdriver"
        case .history: return "clock.arrow.circlepath"
        case .preferences: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "常用的文件操作，放在顺手的位置。"
        case .menu: return "选择需要的功能，按自己的习惯调整顺序。"
        case .templates: return "用有效的空白文档或自己的文件，一键开始。"
        case .favorites: return "右键打开目录，也可以把文件直接发送过去。"
        case .applications: return "让文件和文件夹在合适的应用中打开。"
        case .tools: return "也可以直接在这里选择文件、运行工具。"
        case .history: return "最近 100 条操作，仅保存在这台 Mac 上。"
        case .preferences: return "开机登录时自动启动、文件操作与交互偏好。设置即时保存。"
        }
    }
}

private let brand = QingYouStyle.accent

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var loginItem: LoginItemController
    init(store: AppStore) {
        self.store = store
        self.loginItem = store.loginItem
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var dropTargeted = false
    @State private var historyFilter = 0
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selection: Binding<SettingsPage?> {
        Binding(get: { store.selectedPage }, set: { if let page = $0 { store.selectedPage = page } })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: QingYouStyle.sidebarWidth,
                                                ideal: QingYouStyle.sidebarWidth,
                                                max: QingYouStyle.sidebarWidth)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let error = store.configurationError {
                            card {
                                Label("设置需要检查", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text(error).font(.callout).textSelection(.enabled)
                                Button("打开配置目录") { NSWorkspace.shared.open(Product.supportDirectory) }
                            }
                        }
                        if searchText.isEmpty {
                            if store.selectedPage != .overview {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(store.selectedPage.title).font(.system(size: 22, weight: .semibold))
                                    Text(store.selectedPage.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.padding(.bottom, 4)
                            }
                            page
                        } else {
                            searchResults
                        }
                    }
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(24).frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
                // 页面切换重置各自的滚动容器，工具箱的滚动位置不会带入设置页。
                .id(searchText.isEmpty ? store.selectedPage.rawValue : "search")
                // 灰色画布露出窄边，内容仍是白色平面，不使用浮动阴影。
                .background(QingYouStyle.surface, in: RoundedRectangle(cornerRadius: QingYouStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: QingYouStyle.radius)
                    .strokeBorder(QingYouStyle.border, lineWidth: 1))
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
                .animation(motion, value: store.selectedPage)
                activityBar
            }
            .background(WorkspaceBackground())
            .toolbar {
                ToolbarItem(placement: .navigation) { breadcrumb.environment(\.colorScheme, scheme) }
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()
                    Button { store.undoLastMoveOrRename() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(store.undoMappings.isEmpty || store.pendingTasks > 0)
                        .help("撤销轻右上次移动或重命名（⇧⌘Z）")
                        .accessibilityLabel("撤销文件操作")
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                    Button { NSWorkspace.shared.open(Product.userHome) } label: { Image(systemName: "folder") }
                        .help("在 Finder 中打开个人文件夹").accessibilityLabel("打开 Finder")
                    searchField.environment(\.colorScheme, scheme)
                }
            }
        }
        .tint(brand)
        .toolbarColorScheme(scheme, for: .windowToolbar)
        .font(.system(size: 13))
        .frame(minWidth: 880, minHeight: 660)
        .background(WorkspaceBackground())
        .onChange(of: store.selectedPage) { _ in query = "" }
        .onReceive(NotificationCenter.default.publisher(for: .qingYouFocusSearch)) { _ in searchFocused = true }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(brand).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("轻右").font(.system(size: 16, weight: .semibold))
                    Text("Mac 文件工具").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarSection("工作空间")
                    navigationRow(.overview)
                    navigationRow(.tools)
                    navigationRow(.history)
                    sidebarSection("偏好设置").padding(.top, 24)
                    navigationRow(.menu)
                    navigationRow(.templates)
                    navigationRow(.preferences)
                }.padding(.horizontal, 12)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Circle().fill(store.extensionEnabled ? QingYouStyle.success : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(store.extensionEnabled ? "已连接 Finder" : "等待启用扩展")
                    Spacer(minLength: 0)
                    Text("0.2").foregroundStyle(.secondary)
                }.font(.system(size: 11)).padding(16).accessibilityElement(children: .combine)
            }
        }
        .background(SidebarBackground().ignoresSafeArea())
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func navigationRow(_ page: SettingsPage) -> some View {
        SidebarNavigationItem(title: page.title, symbol: page.symbol, selected: store.selectedPage == page) {
            withAnimation(motion) { store.selectedPage = page }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            Button("轻右") { query = ""; store.selectedPage = .overview }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("返回开始使用")
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? store.selectedPage.title : "搜索")
                .fontWeight(.medium).lineLimit(1)
        }.font(.system(size: 12)).accessibilityElement(children: .contain)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(searchInk.opacity(0.55))
            TextField("", text: $query, prompt: Text("搜索功能与设置").foregroundColor(searchInk.opacity(0.55)))
                .textFieldStyle(.plain).font(.system(size: 12))
                .foregroundColor(searchInk.opacity(0.85))
                .focused($searchFocused).accessibilityLabel("搜索功能与设置")
                .onExitCommand { query = ""; searchFocused = false }
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(searchInk.opacity(0.55))
                }.buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 9).frame(width: 200, height: 30)
        .background(QingYouStyle.input, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(searchFocused ? brand.opacity(0.65) : Color.clear, lineWidth: 1))
    }

    // 工具栏的材质可能单独解析文字外观；让搜索文字始终跟随输入框底色。
    private var searchInk: Color { scheme == .dark ? .white : .black }

    @ViewBuilder private var activityBar: some View {
        if store.pendingTasks > 0 {
            Divider()
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(store.currentTask.isEmpty ? "准备处理…" : store.currentTask).font(.callout)
                Spacer()
                Text(store.pendingTasks > 1 ? "另有 \(store.pendingTasks - 1) 项等待" : "可继续使用 Finder")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(.bar)
        } else if let entry = store.latestFeedback {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: entry.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.failed ? Color.orange : QingYouStyle.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.callout.weight(.medium))
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let path = entry.outputPath {
                    Button("显示结果") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                Button { withAnimation(motion) { store.latestFeedback = nil } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("收起完成提示")
            }.padding(14).background(.bar).transition(.opacity)
        }
    }

    private var searchResults: some View {
        let pages = SettingsPage.allCases.filter { $0 != .favorites && $0 != .applications }.filter { ($0.title + $0.subtitle).localizedStandardContains(searchText) }
        let commands = ToolCommand.available.filter { $0.matches(searchText) }
        let features = MenuFeature.available.filter { ($0.title + $0.detail).localizedStandardContains(searchText) }
        let templates = store.configuration.templates.filter { $0.enabled && ($0.name + $0.fileExtension).localizedStandardContains(searchText) }
        return VStack(alignment: .leading, spacing: 18) {
            Text("搜索结果").font(.system(size: 22, weight: .semibold))
            Text("功能、设置和文件模板").font(.callout).foregroundStyle(.secondary)
            if pages.isEmpty && commands.isEmpty && templates.isEmpty && features.isEmpty {
                empty("没有找到相关功能", "试试「PDF」「文字」「路径」或「模板」。", "magnifyingglass")
            }
            if !commands.isEmpty {
                card {
                    Text("工具").font(.headline)
                    if !store.stagedFiles.isEmpty {
                        Text("将使用工具箱已选择的 \(store.stagedFiles.count) 个项目").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(commands) { command in
                        Button { store.execute(command) } label: {
                            searchRow(command.title, command.detail, command.symbol)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !features.isEmpty {
                card {
                    Text("Finder 菜单功能").font(.headline)
                    ForEach(features) { feature in
                        Button { query = ""; store.selectedPage = .menu } label: {
                            searchRow(feature.title, feature.detail, feature.symbol)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !pages.isEmpty {
                card {
                    Text("设置与页面").font(.headline)
                    ForEach(pages) { page in
                        Button { query = ""; store.selectedPage = page } label: {
                            searchRow(page.title, page.subtitle, page.symbol)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !templates.isEmpty {
                card {
                    Text("新建文件").font(.headline)
                    ForEach(templates) { template in
                        Button {
                            guard let directory = store.chooseDirectory(message: "在哪里创建\(template.name)？") else { return }
                            store.perform(.init(action: .createFile, directory: directory.path, argument: template.id))
                        } label: { searchRow(template.name, "." + template.fileExtension, "doc.badge.plus") }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func searchRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(brand).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    @ViewBuilder private var page: some View {
        switch store.selectedPage {
        case .overview: overview
        case .menu: menuSettings
        case .templates: templates
        case .favorites: favorites
        case .applications: applications
        case .tools: tools
        case .history: history
        case .preferences: preferences
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(Surface())
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("文件之间，一切顺手。").font(.system(size: 24, weight: .semibold))
                    Text("从一次右键开始，让整理、创作和分享更轻松。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("轻量常驻 · 本机处理").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.selectedPage = .tools } label: {
                    Label("打开工具箱", systemImage: "arrow.up.right")
                }.buttonStyle(SoftActionStyle(prominent: true)).fixedSize()
            }.padding(24)
                .background(QingYouStyle.banner, in: RoundedRectangle(cornerRadius: QingYouStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: QingYouStyle.radius)
                    .strokeBorder(QingYouStyle.border, lineWidth: 1))
            HStack(spacing: 12) {
                metric("\(store.configuration.menuItems.filter(\.enabled).count)", "菜单功能", "cursorarrow.click", .menu)
                metric("\(store.configuration.templates.filter(\.enabled).count)", "文件模板", "doc.badge.plus", .templates)
                metric("\(ToolCommand.available.count)", "本地工具", "wrench.and.screwdriver", .tools)
            }
            card {
                HStack(spacing: 12) {
                    Circle().fill(store.extensionEnabled ? QingYouStyle.success : Color.secondary)
                        .frame(width: 8, height: 8).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.extensionEnabled ? "已就位，下一次右键就能用" : "连接你的 Finder")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.extensionEnabled ? "在 Finder 中右击，直接选择新建、拷贝路径等操作。" : "启用扩展，把常用工具放进右键菜单。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(store.extensionEnabled ? "管理扩展" : "前往启用") { store.manageExtension() }
                        .buttonStyle(SoftActionStyle()).fixedSize()
                    Button { store.refreshExtensionStatus() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 24, height: 28)
                    }.buttonStyle(.borderless).help("刷新扩展状态").accessibilityLabel("刷新扩展状态")
                }
            }
            HStack {
                Text("顺手开始").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("常用的，就近一点").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Menu {
                    ForEach(store.configuration.templates.filter(\.enabled)) { template in
                        Button(template.menuTitle) {
                            guard let directory = store.chooseDirectory(message: "在哪里创建文件？") else { return }
                            store.perform(.init(action: .createFile, directory: directory.path, argument: template.id))
                        }
                    }
                } label: {
                    QuickEntryLabel(title: "新建文件", detail: "从内置或自定义模板开始", symbol: "doc.badge.plus", menu: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .modifier(Surface()).modifier(HoverSurface())
                .accessibilityLabel("新建文件，选择模板").help("选择新建文件的模板")
                Button { store.selectedPage = .menu } label: {
                    QuickEntryLabel(title: "定制右键", detail: "调整功能、顺序与显示方式", symbol: "slider.horizontal.3")
                }.buttonStyle(.plain).modifier(Surface()).modifier(HoverSurface())
            }
            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("文件留在本机 · 转换保留原件 · 无需账号")
                Spacer(minLength: 8)
                Button("查看最近操作") { store.selectedPage = .history }.buttonStyle(.link)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func metric(_ number: String, _ label: String, _ symbol: String, _ destination: SettingsPage) -> some View {
        Button { store.selectedPage = destination } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(brand)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(number).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Surface()).modifier(HoverSurface())
        }.buttonStyle(.plain).accessibilityLabel("\(label)，\(number) 项")
    }

    private var menuSettings: some View {
        VStack(spacing: 18) {
            card {
                Label("从一套顺手的菜单开始", systemImage: "slider.horizontal.3").font(.headline)
                Text("选择预设会更新功能开关与顺序，之后仍可逐项调整。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(MenuPreset.allCases) { preset in
                        Button(preset.title) { withAnimation(motion) { preset.apply(to: &store.configuration) } }
                    }
                    Spacer()
                    Text("\(store.configuration.menuItems.filter(\.enabled).count) 组已开启").font(.caption).foregroundStyle(.secondary)
                }
            }
            card {
                Toggle("将功能收纳到「轻右」子菜单", isOn: $store.configuration.useSubmenu)
                Text("关闭后，常用操作直接显示；图片与 PDF 功能按分类展开。").font(.caption).foregroundStyle(.secondary)
            }
            card {
                ForEach(Array(store.configuration.menuItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 14) {
                        Image(systemName: item.feature.symbol).font(.system(size: 18)).foregroundStyle(brand).frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.feature.title).font(.system(size: 13, weight: .medium))
                            Text(item.feature.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { withAnimation(motion) { store.moveFeature(index, by: -1) } } label: { Image(systemName: "chevron.up") }
                            .help("上移").disabled(index == 0)
                        Button { withAnimation(motion) { store.moveFeature(index, by: 1) } } label: { Image(systemName: "chevron.down") }
                            .help("下移").disabled(index == store.configuration.menuItems.count - 1)
                        Toggle(item.feature.title, isOn: $store.configuration.menuItems[index].enabled)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.vertical, 5)
                    if index < store.configuration.menuItems.count - 1 { Divider() }
                }
            }
        }
    }
    private var templates: some View {
        VStack(spacing: 18) {
            card {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("WPS 文档，也能右键新建").font(.headline)
                        Text("内置文档可用 WPS 打开。也可导入自己的模板，轻右会保存副本。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("导入模板…") { store.importTemplate() }
                }
            }
            card {
                ForEach(Array(store.configuration.templates.enumerated()), id: \.element.id) { index, template in
                    HStack(spacing: 12) {
                        Text(template.fileExtension.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(brand).frame(width: 46, height: 34)
                            .background(brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        TextField("显示名称", text: $store.configuration.templates[index].name)
                            .textFieldStyle(.plain).frame(maxWidth: 240)
                        Spacer()
                        Text(template.importedFilename == nil ? "内置" : "自定义").font(.caption).foregroundStyle(.secondary)
                        if template.importedFilename != nil {
                            Button { store.configuration.templates.remove(at: index) } label: { Image(systemName: "minus.circle") }.help("移除模板")
                        }
                        Toggle(template.name, isOn: $store.configuration.templates[index].enabled)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.vertical, 5)
                    if index < store.configuration.templates.count - 1 { Divider() }
                }
            }
            card {
                Toggle("新建文件后自动打开", isOn: $store.configuration.openAfterCreation)
                Toggle("新建办公文档优先使用 WPS", isOn: Binding(
                    get: { store.configuration.prefersWPS }, set: { store.configuration.preferWPS = $0 }))
                Text("安装 WPS 时，仅为轻右新建的办公文档设置打开方式。新建后可直接改名；文字模板支持 {{name}} 和 {{date}} 占位符。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var favorites: some View {
        VStack(spacing: 18) {
            HStack { Text("收藏目录").font(.headline); Spacer(); Button("添加目录…") { store.addFavorite() } }
            if store.configuration.favorites.isEmpty {
                empty("还没有收藏目录", "添加后即可在右键菜单中快速打开或发送文件。", "star")
            } else {
                card {
                    ForEach(Array(store.configuration.favorites.enumerated()), id: \.element.id) { index, favorite in
                        HStack(spacing: 14) {
                            Image(systemName: "folder.fill").font(.title2).foregroundStyle(brand)
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("显示名称", text: $store.configuration.favorites[index].name).textFieldStyle(.plain)
                                Text(favorite.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            }
                            Spacer()
                            Button("打开") { store.perform(.init(action: .openFavorite, argument: favorite.id.uuidString)) }
                            Button { store.configuration.favorites.remove(at: index) } label: { Image(systemName: "minus.circle") }.help("移除收藏")
                        }.padding(.vertical, 8)
                        if index < store.configuration.favorites.count - 1 { Divider() }
                    }
                }
            }
        }
    }
    private var applications: some View {
        VStack(spacing: 18) {
            card {
                HStack {
                    Label("系统终端已内置，无需配置", systemImage: "terminal")
                    Spacer()
                    Button("添加应用…") { store.addApplication() }
                }
                Text("编辑器接收选中文件；右击空白位置时接收当前目录。应用是否支持打开目录由它自身决定。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.configuration.applications.isEmpty {
                empty("添加常用编辑器", "支持 VS Code、Typora、PyCharm 等已安装的 Mac 应用。", "arrow.up.forward.app")
            } else {
                card {
                    ForEach(Array(store.configuration.applications.enumerated()), id: \.element.id) { index, app in
                        HStack(spacing: 14) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 5) {
                                TextField("显示名称", text: $store.configuration.applications[index].name).textFieldStyle(.plain)
                                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { store.configuration.applications.remove(at: index) } label: { Image(systemName: "minus.circle") }.help("移除应用")
                        }.padding(.vertical, 6)
                        if index < store.configuration.applications.count - 1 { Divider() }
                    }
                }
            }
        }
    }
    private var tools: some View {
        let profile = SelectionProfile(store.stagedFiles)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: dropTargeted ? "tray.and.arrow.down.fill" : "doc.on.doc")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(brand)
                    .accessibilityHidden(true)
                Text(store.receivingDrop ? "正在接收文件…" : (dropTargeted ? "松开以添加文件" : "把 Finder 里的文件拖到这里"))
                    .font(.headline)
                Text("先选择文件，再运行工具；拖入时不会修改文件。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("选择文件…") {
                    let urls = store.chooseFiles(message: "添加待处理的文件或文件夹")
                    if !urls.isEmpty { store.stageFiles(urls) }
                }.disabled(store.receivingDrop)
            }
            .frame(maxWidth: .infinity).padding(26)
            .background(dropTargeted ? brand.opacity(0.08) : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: QingYouStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: QingYouStyle.radius).strokeBorder(dropTargeted ? brand : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .animation(motion, value: dropTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: store.receiveDrop)
            if !store.stagedFiles.isEmpty {
                card {
                    HStack {
                        Label("已选择 \(store.stagedFiles.count) 个项目", systemImage: "checkmark.circle.fill").font(.headline)
                        Spacer()
                        Button("清空选择") { withAnimation(motion) { store.stagedFiles = [] } }
                    }
                    ForEach(Array(store.stagedFiles.prefix(4)), id: \.path) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            Text(url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { store.stagedFiles.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("移除 \(url.lastPathComponent)")
                        }
                    }
                    if store.stagedFiles.count > 4 {
                        Text("以及另外 \(store.stagedFiles.count - 4) 个项目").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("仅点亮适用于这批文件的工具。运行后可在提示中显示结果。").font(.caption).foregroundStyle(.secondary)
                }.transition(.opacity)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 14) {
                ForEach(ToolCommand.available) { command in
                    ToolTile(command: command, enabled: store.stagedFiles.isEmpty || command.accepts(profile),
                             staged: !store.stagedFiles.isEmpty) { store.execute(command) }
                }
            }

        }
    }
    private func pick(_ action: ActionKind, message: String, folders: Bool = true, types: [UTType]? = nil) {
        let urls = store.chooseFiles(message: message, folders: folders, types: types)
        guard !urls.isEmpty else { return }
        store.perform(.init(action: action, paths: urls.map(\.path), directory: urls[0].deletingLastPathComponent().path))
    }
    private var history: some View {
        let entries = store.activities.filter { historyFilter == 0 || (historyFilter == 1 ? !$0.failed : $0.failed) }
        return VStack(spacing: 18) {
            Picker("筛选操作记录", selection: $historyFilter) {
                Text("全部").tag(0)
                Text("已完成").tag(1)
                Text("需要处理").tag(2)
            }.pickerStyle(.segmented).frame(maxWidth: 330)
            HStack {
                Text("本次启动可撤销最近一批移动或重命名。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("撤销上次操作") { store.undoLastMoveOrRename() }
                    .disabled(store.undoMappings.isEmpty || store.pendingTasks > 0)
            }
            if entries.isEmpty {
                empty("还没有操作记录", "从右键菜单或工具箱开始，结果会显示在这里。", "clock")
            } else {
                card {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: entry.failed ? "exclamationmark.circle" : "checkmark.circle")
                                .foregroundStyle(entry.failed ? Color.orange : brand).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.title).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(entry.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let path = entry.outputPath {
                                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                        .font(.caption)
                                }
                            }
                        }.padding(.vertical, 6)
                        if entry.id != entries.last?.id { Divider() }
                    }
                }
            }
        }
    }
    private var preferences: some View {
        VStack(spacing: 18) {
            card {
                Label("启动", systemImage: "power").font(.headline)
                Toggle("登录时自动启动", isOn: Binding(
                    get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                Text(loginItem.detail).font(.caption).foregroundStyle(.secondary)
                if let error = loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Button("打开系统登录项设置") { loginItem.openSystemSettings() }
                    if loginItem.needsApproval {
                        Spacer()
                        Button("取消自动启动申请") { loginItem.setEnabled(false) }
                    }
                }
            }
            card {
                Text("文件操作").font(.headline)
                Picker("遇到重名文件", selection: $store.configuration.collisionPolicy) {
                    ForEach(CollisionPolicy.allCases) { Text($0.title).tag($0) }
                }.frame(maxWidth: 360)
                Toggle("新建文件后自动打开", isOn: $store.configuration.openAfterCreation)
                Text("轻右不会自动覆盖同名文件。撤销记录保留到退出软件，操作日志保留最近 100 条。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("新建后直接编辑文件名", isOn: Binding(
                    get: { store.configuration.editsNameAfterCreation },
                    set: { store.configuration.renameAfterCreation = $0 }))
                    .disabled(store.configuration.openAfterCreation)
                Text(store.configuration.openAfterCreation
                    ? "已选择直接打开文件，暂不进入名称编辑。"
                    : "授权后尝试在 Finder 中直接编辑名称；无法确认选中文件时，保留选中状态，按回车即可改名。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(store.accessibilityTrusted ? "辅助功能已授权" : "需要辅助功能授权",
                          systemImage: store.accessibilityTrusted ? "checkmark.circle" : "hand.raised")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.accessibilityTrusted ? "管理授权" : "前往授权…") { store.openAccessibilitySettings() }
                }
            }
            card {
                HStack { Text("右键菜单生效目录").font(.headline); Spacer(); Button("添加目录…") { store.addMonitoredDirectory() } }
                Text("包含所选目录的子目录。这里只决定菜单出现的位置，不会扫描文件，也不会自动授予磁盘访问权限。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(store.configuration.monitoredPaths.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(brand)
                        Text(path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { store.configuration.monitoredPaths.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    }
                }
            }
            card {
                Text("交互与外观").font(.headline)
                Toggle("批量处理完成时显示轻量提示", isOn: Binding(
                    get: { store.configuration.showsCompletionFeedback },
                    set: { store.configuration.completionFeedback = $0 }))
                Text("新建文件、复制信息和标记剪切始终静默完成。其他任务的提示可关闭，结果仍在操作记录中。").font(.caption).foregroundStyle(.secondary)
                Divider()
                Label("随系统切换明暗，使用系统蓝强调操作", systemImage: "circle.lefthalf.filled")
                Label("尊重系统的减少动态效果和降低透明度设置", systemImage: "accessibility")
                    .font(.callout).foregroundStyle(.secondary)
            }
            card {
                Text("本地数据").font(.headline)
                Text("设置、模板与操作记录保存在用户的 Application Support/QingYou 目录。没有账号、遥测或云端上传。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("打开数据目录") { NSWorkspace.shared.open(Product.supportDirectory) }
                    Spacer()
                    Button("备份设置并恢复默认") { store.resetConfiguration() }
                }
            }
        }
        .onAppear { loginItem.refresh(); store.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
    private func empty(_ title: String, _ detail: String, _ symbol: String) -> some View {
        card {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary).padding(.top, 25)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).padding(.bottom, 25)
        }
    }
}
