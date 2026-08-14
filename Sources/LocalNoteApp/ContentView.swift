import AppKit
import SwiftUI
#if canImport(LocalNoteCore)
import LocalNoteCore
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings: Bool

    init(model: AppModel, initiallyShowingSettings: Bool = false) {
        self.model = model
        _showingSettings = State(initialValue: initiallyShowingSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingSettings {
                settings
            } else {
                outline
            }
            Divider()
            footer
        }
        .frame(width: 440, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { model.navigate(days: -1) }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: model.navigateToToday) {
                Text(model.dateKey.replacingOccurrences(of: "-", with: ""))
                    .font(.headline)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { model.navigate(days: 1) }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(PlainButtonStyle())
            Spacer()
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingSettings ? "返回清单" : "设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var outline: some View {
        VStack(spacing: 0) {
            if model.document.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checklist")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary)
                    Text("今天还没有记录")
                        .foregroundColor(.secondary)
                    Button("添加第一项", action: model.addItem)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.document.items) { item in
                            outlineRow(item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Color.clear.frame(width: CGFloat(item.depth * 18), height: 1)
            if item.kind == .checkbox {
                Button(action: { model.toggleCompletion(id: item.id) }) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .foregroundColor(item.checked ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(model.displayPrefix(for: item))
                    .frame(width: 24, alignment: .trailing)
                    .foregroundColor(.secondary)
            }
            ZStack {
                OutlineEditorField(
                    text: model.itemBinding(id: item.id),
                    onCommit: { model.addPeer(after: item.id) },
                    onDeleteEmpty: { model.delete(id: item.id) },
                    onIndent: { model.indent(id: item.id) },
                    onOutdent: { model.outdent(id: item.id) }
                )
                .frame(maxWidth: .infinity)
                .opacity(item.isStruck ? 0.55 : 1)
                if item.isStruck {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(height: 1)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("空白事项按 Backspace 删除；右键打开更多操作")
        .contextMenu {
            Button("增加层级") { model.indent(id: item.id) }
            Button("减少层级") { model.outdent(id: item.id) }
            Button(item.manualStrikethrough ? "取消划线" : "划线") { model.toggleStrike(id: item.id) }
            Menu("行类型") {
                Button("复选框") { model.changeKind(id: item.id, kind: .checkbox) }
                Button("编号") { model.changeKind(id: item.id, kind: .numbered) }
                Button("项目符号") { model.changeKind(id: item.id, kind: .bullet) }
                Button("正文") { model.changeKind(id: item.id, kind: .text) }
            }
            Divider()
            Button("删除") { model.delete(id: item.id) }
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notionSettingsSection
                Divider()
                lightweightSettingsSection
                Spacer()
                Button("退出 Local Note") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
            }
            .padding(16)
        }
    }

    private var notionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notion 同步")
                .font(.headline)
            Text("填写你的工作记录根页面 ID。Local Note 会在该页面中按日期标题更新当天内容。")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("页面 ID 或 URL")
                .font(.caption)
            TextField("Notion 页面 ID", text: $model.notionPageID)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Token")
                .font(.caption)
            SecureField("ntn_…", text: $model.notionToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Button("保存设置") { model.saveSettings() }
                Button("保存并同步") {
                    if model.saveSettings() { model.syncNow() }
                }
            }
        }
    }

    private var lightweightSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("轻量模式")
                .font(.headline)
            Label("只加载当前日期", systemImage: "memorychip")
            Label("无定时轮询", systemImage: "timer")
            Label("Token 仅存入 Keychain", systemImage: "lock")
        }
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(model.syncState.label)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
            Spacer()
            if !showingSettings {
                if model.syncState == .conflict {
                    Button("以 Notion 为准") {
                        model.resolveConflictUsingNotion()
                    }
                    .help("放弃本地当天改动，重新拉取 Notion")
                    Button("以本地为准") {
                        model.resolveConflictUsingLocal()
                    }
                    .help("用本地当天内容覆盖 Notion")
                } else {
                    Button(action: model.addItem) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("添加事项")
                    Button(action: { model.syncNow() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.syncState == .syncing)
                    .help("立即同步")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch model.syncState {
        case .synced: return .green
        case .syncing, .saving: return .orange
        case .conflict, .error: return .red
        case .notConfigured, .idle: return .secondary
        }
    }
}

private struct OutlineEditorField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onDeleteEmpty: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "待办事项"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OutlineEditorField

        init(_ parent: OutlineEditorField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  parent.text != field.stringValue else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                DispatchQueue.main.async { self.parent.onDeleteEmpty() }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                DispatchQueue.main.async { self.parent.onCommit() }
                return true
            case #selector(NSResponder.insertTab(_:)):
                DispatchQueue.main.async { self.parent.onIndent() }
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                DispatchQueue.main.async { self.parent.onOutdent() }
                return true
            default:
                return false
            }
        }
    }
}
