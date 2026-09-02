import AppKit
import SwiftUI
#if canImport(LocalNoteCore)
import LocalNoteCore
#endif

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var model: AppModel
    @State private var showingSettings: Bool
    @State private var showingCalendar: Bool
    @State private var calendarMonthDateKey: String
    @State private var calendarSummaries: [String: DayActivitySummary]
    @State private var focusRequest: OutlineFocusRequest?
    @State private var activeItemID: UUID?
    @State private var selectionAnchorID: UUID?
    @State private var selectionExtentID: UUID?
    @State private var textSelection: OutlineTextSelection?

    init(
        model: AppModel,
        initiallyShowingSettings: Bool = false,
        initiallyShowingCalendar: Bool = false
    ) {
        self.model = model
        _showingSettings = State(initialValue: initiallyShowingSettings)
        _showingCalendar = State(initialValue: initiallyShowingCalendar)
        _calendarMonthDateKey = State(initialValue: model.dateKey)
        _calendarSummaries = State(initialValue: [:])
        _focusRequest = State(initialValue: nil)
        _activeItemID = State(initialValue: nil)
        _selectionAnchorID = State(initialValue: nil)
        _selectionExtentID = State(initialValue: nil)
        _textSelection = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            themedDivider
            if showingSettings {
                settings
            } else if showingCalendar {
                calendarOverview
            } else {
                outline
            }
            themedDivider
            footer
        }
        .frame(width: 440, height: 560)
        .foregroundColor(resolvedTheme.primaryText)
        .background(resolvedTheme.background)
        .accentColor(resolvedTheme.accent)
        .preferredColorScheme(model.appearance.mode.preferredColorScheme)
        .onAppear {
            if showingCalendar { refreshCalendar() }
        }
        .onChange(of: model.document) { _ in
            if showingCalendar { refreshCalendar() }
        }
        .onChange(of: model.dateKey) { _ in
            activeItemID = nil
            clearSelections()
        }
    }

    private var resolvedTheme: LocalNoteTheme {
        LocalNoteTheme.resolve(
            preferences: model.appearance,
            systemColorScheme: systemColorScheme
        )
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(resolvedTheme.separator)
            .frame(height: 1)
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
            Button(action: toggleCalendar) {
                Image(systemName: showingCalendar && !showingSettings ? "calendar.circle.fill" : "calendar")
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingCalendar && !showingSettings ? "返回清单" : "日历概览")
            .accessibility(label: Text("日历概览"))
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingSettings ? "返回清单" : "设置")
        }
        .foregroundColor(resolvedTheme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var calendarOverview: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { shiftCalendarMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
                Text(calendarMonthTitle)
                    .font(.headline)
                Spacer()
                Button(action: { shiftCalendarMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { entry in
                    Text(entry.element)
                        .font(.caption)
                        .foregroundColor(resolvedTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 6) {
                        ForEach(Array(calendarDays[(week * 7)..<(week * 7 + 7)]), id: \.dateKey) { day in
                            calendarDayButton(day)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text("少")
                ForEach(0..<6, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(activityColor(level: level))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(resolvedTheme.separator.opacity(level == 0 ? 1 : 0), lineWidth: 1)
                        )
                        .frame(width: 14, height: 14)
                }
                Text("多")
                Spacer()
                Text("颜色越深，完成越多")
            }
            .font(.caption2)
            .foregroundColor(resolvedTheme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func calendarDayButton(_ day: CalendarDay) -> some View {
        let summary = calendarSummaries[day.dateKey]
        let level = summary?.intensityLevel ?? 0
        let isSelected = day.dateKey == model.dateKey
        let isToday = day.dateKey == DateKey.make(from: Date())
        return Button(action: { selectCalendarDay(day.dateKey) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(activityColor(level: level))
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected
                            ? resolvedTheme.accent
                            : resolvedTheme.secondaryText.opacity(isToday ? 0.7 : 0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
                Text("\(day.dayNumber)")
                    .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundColor(
                        day.isInDisplayedMonth
                            ? resolvedTheme.activityTextColor(level: level)
                            : resolvedTheme.secondaryText
                    )
                    .opacity(day.isInDisplayedMonth ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(PlainButtonStyle())
        .help(activityHelp(for: day, summary: summary))
        .accessibility(label: Text(activityHelp(for: day, summary: summary)))
    }

    private var calendarDays: [CalendarDay] {
        let days = DateKey.monthGrid(containing: calendarMonthDateKey)
        if days.count == 42 { return days }
        return (0..<42).map {
            CalendarDay(dateKey: "invalid-\($0)", dayNumber: $0 + 1, isInDisplayedMonth: false)
        }
    }

    private var calendarMonthTitle: String {
        let parts = calendarMonthDateKey.split(separator: "-")
        guard parts.count >= 2 else { return calendarMonthDateKey }
        return "\(parts[0])年\(Int(parts[1]) ?? 0)月"
    }

    private func activityColor(level: Int) -> Color {
        resolvedTheme.activityColor(level: level)
    }

    private func activityHelp(for day: CalendarDay, summary: DayActivitySummary?) -> String {
        guard let summary = summary, summary.hasTodos else { return "\(day.dateKey)：无待办" }
        return "\(day.dateKey)：完成 \(summary.completedTodos)/\(summary.totalTodos)"
    }

    private func toggleCalendar() {
        if showingSettings {
            showingSettings = false
            showingCalendar = true
            calendarMonthDateKey = model.dateKey
            refreshCalendar()
            return
        }
        showingCalendar.toggle()
        if showingCalendar {
            calendarMonthDateKey = model.dateKey
            refreshCalendar()
        }
    }

    private func shiftCalendarMonth(by months: Int) {
        guard let shifted = DateKey.adding(months: months, to: calendarMonthDateKey) else { return }
        calendarMonthDateKey = shifted
        refreshCalendar()
    }

    private func selectCalendarDay(_ dateKey: String) {
        model.navigate(to: dateKey)
        showingCalendar = false
    }

    private func refreshCalendar() {
        let keys = DateKey.monthGrid(containing: calendarMonthDateKey).map(\.dateKey)
        calendarSummaries = model.activitySummaries(for: keys)
    }

    private var outline: some View {
        VStack(spacing: 0) {
            if model.document.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checklist")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(resolvedTheme.secondaryText)
                    Text("今天还没有记录")
                        .foregroundColor(resolvedTheme.secondaryText)
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
        let isSelected = selectedItemIDs.contains(item.id)
        let selectedTextRange = textSelection?.range(for: item, in: model.document.items)
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Color.clear.frame(width: CGFloat(item.depth * 18), height: 1)
            if item.kind == .checkbox {
                Button(action: {
                    clearSelections()
                    model.toggleCompletion(id: item.id)
                }) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .foregroundColor(item.checked ? resolvedTheme.accent : resolvedTheme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(model.displayPrefix(for: item))
                    .frame(width: 24, alignment: .trailing)
                    .foregroundColor(resolvedTheme.secondaryText)
            }
            ZStack {
                OutlineEditorField(
                    itemID: item.id,
                    kind: item.kind,
                    isStruck: item.isStruck,
                    textColor: item.isStruck
                        ? resolvedTheme.completedTextNSColor
                        : resolvedTheme.themeID == .systemNative
                            ? NSColor.labelColor
                            : resolvedTheme.primaryTextNSColor,
                    insertionPointColor: resolvedTheme.accentNSColor,
                    text: model.itemBinding(id: item.id),
                    focusRequest: focusRequest,
                    onCommit: { selection in
                        commitAndFocus(itemID: item.id, replacingUTF16Range: selection)
                    },
                    onDeleteEmpty: { deleteAndFocus(item.id) },
                    onExitStructuredItem: { model.exitStructuredItem(id: item.id) },
                    onApplyTypingShortcut: { kind in
                        model.applyTypingShortcut(id: item.id, kind: kind)
                    },
                    onMoveVertical: { direction, caretOffset in
                        moveFocus(from: item.id, direction: direction, caretOffset: caretOffset)
                    },
                    onExtendSelection: { direction in
                        extendSelection(from: item.id, direction: direction)
                    },
                    onUndo: { caretOffset in
                        performHistory(.undo, from: item.id, caretOffset: caretOffset)
                    },
                    onRedo: { caretOffset in
                        performHistory(.redo, from: item.id, caretOffset: caretOffset)
                    },
                    onIndent: { model.indent(id: item.id) },
                    onOutdent: { model.outdent(id: item.id) },
                    onToggleStrike: { toggleStrike(for: item.id) },
                    crossRowSelection: selectedTextRange,
                    onSelectRow: { extending in
                        clearTextSelection()
                        selectRow(item.id, extending: extending)
                    },
                    onClearTextSelection: clearSelections,
                    onDragTextSelection: updateTextSelection,
                    onCopySelection: copySelection,
                    onTextChange: clearSelections,
                    onBeginEditing: {
                        activeItemID = item.id
                        focusRequest = nil
                        model.beginEditing(id: item.id)
                    },
                    onEndEditing: { model.endEditing(id: item.id) }
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .help("顶层待办 Return 后按 Tab 创建 1. 子项；Return 延续编号；Shift-Tab 减少层级；空编号 Backspace 返回下一项待办")
        .contextMenu {
            if textSelection != nil || selectedItemIDs.count > 1 {
                Button("复制所选内容") { _ = copySelection() }
                Divider()
            }
            Button("增加层级") { model.indent(id: item.id) }
            Button("减少层级") { model.outdent(id: item.id) }
            Button(strikeActionTitle(for: item.id)) { toggleStrike(for: item.id) }
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
        clearSelections()
        guard let id = model.addItem() else { return }
        requestFocus(itemID: id, caretOffset: 0)
    }

    private func addPeerAndFocus(after id: UUID) {
        clearSelections()
        guard let insertedID = model.addPeer(after: id) else { return }
        requestFocus(itemID: insertedID, caretOffset: 0)
    }

    private func commitAndFocus(itemID: UUID, replacingUTF16Range selection: NSRange) {
        clearSelections()
        guard let insertedID = model.commitItem(
            id: itemID,
            replacingUTF16Range: selection
        ) else { return }
        requestFocus(itemID: insertedID, caretOffset: 0)
    }

    private func moveFocus(from id: UUID, direction: Int, caretOffset: Int) {
        clearSelections()
        guard let index = model.document.items.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard model.document.items.indices.contains(targetIndex) else { return }
        requestFocus(itemID: model.document.items[targetIndex].id, caretOffset: caretOffset)
    }

    private var selectedItemIDs: Set<UUID> {
        guard let anchorID = selectionAnchorID,
              let extentID = selectionExtentID,
              anchorID != extentID,
              let anchorIndex = model.document.items.firstIndex(where: { $0.id == anchorID }),
              let extentIndex = model.document.items.firstIndex(where: { $0.id == extentID }) else {
            return []
        }
        let lowerBound = min(anchorIndex, extentIndex)
        let upperBound = max(anchorIndex, extentIndex)
        return Set(model.document.items[lowerBound...upperBound].map(\.id))
    }

    private func selectRow(_ id: UUID, extending: Bool) {
        guard extending else {
            clearRowSelection()
            return
        }
        selectionAnchorID = selectionAnchorID ?? activeItemID ?? id
        selectionExtentID = id
    }

    private func extendSelection(from id: UUID, direction: Int) {
        guard let index = model.document.items.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard model.document.items.indices.contains(targetIndex) else { return }
        let target = model.document.items[targetIndex]
        selectionAnchorID = selectionAnchorID ?? id
        selectionExtentID = target.id
        requestFocus(itemID: target.id, caretOffset: direction < 0 ? target.text.utf16.count : 0)
    }

    private func toggleStrike(for id: UUID) {
        let ids = selectedItemIDs
        if ids.count > 1, ids.contains(id) {
            model.toggleStrike(ids: ids)
        } else {
            model.toggleStrike(id: id)
        }
    }

    private func strikeActionTitle(for id: UUID) -> String {
        let ids = selectedItemIDs
        guard ids.count > 1, ids.contains(id) else {
            return model.document.items.first(where: { $0.id == id })?.manualStrikethrough == true
                ? "取消划线" : "划线"
        }
        let selected = model.document.items.filter { ids.contains($0.id) }
        return selected.allSatisfy(\.manualStrikethrough) ? "取消所选划线" : "为所选项划线"
    }

    private func clearRowSelection() {
        selectionAnchorID = nil
        selectionExtentID = nil
    }

    private func updateTextSelection(
        _ anchor: OutlineTextPosition,
        _ extent: OutlineTextPosition
    ) {
        guard anchor.itemID != extent.itemID else {
            textSelection = nil
            return
        }
        clearRowSelection()
        textSelection = OutlineTextSelection(anchor: anchor, extent: extent)
    }

    private func clearTextSelection() {
        textSelection = nil
    }

    private func clearSelections() {
        clearRowSelection()
        clearTextSelection()
    }

    private func copySelection() -> Bool {
        let value: String?
        if let textSelection = textSelection {
            value = textSelection.text(in: model.document.items)
        } else {
            let ids = selectedItemIDs
            value = ids.count > 1
                ? model.document.items.filter { ids.contains($0.id) }.map(\.text).joined(separator: "\n")
                : nil
        }
        guard let value = value else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    private func performHistory(
        _ direction: OutlineHistoryDirection,
        from itemID: UUID,
        caretOffset: Int
    ) -> OutlineHistoryFocus? {
        let previousItems = model.document.items
        let previousIndex = previousItems.firstIndex(where: { $0.id == itemID })
        let changed = direction == .undo ? model.undo() : model.redo()
        guard changed, !model.document.items.isEmpty else {
            if model.document.items.isEmpty { focusRequest = nil }
            return nil
        }

        let previousIDs = Set(previousItems.map(\.id))
        let addedItems = model.document.items.filter { !previousIDs.contains($0.id) }
        let target: OutlineItem?
        if direction == .redo, let added = addedItems.first {
            target = added
        } else if let existing = model.document.items.first(where: { $0.id == itemID }) {
            target = existing
        } else {
            let fallbackIndex = min(max(0, (previousIndex ?? 1) - 1), model.document.items.count - 1)
            target = model.document.items[fallbackIndex]
        }
        guard let target = target else { return nil }
        let resolvedOffset = min(max(0, caretOffset), target.text.utf16.count)
        requestFocus(itemID: target.id, caretOffset: resolvedOffset)
        return OutlineHistoryFocus(itemID: target.id, caretOffset: resolvedOffset, text: target.text)
    }

    private func deleteAndFocus(_ id: UUID) {
        clearSelections()
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
                appearanceSettingsSection
                themedDivider
                notionSettingsSection
                themedDivider
                lightweightSettingsSection
                Spacer()
                Button("退出 Local Note") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var appearanceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观")
                .font(.headline)

            Picker(
                "显示模式",
                selection: Binding(
                    get: { model.appearance.mode },
                    set: model.setAppearanceMode
                )
            ) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .accessibility(label: Text("显示模式"))

            Text("主题")
                .font(.caption)
                .foregroundColor(resolvedTheme.secondaryText)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(ThemeID.allCases) { themeID in
                    Button(action: { model.setTheme(themeID) }) {
                        ThemePreviewTile(
                            themeID: themeID,
                            accentID: model.appearance.accent,
                            isSelected: model.appearance.theme == themeID
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibility(label: Text("\(themeID.title)主题"))
                    .accessibility(value: Text(model.appearance.theme == themeID ? "已选择" : "未选择"))
                    .help("切换到\(themeID.title)主题")
                }
            }

            Text("强调色")
                .font(.caption)
                .foregroundColor(resolvedTheme.secondaryText)

            HStack(spacing: 12) {
                ForEach(AccentID.allCases) { accentID in
                    accentButton(accentID)
                }
                Spacer(minLength: 0)
            }

            Button(action: model.resetAppearance) {
                Text("恢复默认")
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(
                model.appearance == .standard
                    ? resolvedTheme.secondaryText
                    : resolvedTheme.accent
            )
            .disabled(model.appearance == .standard)
            .help("恢复跟随系统、系统原生主题和蓝色强调色")
        }
    }

    private func accentButton(_ accentID: AccentID) -> some View {
        let isSelected = model.appearance.accent == accentID
        let swatchColor = Color(
            LocalNoteTheme.accentColor(accentID, colorScheme: resolvedTheme.colorScheme)
        )
        return Button(action: { model.setAccent(accentID) }) {
            ZStack {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .stroke(resolvedTheme.background, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(swatchColor, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibility(label: Text("\(accentID.title)强调色"))
        .accessibility(value: Text(isSelected ? "已选择" : "未选择"))
        .help("使用\(accentID.title)强调色")
    }

    private var notionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notion 同步")
                .font(.headline)
            Text("填写你的工作记录根页面 ID。Local Note 会在该页面中按日期标题更新当天内容。")
                .font(.caption)
                .foregroundColor(resolvedTheme.secondaryText)
            Text("页面 ID 或 URL")
                .font(.caption)
            TextField("Notion 页面 ID", text: $model.notionPageID)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .background(resolvedTheme.surface)
            Text("Token")
                .font(.caption)
            SecureField("ntn_…", text: $model.notionToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .background(resolvedTheme.surface)
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
                .foregroundColor(resolvedTheme.secondaryText)
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
                    if !showingCalendar {
                        Button(action: addAndFocusItem) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("添加事项")
                    }
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
        case .notConfigured, .idle: return resolvedTheme.secondaryText
        }
    }
}

private struct ThemePreviewTile: View {
    let themeID: ThemeID
    let accentID: AccentID
    let isSelected: Bool

    private var lightTheme: LocalNoteTheme {
        LocalNoteTheme.resolve(
            preferences: AppearancePreferences(mode: .light, theme: themeID, accent: accentID),
            systemColorScheme: .light
        )
    }

    private var darkTheme: LocalNoteTheme {
        LocalNoteTheme.resolve(
            preferences: AppearancePreferences(mode: .dark, theme: themeID, accent: accentID),
            systemColorScheme: .dark
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                HStack(spacing: 0) {
                    miniOutline(theme: lightTheme)
                    miniOutline(theme: darkTheme)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? lightTheme.accent : lightTheme.separator, lineWidth: isSelected ? 2 : 1)
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(lightTheme.accent)
                        .background(Circle().fill(lightTheme.background))
                        .padding(5)
                }
            }
            .frame(height: 104)

            Text(themeID.title)
                .font(.caption)
        }
        .contentShape(Rectangle())
    }

    private func miniOutline(theme: LocalNoteTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                Text("20260819")
                    .font(.system(size: 5, weight: .semibold))
                Image(systemName: "chevron.right")
                Spacer(minLength: 1)
                Image(systemName: "calendar")
                Image(systemName: "gearshape")
            }
            .font(.system(size: 5, weight: .semibold))
            .foregroundColor(theme.primaryText.opacity(0.85))

            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)

            HStack(spacing: 4) {
                Image(systemName: "square")
                    .font(.system(size: 7))
                Capsule().frame(width: 34, height: 3)
            }
            ForEach(0..<2, id: \.self) { index in
                HStack(spacing: 4) {
                    Image(systemName: index == 1 ? "checkmark.square.fill" : "square")
                        .font(.system(size: 7))
                        .foregroundColor(index == 1 ? theme.accent : theme.secondaryText)
                    Capsule()
                        .frame(width: CGFloat(28 + index * 8), height: 3)
                        .foregroundColor(theme.secondaryText.opacity(index == 1 ? 0.65 : 0.9))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(1..<6, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.activityColor(level: level))
                        .frame(width: 8, height: 5)
                }
            }
        }
        .foregroundColor(theme.secondaryText)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.background)
    }
}

private struct OutlineFocusRequest: Equatable {
    let token: UUID
    let itemID: UUID
    let caretOffset: Int
}

struct OutlineTextPosition: Equatable {
    let itemID: UUID
    let utf16Offset: Int
}

struct OutlineTextSelection: Equatable {
    let anchor: OutlineTextPosition
    let extent: OutlineTextPosition

    func range(for item: OutlineItem, in items: [OutlineItem]) -> NSRange? {
        guard anchor.itemID != extent.itemID,
              let anchorIndex = items.firstIndex(where: { $0.id == anchor.itemID }),
              let extentIndex = items.firstIndex(where: { $0.id == extent.itemID }),
              let itemIndex = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let lowerIndex = min(anchorIndex, extentIndex)
        let upperIndex = max(anchorIndex, extentIndex)
        guard (lowerIndex...upperIndex).contains(itemIndex) else { return nil }

        let length = item.text.utf16.count
        let anchorOffset = min(max(0, anchor.utf16Offset), items[anchorIndex].text.utf16.count)
        let extentOffset = min(max(0, extent.utf16Offset), items[extentIndex].text.utf16.count)
        if anchorIndex < extentIndex {
            if itemIndex == anchorIndex {
                return NSRange(location: anchorOffset, length: length - anchorOffset)
            }
            if itemIndex == extentIndex {
                return NSRange(location: 0, length: extentOffset)
            }
        } else {
            if itemIndex == extentIndex {
                return NSRange(location: extentOffset, length: length - extentOffset)
            }
            if itemIndex == anchorIndex {
                return NSRange(location: 0, length: anchorOffset)
            }
        }
        return NSRange(location: 0, length: length)
    }

    func text(in items: [OutlineItem]) -> String? {
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchor.itemID }),
              let extentIndex = items.firstIndex(where: { $0.id == extent.itemID }),
              anchorIndex != extentIndex else { return nil }
        let lowerIndex = min(anchorIndex, extentIndex)
        let upperIndex = max(anchorIndex, extentIndex)
        return items[lowerIndex...upperIndex].map { item in
            guard let range = range(for: item, in: items) else { return "" }
            return (item.text as NSString).substring(with: range)
        }.joined(separator: "\n")
    }
}

private enum OutlineHistoryDirection {
    case undo
    case redo
}

private struct OutlineHistoryFocus {
    let itemID: UUID
    let caretOffset: Int
    let text: String
}

private struct OutlineEditorField: NSViewRepresentable {
    let itemID: UUID
    let kind: OutlineItemKind
    let isStruck: Bool
    let textColor: NSColor
    let insertionPointColor: NSColor
    @Binding var text: String
    let focusRequest: OutlineFocusRequest?
    let onCommit: (NSRange) -> Void
    let onDeleteEmpty: () -> Void
    let onExitStructuredItem: () -> Void
    let onApplyTypingShortcut: (OutlineItemKind) -> Void
    let onMoveVertical: (_ direction: Int, _ caretOffset: Int) -> Void
    let onExtendSelection: (_ direction: Int) -> Void
    let onUndo: (_ caretOffset: Int) -> OutlineHistoryFocus?
    let onRedo: (_ caretOffset: Int) -> OutlineHistoryFocus?
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleStrike: () -> Void
    let crossRowSelection: NSRange?
    let onSelectRow: (_ extending: Bool) -> Void
    let onClearTextSelection: () -> Void
    let onDragTextSelection: (_ anchor: OutlineTextPosition, _ extent: OutlineTextPosition) -> Void
    let onCopySelection: () -> Bool
    let onTextChange: () -> Void
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = OutlineTextField()
        field.identifier = NSUserInterfaceItemIdentifier(itemID.uuidString)
        field.placeholderString = "待办事项"
        field.textColor = textColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.allowsEditingTextAttributes = true
        field.delegate = context.coordinator
        field.onToggleStrike = onToggleStrike
        field.onUndo = onUndo
        field.onRedo = onRedo
        field.onBeginEditing = onBeginEditing
        field.onEndEditing = onEndEditing
        field.onSelectRow = onSelectRow
        field.onClearTextSelection = onClearTextSelection
        field.onDragTextSelection = onDragTextSelection
        field.onCopySelection = onCopySelection
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.identifier = NSUserInterfaceItemIdentifier(itemID.uuidString)
        (field as? OutlineTextField)?.onToggleStrike = onToggleStrike
        (field as? OutlineTextField)?.onUndo = onUndo
        (field as? OutlineTextField)?.onRedo = onRedo
        (field as? OutlineTextField)?.onBeginEditing = onBeginEditing
        (field as? OutlineTextField)?.onEndEditing = onEndEditing
        (field as? OutlineTextField)?.onSelectRow = onSelectRow
        (field as? OutlineTextField)?.onClearTextSelection = onClearTextSelection
        (field as? OutlineTextField)?.onDragTextSelection = onDragTextSelection
        (field as? OutlineTextField)?.onCopySelection = onCopySelection
        (field as? OutlineTextField)?.applyTextAppearance(
            textColor: textColor,
            insertionPointColor: insertionPointColor
        )
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
            (field as? OutlineTextField)?.invalidateWrappingHeight()
        }
        (field as? OutlineTextField)?.applyStrikethrough(isStruck)
        (field as? OutlineTextField)?.applyCrossRowSelection(crossRowSelection)
        (field as? OutlineTextField)?.applyFocusRequest(focusRequest)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OutlineEditorField

        init(_ parent: OutlineEditorField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let editor = field.currentEditor() as? NSTextView
            if let editor = editor, editor.hasMarkedText() {
                return
            }
            if parent.kind == .checkbox,
               let shortcutKind = OutlineTypingShortcut.kind(for: field.stringValue) {
                editor?.string = ""
                editor?.setSelectedRange(NSRange(location: 0, length: 0))
                field.stringValue = ""
                parent.onApplyTypingShortcut(shortcutKind)
                (field as? OutlineTextField)?.invalidateWrappingHeight()
                return
            }
            guard parent.text != field.stringValue else { return }
            parent.onTextChange()
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
            case #selector(NSResponder.moveUpAndModifySelection(_:)) where !textView.hasMarkedText():
                parent.onExtendSelection(-1)
                return true
            case #selector(NSResponder.moveDownAndModifySelection(_:)) where !textView.hasMarkedText():
                parent.onExtendSelection(1)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                if parent.kind == .numbered || parent.kind == .bullet {
                    DispatchQueue.main.async { self.parent.onExitStructuredItem() }
                } else {
                    DispatchQueue.main.async { self.parent.onDeleteEmpty() }
                }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let selection = textView.selectedRange()
                DispatchQueue.main.async { self.parent.onCommit(selection) }
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
    var onUndo: ((Int) -> OutlineHistoryFocus?)?
    var onRedo: ((Int) -> OutlineHistoryFocus?)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onSelectRow: ((Bool) -> Void)?
    var onClearTextSelection: (() -> Void)?
    var onDragTextSelection: ((OutlineTextPosition, OutlineTextPosition) -> Void)?
    var onCopySelection: (() -> Bool)?
    private var pendingFocusRequest: OutlineFocusRequest?
    private var appliedFocusToken: UUID?
    private var measuredWidth: CGFloat = 0
    private var strikethroughEnabled = false
    private var crossRowSelection: NSRange?
    private var crossRowPanRecognizer: NSPanGestureRecognizer?
    private weak var recognizedFieldEditor: NSTextView?
    private var recognizedSelectionAnchor: OutlineTextPosition?

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

    override func mouseDown(with event: NSEvent) {
        onClearTextSelection?()
        onSelectRow?(event.modifierFlags.contains(.shift))
        guard event.clickCount == 1, let window = window else {
            super.mouseDown(with: event)
            return
        }
        if currentEditor() == nil, !window.makeFirstResponder(self) {
            super.mouseDown(with: event)
            return
        }
        guard let editor = currentEditor() as? NSTextView,
              let itemID = identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else {
            super.mouseDown(with: event)
            return
        }

        let anchorOffset = characterOffset(atWindowPoint: event.locationInWindow)
        editor.setSelectedRange(NSRange(location: anchorOffset, length: 0))
        while let trackingEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if trackingEvent.type == .leftMouseUp { break }
            guard let target = Self.closestOutlineField(
                to: trackingEvent.locationInWindow,
                in: window
            ), let targetID = target.identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else {
                continue
            }
            let extentOffset = target.characterOffset(atWindowPoint: trackingEvent.locationInWindow)
            let anchor = OutlineTextPosition(itemID: itemID, utf16Offset: anchorOffset)
            let extent = OutlineTextPosition(itemID: targetID, utf16Offset: extentOffset)
            onDragTextSelection?(anchor, extent)
            if target === self {
                let lowerBound = min(anchorOffset, extentOffset)
                editor.setSelectedRange(
                    NSRange(location: lowerBound, length: abs(extentOffset - anchorOffset))
                )
            } else {
                let ownFrame = convert(bounds, to: nil)
                let targetFrame = target.convert(target.bounds, to: nil)
                let selection = targetFrame.midY < ownFrame.midY
                    ? NSRange(location: anchorOffset, length: editor.string.utf16.count - anchorOffset)
                    : NSRange(location: 0, length: anchorOffset)
                editor.setSelectedRange(selection)
            }
        }
    }

    func invalidateWrappingHeight() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    func applyStrikethrough(_ enabled: Bool) {
        strikethroughEnabled = enabled
        renderTextAppearance()
    }

    func applyCrossRowSelection(_ range: NSRange?) {
        crossRowSelection = range
        renderTextAppearance()
    }

    private func renderTextAppearance() {
        let styleKey = NSAttributedString.Key.strikethroughStyle
        let styleValue = NSUnderlineStyle.single.rawValue
        if let editor = currentEditor() as? NSTextView, let storage = editor.textStorage {
            let foregroundColor = editor.textColor ?? textColor ?? NSColor.labelColor
            editor.textColor = foregroundColor
            let range = NSRange(location: 0, length: storage.length)
            if range.length > 0 {
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.foregroundColor, value: foregroundColor, range: range)
                if strikethroughEnabled {
                    storage.addAttribute(styleKey, value: styleValue, range: range)
                } else {
                    storage.removeAttribute(styleKey, range: range)
                }
            }
            if let layoutManager = editor.layoutManager {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
                if let selectedRange = clampedCrossRowSelection(length: storage.length),
                   selectedRange.length > 0 {
                    layoutManager.addTemporaryAttributes(
                        [
                            .backgroundColor: NSColor.selectedTextBackgroundColor,
                            .foregroundColor: NSColor.selectedTextColor
                        ],
                        forCharacterRange: selectedRange
                    )
                }
            }
            var attributes = editor.typingAttributes
            if strikethroughEnabled {
                attributes[styleKey] = styleValue
            } else {
                attributes.removeValue(forKey: styleKey)
            }
            attributes[.foregroundColor] = foregroundColor
            editor.typingAttributes = attributes
            return
        }

        let foregroundColor = textColor ?? NSColor.labelColor
        let attributed = NSMutableAttributedString(string: stringValue)
        let range = NSRange(location: 0, length: attributed.length)
        if range.length > 0 {
            if let font = font {
                attributed.addAttribute(.font, value: font, range: range)
            }
            attributed.addAttribute(.foregroundColor, value: foregroundColor, range: range)
            if strikethroughEnabled {
                attributed.addAttribute(styleKey, value: styleValue, range: range)
            }
            if let selectedRange = clampedCrossRowSelection(length: attributed.length),
               selectedRange.length > 0 {
                attributed.addAttributes(
                    [
                        .backgroundColor: NSColor.selectedTextBackgroundColor,
                        .foregroundColor: NSColor.selectedTextColor
                    ],
                    range: selectedRange
                )
            }
        }
        attributedStringValue = attributed
    }

    func applyTextAppearance(
        textColor: NSColor,
        insertionPointColor: NSColor
    ) {
        self.textColor = textColor
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.textColor = textColor
        editor.insertionPointColor = insertionPointColor
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: textColor,
                range: NSRange(location: 0, length: storage.length)
            )
        }
        var attributes = editor.typingAttributes
        attributes[.foregroundColor] = textColor
        editor.typingAttributes = attributes
    }

    private func clampedCrossRowSelection(length: Int) -> NSRange? {
        guard let selection = crossRowSelection else { return nil }
        let location = min(max(0, selection.location), length)
        let upperBound = min(max(location, selection.location + selection.length), length)
        return NSRange(location: location, length: upperBound - location)
    }

    private static func closestOutlineField(to point: NSPoint, in window: NSWindow) -> OutlineTextField? {
        guard let contentView = window.contentView else { return nil }
        let fields = outlineFields(in: contentView)
        return fields.min { first, second in
            verticalDistance(from: point, to: first)
                < verticalDistance(from: point, to: second)
        }
    }

    private func installCrossRowPanRecognizer() {
        guard let editor = currentEditor() as? NSTextView else { return }
        if recognizedFieldEditor === editor, crossRowPanRecognizer != nil { return }
        removeCrossRowPanRecognizer()
        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handleCrossRowPan(_:)))
        recognizer.buttonMask = 0x1
        recognizer.delaysPrimaryMouseButtonEvents = false
        editor.addGestureRecognizer(recognizer)
        recognizedFieldEditor = editor
        crossRowPanRecognizer = recognizer
    }

    private func removeCrossRowPanRecognizer() {
        if let recognizer = crossRowPanRecognizer {
            recognizedFieldEditor?.removeGestureRecognizer(recognizer)
        }
        recognizedFieldEditor = nil
        crossRowPanRecognizer = nil
        recognizedSelectionAnchor = nil
    }

    @objc private func handleCrossRowPan(_ recognizer: NSPanGestureRecognizer) {
        guard let editor = recognizedFieldEditor,
              let window = window,
              let itemID = identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else { return }
        let windowPoint = editor.convert(recognizer.location(in: editor), to: nil)
        switch recognizer.state {
        case .began:
            onClearTextSelection?()
            let translation = recognizer.translation(in: editor)
            let anchorPoint = editor.convert(
                NSPoint(
                    x: recognizer.location(in: editor).x - translation.x,
                    y: recognizer.location(in: editor).y - translation.y
                ),
                to: nil
            )
            recognizedSelectionAnchor = OutlineTextPosition(
                itemID: itemID,
                utf16Offset: characterOffset(atWindowPoint: anchorPoint)
            )
        case .changed, .ended:
            guard let anchor = recognizedSelectionAnchor,
                  let target = Self.closestOutlineField(to: windowPoint, in: window),
                  let targetID = target.identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else { return }
            let extentOffset = target.characterOffset(atWindowPoint: windowPoint)
            onDragTextSelection?(
                anchor,
                OutlineTextPosition(itemID: targetID, utf16Offset: extentOffset)
            )
            if target === self {
                let lowerBound = min(anchor.utf16Offset, extentOffset)
                editor.setSelectedRange(
                    NSRange(location: lowerBound, length: abs(extentOffset - anchor.utf16Offset))
                )
            }
            if recognizer.state == .ended { recognizedSelectionAnchor = nil }
        case .cancelled, .failed:
            recognizedSelectionAnchor = nil
        default:
            break
        }
    }

    private static func outlineFields(in view: NSView) -> [OutlineTextField] {
        let current = (view as? OutlineTextField).map { [$0] } ?? []
        return current + view.subviews.flatMap(outlineFields)
    }

    private static func verticalDistance(from point: NSPoint, to field: OutlineTextField) -> CGFloat {
        let frame = field.convert(field.bounds, to: nil)
        if point.y < frame.minY { return frame.minY - point.y }
        if point.y > frame.maxY { return point.y - frame.maxY }
        return 0
    }

    private func characterOffset(atWindowPoint windowPoint: NSPoint) -> Int {
        let length = stringValue.utf16.count
        guard length > 0 else { return 0 }
        if let editor = currentEditor() as? NSTextView {
            let editorPoint = editor.convert(windowPoint, from: nil)
            return min(length, editor.characterIndexForInsertion(at: editorPoint))
        }
        let localPoint = convert(windowPoint, from: nil)
        let drawingRect = cell?.drawingRect(forBounds: bounds) ?? bounds
        let attributed = NSMutableAttributedString(attributedString: attributedStringValue)
        if attributed.length != length {
            attributed.setAttributedString(NSAttributedString(string: stringValue))
        }
        if attributed.length > 0, attributed.attribute(.font, at: 0, effectiveRange: nil) == nil {
            attributed.addAttribute(
                .font,
                value: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                range: NSRange(location: 0, length: attributed.length)
            )
        }

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(
                width: max(1, drawingRect.width),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let y = isFlipped
            ? localPoint.y - drawingRect.minY
            : drawingRect.maxY - localPoint.y
        let textPoint = NSPoint(x: localPoint.x - drawingRect.minX, y: max(0, y))
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: textPoint,
            in: container,
            fractionOfDistanceThroughGlyph: &fraction
        )
        var lineGlyphRange = NSRange()
        let usedLineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: min(glyphIndex, max(0, layoutManager.numberOfGlyphs - 1)),
            effectiveRange: &lineGlyphRange
        )
        if textPoint.x <= usedLineRect.minX {
            return min(length, layoutManager.characterIndexForGlyph(at: lineGlyphRange.location))
        }
        if textPoint.x >= usedLineRect.maxX {
            let lastGlyph = min(layoutManager.numberOfGlyphs, NSMaxRange(lineGlyphRange))
            guard lastGlyph > 0 else { return 0 }
            let lastCharacter = layoutManager.characterIndexForGlyph(at: lastGlyph - 1)
            let glyphCharacterRange = layoutManager.characterRange(
                forGlyphRange: NSRange(location: lastGlyph - 1, length: 1),
                actualGlyphRange: nil
            )
            return min(length, max(lastCharacter + 1, NSMaxRange(glyphCharacterRange)))
        }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return min(length, characterIndex + (fraction >= 0.5 ? 1 : 0))
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
            applyStrikethrough(strikethroughEnabled)
            installCrossRowPanRecognizer()
        }
        return accepted
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        OutlineCommandRouter.shared.didBeginEditing(self)
        onBeginEditing?()
        applyStrikethrough(strikethroughEnabled)
        installCrossRowPanRecognizer()
    }

    override func textDidEndEditing(_ notification: Notification) {
        removeCrossRowPanRecognizer()
        onEndEditing?()
        OutlineCommandRouter.shared.didEndEditing(self)
        super.textDidEndEditing(notification)
        applyStrikethrough(strikethroughEnabled)
    }

    @objc func toggleLocalNoteStrikethrough(_ sender: Any?) {
        onToggleStrike?()
    }

    @objc func copyLocalNote(_ sender: Any?) {
        if onCopySelection?() == true { return }
        (currentEditor() as? NSTextView)?.copy(sender)
    }

    @objc func undoLocalNote(_ sender: Any?) {
        performHistoryAction(onUndo)
    }

    @objc func redoLocalNote(_ sender: Any?) {
        performHistoryAction(onRedo)
    }

    private func performHistoryAction(_ action: ((Int) -> OutlineHistoryFocus?)?) {
        guard let action = action else { return }
        let editor = currentEditor() as? NSTextView
        let caretOffset = editor?.selectedRange().location ?? stringValue.utf16.count
        guard let focus = action(caretOffset) else { return }
        guard focus.itemID.uuidString == identifier?.rawValue else { return }
        stringValue = focus.text
        editor?.string = focus.text
        editor?.setSelectedRange(NSRange(location: focus.caretOffset, length: 0))
        invalidateWrappingHeight()
    }
}
