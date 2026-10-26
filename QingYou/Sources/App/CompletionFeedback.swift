import AppKit
import SwiftUI

/// 普通完成提示使用不激活应用的面板，文件操作后焦点仍留在 Finder。
final class CompletionFeedback {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func show(_ entry: ActivityEntry, undo: (() -> Void)?) {
        dismiss()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 126),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: CompletionCard(entry: entry, undo: undo,
            dismiss: { [weak self] in self?.dismiss() },
            hover: { [weak self] hovering in
                if hovering { self?.dismissal?.cancel() } else { self?.scheduleDismissal() }
            }))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 390, y: frame.minY + 20))
        }
        self.panel = panel
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        scheduleDismissal()
    }
    private func scheduleDismissal() {
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
    }
    func dismiss() {
        dismissal?.cancel()
        panel?.close()
        panel = nil
    }
}

private struct CompletionCard: View {
    let entry: ActivityEntry
    let undo: (() -> Void)?
    let dismiss: () -> Void
    let hover: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                .padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.headline)
                Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 14) {
                    if let path = entry.outputPath {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            dismiss()
                        }
                    }
                    if let undo {
                        Button("撤销") { dismiss(); undo() }
                    }
                }.buttonStyle(.borderless).font(.caption).padding(.top, 2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.caption) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("关闭提示")
        }
        .padding(18).frame(width: 370, height: 126, alignment: .topLeading)
        .background {
            if reduceTransparency { Color(NSColor.windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))
        .onHover(perform: hover)
    }
}
