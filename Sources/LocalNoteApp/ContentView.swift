import AppKit
import SwiftUI
#if canImport(LocalNoteCore)
import LocalNoteCore
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings: Bool
    @State private var focusRequest: OutlineFocusRequest?

    init(model: AppModel, initiallyShowingSettings: Bool = false) {
        self.model = model
        _showingSettings = State(initialValue: initiallyShowingSettings)
        _focusRequest = State(initialValue: nil)
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
                    Button("添加第一项", action: addAndFocusItem)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.document.items) { item in
                                outlineRow(item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: focusRequest) { request in
                        guard let request = request else { return }
                        proxy.scrollTo(request.itemID)
                    }
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
                    itemID: item.id,
                    text: model.itemBinding(id: item.id),
                    focusRequest: focusRequest,
                    onCommit: { addPeerAndFocus(after: item.id) },
                    onDeleteEmpty: { deleteAndFocus(item.id) },
                    onMoveVertical: { direction, caretOffset in
                        moveFocus(from: item.id, direction: direction, caretOffset: caretOffset)
                    },
                    onIndent: { model.indent(id: item.id) },
                    onOutdent: { model.outdent(id: item.id) },
                    onToggleStrike: { model.toggleStrike(id: item.id) },
                    onBeginEditing: {
                        focusRequest = nil
                        model.beginEditing(id: item.id)
                    },
                    onEndEditing: { model.endEditing(id: item.id) }
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .opacity(item.isStruck ? 0.55 : 1)
                if item.isStruck {
                    WrappedStrikethrough()
                        .stroke(Color.secondary.opacity(0.7), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("↑↓ 切换事项；Return 新增；⌘⇧S 划线；空行 Backspace 删除")
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

    private func addAndFocusItem() {
        guard let id = model.addItem() else { return }
        requestFocus(itemID: id, caretOffset: 0)
    }

    private func addPeerAndFocus(after id: UUID) {
        guard let insertedID = model.addPeer(after: id) else { return }
        requestFocus(itemID: insertedID, caretOffset: 0)
    }

    private func moveFocus(from id: UUID, direction: Int, caretOffset: Int) {
        guard let index = model.document.items.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard model.document.items.indices.contains(targetIndex) else { return }
        requestFocus(itemID: model.document.items[targetIndex].id, caretOffset: caretOffset)
    }

    private func deleteAndFocus(_ id: UUID) {
        guard let index = model.document.items.firstIndex(where: { $0.id == id }) else { return }
        let items = model.document.items
        let previous = index > 0 ? items[index - 1] : nil
        let rootDepth = items[index].depth
        var nextIndex = index + 1
        while nextIndex < items.count && items[nextIndex].depth > rootDepth {
            nextIndex += 1
        }
        let next = nextIndex < items.count ? items[nextIndex] : nil
        model.delete(id: id)
        if let previous = previous {
            requestFocus(itemID: previous.id, caretOffset: previous.text.utf16.count)
        } else if let next = next {
            requestFocus(itemID: next.id, caretOffset: 0)
        }
    }

    private func requestFocus(itemID: UUID, caretOffset: Int) {
        focusRequest = OutlineFocusRequest(
            token: UUID(),
            itemID: itemID,
            caretOffset: max(0, caretOffset)
        )
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
                    Button(action: addAndFocusItem) {
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

private struct OutlineFocusRequest: Equatable {
    let token: UUID
    let itemID: UUID
    let caretOffset: Int
}

private struct WrappedStrikethrough: Shape {
    private let lineHeight = ceil(NSFont.systemFont(ofSize: NSFont.systemFontSize).boundingRectForFont.height)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lines = max(1, Int(round(rect.height / lineHeight)))
        let topInset = max(0, (rect.height - CGFloat(lines) * lineHeight) / 2)
        for line in 0..<lines {
            let y = topInset + (CGFloat(line) + 0.52) * lineHeight
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct OutlineEditorField: NSViewRepresentable {
    let itemID: UUID
    @Binding var text: String
    let focusRequest: OutlineFocusRequest?
    let onCommit: () -> Void
    let onDeleteEmpty: () -> Void
    let onMoveVertical: (_ direction: Int, _ caretOffset: Int) -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleStrike: () -> Void
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = OutlineTextField()
        field.identifier = NSUserInterfaceItemIdentifier(itemID.uuidString)
        field.placeholderString = "待办事项"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = context.coordinator
        field.onToggleStrike = onToggleStrike
        field.onBeginEditing = onBeginEditing
        field.onEndEditing = onEndEditing
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.identifier = NSUserInterfaceItemIdentifier(itemID.uuidString)
        (field as? OutlineTextField)?.onToggleStrike = onToggleStrike
        (field as? OutlineTextField)?.onBeginEditing = onBeginEditing
        (field as? OutlineTextField)?.onEndEditing = onEndEditing
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
            (field as? OutlineTextField)?.invalidateWrappingHeight()
        }
        (field as? OutlineTextField)?.applyFocusRequest(focusRequest)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OutlineEditorField

        init(_ parent: OutlineEditorField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            guard parent.text != field.stringValue else { return }
            parent.text = field.stringValue
            (field as? OutlineTextField)?.invalidateWrappingHeight()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)) where !textView.hasMarkedText():
                parent.onMoveVertical(-1, textView.selectedRange().location)
                return true
            case #selector(NSResponder.moveDown(_:)) where !textView.hasMarkedText():
                parent.onMoveVertical(1, textView.selectedRange().location)
                return true
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

private final class OutlineTextField: NSTextField {
    var onToggleStrike: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    private var pendingFocusRequest: OutlineFocusRequest?
    private var appliedFocusToken: UUID?
    private var measuredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        guard let cell = cell else { return super.intrinsicContentSize }
        let width = bounds.width > 0 ? bounds.width : super.intrinsicContentSize.width
        guard width > 0 else { return super.intrinsicContentSize }
        let fittingBounds = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let measured = cell.cellSize(forBounds: fittingBounds)
        let oneLineHeight = ceil(font?.boundingRectForFont.height ?? super.intrinsicContentSize.height)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(oneLineHeight, ceil(measured.height))
        )
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - measuredWidth) > 0.5 {
            measuredWidth = bounds.width
            invalidateWrappingHeight()
        }
    }

    func invalidateWrappingHeight() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    func applyFocusRequest(_ request: OutlineFocusRequest?) {
        pendingFocusRequest = request
        guard let request = request,
              request.itemID.uuidString == identifier?.rawValue,
              appliedFocusToken != request.token else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.pendingFocusRequest == request,
                  let window = self.window,
                  window.makeFirstResponder(self) else { return }
            self.appliedFocusToken = request.token
            self.scrollToVisible(self.bounds)
            guard let editor = self.currentEditor() as? NSTextView else { return }
            let location = min(request.caretOffset, editor.string.utf16.count)
            editor.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            OutlineCommandRouter.shared.didBeginEditing(self)
            onBeginEditing?()
        }
        return accepted
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        OutlineCommandRouter.shared.didBeginEditing(self)
        onBeginEditing?()
    }

    override func textDidEndEditing(_ notification: Notification) {
        onEndEditing?()
        OutlineCommandRouter.shared.didEndEditing(self)
        super.textDidEndEditing(notification)
    }

    @objc func toggleLocalNoteStrikethrough(_ sender: Any?) {
        onToggleStrike?()
    }
}
