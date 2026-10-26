import SwiftUI
import AppKit
import PDFKit

struct UtilityHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var preparing = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(QingYouStyle.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 21, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if preparing { ProgressView().controlSize(.small).accessibilityLabel("正在更新预览") }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
}

struct UtilityFooter: View {
    @ObservedObject var work: LocalWorkState
    let directory: URL
    var message: String?
    var canExport: Bool
    var exportTitle: String
    let export: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = work.message ?? message {
                Label(text, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if work.isWorking {
                HStack(spacing: 12) {
                    ProgressView(value: work.progress).frame(maxWidth: 220)
                    Text(work.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if !work.status.isEmpty {
                Text(work.status).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("保存副本 · 原文件保留", systemImage: "folder").font(.system(size: 12, weight: .medium))
                    Text(directory.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(directory.path)
                }
                Spacer(minLength: 16)
                Button(work.isWorking ? "取消处理" : "取消") { if work.isWorking { work.cancel() } else { close() } }
                    .keyboardShortcut(.cancelAction).disabled(work.isCancelling)
                Button(work.isWorking ? "处理中…" : exportTitle, action: export)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canExport || work.isWorking)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16).background(QingYouStyle.surface)
    }
}

struct UtilityPDFPane: View {
    let title: String
    let subtitle: String
    let document: PDFDocument?
    var selectedPage: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                if let document { NativePDFPreview(document: document, selectedPage: selectedPage, wholePage: true) }
                else { Text("读取文件并设置参数后显示预览").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }.background(QingYouStyle.surface)
            .overlay(Rectangle().strokeBorder(QingYouStyle.border, lineWidth: 1))
    }
}

struct UtilityImagePane: View {
    let title: String
    let subtitle: String
    let image: NSImage?
    var emptyText = "设置参数后显示预览"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }.padding(12)
            Divider()
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(18) }
                else { Text(emptyText).font(.system(size: 12)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(QingYouStyle.surface).overlay(Rectangle().strokeBorder(QingYouStyle.border, lineWidth: 1))
    }
}
