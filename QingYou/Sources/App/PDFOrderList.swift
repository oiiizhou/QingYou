import AppKit
import SwiftUI

/// 使用 Finder 同类的列表拖放：插入线明确表示松手后的顺序。
struct PDFOrderList: NSViewRepresentable {
    @ObservedObject var model: PDFWorkspaceModel

    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 76
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("document")))
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.registerForDraggedTypes([Coordinator.orderType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.refresh(model)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let orderType = NSPasteboard.PasteboardType("io.github.qingyou.pdf-order")
        weak var table: NSTableView?
        private var model: PDFWorkspaceModel
        private var ids: [UUID] = []
        private var refreshing = false

        init(_ model: PDFWorkspaceModel) { self.model = model }
        func refresh(_ model: PDFWorkspaceModel) {
            self.model = model
            guard let table else { return }
            refreshing = true
            defer { refreshing = false }
            let next = model.files.map(\.id)
            // 原生行移动动画保留选中状态，减少动态效果开启时直接刷新。
            if ids.count == next.count, Set(ids) == Set(next), ids != next,
               !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                table.beginUpdates()
                for target in next.indices where ids[target] != next[target] {
                    if let from = ids.firstIndex(of: next[target]) {
                        table.moveRow(at: from, to: target)
                        ids.insert(ids.remove(at: from), at: target)
                    }
                }
                table.endUpdates()
            }
            ids = next
            table.reloadData()
            if let selected = model.selectedInput, let row = next.firstIndex(of: selected) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { model.files.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PDFOrderRow() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard model.files.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("pdf-card")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? PDFOrderCell ?? PDFOrderCell()
            cell.identifier = identifier
            let item = model.files[row]
            cell.configure(item, position: row, count: model.files.count, busy: model.isExporting)
            cell.onUp = { [weak model] in model?.move(item.id, by: -1) }
            cell.onDown = { [weak model] in model?.move(item.id, by: 1) }
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !refreshing, let table, model.files.indices.contains(table.selectedRow), !model.isExporting else { return }
            model.selectedInput = model.files[table.selectedRow].id
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard !model.isExporting, model.files.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(model.files[row].id.uuidString, forType: Self.orderType)
            return item
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard !model.isExporting, info.draggingSource as? NSTableView === tableView,
                  info.draggingPasteboard.string(forType: Self.orderType) != nil else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard !model.isExporting, info.draggingSource as? NSTableView === tableView,
                  let value = info.draggingPasteboard.string(forType: Self.orderType),
                  let id = UUID(uuidString: value), model.files.contains(where: { $0.id == id }) else { return false }
            model.selectedInput = id
            model.move(id, to: row)
            return true
        }
    }
}

private final class PDFOrderRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) { drawCard(selected: false) }
    override func drawSelection(in dirtyRect: NSRect) { drawCard(selected: true) }
    private func drawCard(selected: Bool) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        let tint = NSColor(QingYouStyle.accent)
        (selected ? tint.withAlphaComponent(0.10) : NSColor.windowBackgroundColor).setFill()
        path.fill()
        (selected ? tint.withAlphaComponent(0.30) : NSColor.separatorColor.withAlphaComponent(0.3)).setStroke()
        path.lineWidth = 1; path.stroke()
    }
}

private final class PDFOrderCell: NSTableCellView {
    private let thumbnail = NSImageView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let up = NSButton()
    private let down = NSButton()
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let handle = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动排序")!)
        handle.contentTintColor = .tertiaryLabelColor
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        // 文件名用于选中文档和拖放，不让标签截走鼠标事件来选择文字。
        title.isSelectable = false; detail.isSelectable = false
        title.textColor = .labelColor
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 5
        up.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "向上移动")
        down.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "向下移动")
        for button in [up, down] {
            button.isBordered = false; button.bezelStyle = .inline
            button.contentTintColor = NSColor(QingYouStyle.accent)
            button.target = self
        }
        up.action = #selector(nudgeUp); down.action = #selector(nudgeDown)
        let arrows = NSStackView(views: [up, down]); arrows.orientation = .vertical; arrows.spacing = 5
        for view in [handle, thumbnail, labels, arrows] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), handle.widthAnchor.constraint(equalToConstant: 12),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 10), thumbnail.widthAnchor.constraint(equalToConstant: 34),
            thumbnail.heightAnchor.constraint(equalToConstant: 46), thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 10), labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(equalTo: arrows.leadingAnchor, constant: -8),
            arrows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), arrows.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrows.widthAnchor.constraint(equalToConstant: 16)
        ])
        textField = title
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var node: NSView? = hit
        while let view = node, view !== self {
            if view is NSButton { return hit }
            node = view.superview
        }
        return self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ item: PDFInput, position: Int, count: Int, busy: Bool) {
        thumbnail.image = item.thumbnail
        title.stringValue = item.url.lastPathComponent
        detail.stringValue = "\(position + 1) · \(item.pages) 页"
        up.isEnabled = !busy && position > 0; down.isEnabled = !busy && position < count - 1
        up.toolTip = "上移 \(item.url.lastPathComponent)"; down.toolTip = "下移 \(item.url.lastPathComponent)"
        up.setAccessibilityLabel(up.toolTip); down.setAccessibilityLabel(down.toolTip)
    }
    @objc private func nudgeUp() { onUp?() }
    @objc private func nudgeDown() { onDown?() }
}
