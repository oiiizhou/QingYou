import SwiftUI
import AppKit

struct UtilityListItem {
    let id: String
    let title: String
    var subtitle = ""
    var image: NSImage?
    var rotation = 0
}

/// 原生列表统一负责选中、插入线、内部拖放和按钮语义，避免手势互相抢占。
struct UtilityOrderList: NSViewRepresentable {
    let items: [UtilityListItem]
    @Binding var selection: String?
    var busy = false
    var compact = false
    var move: ((String, Int) -> Void)?
    var rotate: ((String) -> Void)?
    var remove: ((String) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let table = NSTableView(); table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil; table.style = .inset; table.rowHeight = compact ? 42 : 72
        table.backgroundColor = .controlBackgroundColor; table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false; table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.registerForDraggedTypes([Coordinator.dragType]); table.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = table; context.coordinator.table = table
        context.coordinator.refresh(self)
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.refresh(self) }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        static let dragType = NSPasteboard.PasteboardType("io.github.qingyou.utility-row")
        var parent: UtilityOrderList
        weak var table: NSTableView?
        private var refreshing = false
        private var signature = ""
        init(_ parent: UtilityOrderList) { self.parent = parent }
        func refresh(_ parent: UtilityOrderList) {
            self.parent = parent
            guard let table else { return }
            refreshing = true; defer { refreshing = false }
            let next = parent.items.map { "\($0.id)|\($0.title)|\($0.subtitle)|\($0.rotation)" }.joined(separator: "\n") + String(parent.busy)
            if next != signature { signature = next; table.reloadData() }
            if let selection = parent.selection, let index = parent.items.firstIndex(where: { $0.id == selection }), table.selectedRow != index {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("utility-cell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? UtilityOrderCell ?? UtilityOrderCell()
            cell.identifier = id
            let item = parent.items[row]
            cell.configure(item, index: row, count: parent.items.count, busy: parent.busy,
                           reorderable: parent.move != nil, rotatable: parent.rotate != nil, removable: parent.remove != nil)
            cell.up = { [weak self] in self?.move(item.id, to: row - 1) }
            cell.down = { [weak self] in self?.move(item.id, to: row + 2) }
            cell.turn = { [weak self] in self?.parent.rotate?(item.id) }
            cell.delete = { [weak self] in self?.parent.remove?(item.id) }
            return cell
        }
        private func move(_ id: String, to insertion: Int) { guard !parent.busy else { return }; parent.move?(id, insertion) }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !refreshing, let table, parent.items.indices.contains(table.selectedRow) else { return }
            parent.selection = parent.items[table.selectedRow].id
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard !parent.busy, parent.move != nil, parent.items.indices.contains(row) else { return nil }
            let item = NSPasteboardItem(); item.setString(parent.items[row].id, forType: Self.dragType); return item
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard !parent.busy, parent.move != nil, info.draggingSource as? NSTableView === tableView else { return [] }
            tableView.setDropRow(row, dropOperation: .above); return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard !parent.busy, parent.move != nil, info.draggingSource as? NSTableView === tableView,
                  let id = info.draggingPasteboard.string(forType: Self.dragType), parent.items.contains(where: { $0.id == id }),
                  (0...parent.items.count).contains(row) else { return false }
            parent.selection = id; parent.move?(id, row); return true
        }
    }
}

private final class UtilityOrderCell: NSTableCellView {
    private let thumbnail = UtilityListThumbnail()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let upButton = NSButton()
    private let downButton = NSButton()
    private let rotateButton = NSButton()
    private let removeButton = NSButton()
    var up: (() -> Void)?, down: (() -> Void)?, turn: (() -> Void)?, delete: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 12, weight: .medium); title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: 10); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingMiddle
        title.isSelectable = false; subtitle.isSelectable = false
        for field in [title, subtitle] { field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        let labels = NSStackView(views: [title, subtitle]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 4
        let actions = NSStackView(views: [upButton, downButton, rotateButton, removeButton]); actions.spacing = 5
        for (button, symbol, action) in [(upButton, "chevron.up", #selector(goUp)), (downButton, "chevron.down", #selector(goDown)), (rotateButton, "rotate.right", #selector(turnPage)), (removeButton, "minus.circle", #selector(removeItem))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.isBordered = false; button.target = self; button.action = action
            button.widthAnchor.constraint(equalToConstant: 19).isActive = true
        }
        let stack = NSStackView(views: [thumbnail, labels, actions]); stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        thumbnail.widthAnchor.constraint(equalToConstant: 36).isActive = true
        thumbnail.heightAnchor.constraint(equalToConstant: 52).isActive = true
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        textField = title
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var node: NSView? = hit
        while let view = node, view !== self {
            if view is NSButton { return hit }
            node = view.superview
        }
        // 文字和缩略图交给列表选中、拖放；行内按钮仍保留自己的点击行为。
        return self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ item: UtilityListItem, index: Int, count: Int, busy: Bool, reorderable: Bool, rotatable: Bool, removable: Bool) {
        title.stringValue = item.title; subtitle.stringValue = item.subtitle; subtitle.isHidden = item.subtitle.isEmpty
        thumbnail.image = item.image; thumbnail.rotation = item.rotation; thumbnail.needsDisplay = true
        upButton.isHidden = !reorderable; downButton.isHidden = !reorderable; rotateButton.isHidden = !rotatable; removeButton.isHidden = !removable
        upButton.isEnabled = !busy && index > 0; downButton.isEnabled = !busy && index + 1 < count
        rotateButton.isEnabled = !busy; removeButton.isEnabled = !busy && count > 1
        for (button, prefix) in [(upButton, "上移"), (downButton, "下移"), (rotateButton, "旋转"), (removeButton, "移除")] {
            button.setAccessibilityLabel(prefix + item.title); button.toolTip = prefix + item.title
        }
        setAccessibilityLabel(item.title + (item.subtitle.isEmpty ? "" : "，" + item.subtitle))
    }
    @objc private func goUp() { up?() }
    @objc private func goDown() { down?() }
    @objc private func turnPage() { turn?() }
    @objc private func removeItem() { delete?() }
}

private final class UtilityListThumbnail: NSView {
    var image: NSImage?
    var rotation = 0
    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: bounds.midX, y: bounds.midY); context.rotate(by: -CGFloat(rotation) * .pi / 180)
        let rotated = abs(rotation) % 180 == 90
        let available = CGSize(width: rotated ? bounds.height : bounds.width, height: rotated ? bounds.width : bounds.height)
        let factor = min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    }
}
