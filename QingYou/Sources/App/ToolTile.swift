import SwiftUI

struct ToolTile: View {
    let command: ToolCommand
    let enabled: Bool
    let staged: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: command.symbol).font(.system(size: 17, weight: .regular))
                    .foregroundStyle(enabled ? QingYouStyle.accent : Color.secondary)
                    .frame(width: 22)
                Text(command.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if staged && enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QingYouStyle.success).font(.system(size: 12))
                        .accessibilityLabel("适用于已选文件")
                }
            }
            Text(command.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(staged ? "运行工具" : "选择文件…", action: action)
                    .buttonStyle(SoftActionStyle())
                    .disabled(!enabled)
                    .help(enabled ? command.title : "当前选择的文件类型不适用")
                    .accessibilityLabel(command.title + (staged ? "，运行工具" : "，选择文件"))
                Spacer()
                if staged && !enabled {
                    Text("文件类型不适用").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(Surface()).modifier(HoverSurface(enabled: enabled))
    }
}
