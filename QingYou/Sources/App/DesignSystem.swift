import SwiftUI
import AppKit

/// 操作强调色、状态和表面分别管理，避免按工具类别堆颜色。
enum QingYouStyle {
    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApp.applicationIconImage
    }
    static let accent = Color(hex: 0x007AFF)
    static let success = Color(hex: 0x34C759)
    static let canvas = adaptive(0xF6F6F8, dark: 0x202022)
    static let surface = adaptive(0xFFFFFF, dark: 0x29292C)
    static let banner = adaptive(0xF5F5F7, dark: 0x303033)
    static let input = adaptive(0xF2F2F7, dark: 0x353538)
    static let sidebar = adaptive(0xEBEBEC, dark: 0x252527)
    static let border = adaptive(0xD2D2D7, dark: 0x55555B).opacity(0.6)
    static let hover = Color.primary.opacity(0.045)
    static let selection = accent.opacity(0.11)
    static let radius: CGFloat = 12
    static let sidebarWidth: CGFloat = 220

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct WorkspaceBackground: View {
    var body: some View { QingYouStyle.canvas }
}

/// 统一卡片边界，不叠加阴影、模糊光晕或浮起位移。
struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(QingYouStyle.surface, in: RoundedRectangle(cornerRadius: QingYouStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: QingYouStyle.radius)
                .strokeBorder(QingYouStyle.border, lineWidth: 1))
    }
}

struct HoverSurface: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: QingYouStyle.radius)
                .strokeBorder(hovering && enabled ? Color.primary.opacity(0.22) : .clear, lineWidth: 1)
                .allowsHitTesting(false))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

struct SoftActionStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        ActionBody(configuration: configuration, prominent: prominent)
    }
    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).frame(minHeight: 30)
                .foregroundStyle(enabled ? (prominent ? Color.white : Color.primary) : Color.secondary)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(prominent && enabled ? .clear : QingYouStyle.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
        }
        private var fill: Color {
            guard enabled else { return QingYouStyle.input }
            if prominent { return QingYouStyle.accent.opacity(configuration.isPressed ? 0.75 : (hovering ? 0.88 : 1)) }
            return configuration.isPressed ? Color.primary.opacity(0.09) : (hovering ? QingYouStyle.hover : QingYouStyle.surface)
        }
    }
}

struct SidebarNavigationItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 20)
                    .foregroundStyle(selected ? QingYouStyle.accent : Color.secondary)
                Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .foregroundStyle(.primary)
            .background(selected ? QingYouStyle.selection : (hovering ? QingYouStyle.hover : .clear),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SidebarBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            QingYouStyle.sidebar
            if !reduceTransparency { SidebarMaterial().opacity(0.75) }
        }
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct QuickEntryLabel: View {
    let title: String
    let detail: String
    let symbol: String
    var menu = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(QingYouStyle.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: menu ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: QingYouStyle.radius))
    }
}
