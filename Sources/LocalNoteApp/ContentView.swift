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
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Color.clear.frame(width: CGFloat(item.depth * 18), height: 1)
            if item.kind == .checkbox {
                Button(action: { model.toggleCompletion(id: item.id) }) {
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
                    onUndo: { caretOffset in
                        performHistory(.undo, from: item.id, caretOffset: caretOffset)
                    },
                    onRedo: { caretOffset in
                        performHistory(.redo, from: item.id, caretOffset: caretOffset)
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
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("顶层待办 Return 后按 Tab 创建 1. 子项；Return 延续编号；Shift-Tab 减少层级；空编号 Backspace 返回下一项待办")
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

    private func commitAndFocus(itemID: UUID, replacingUTF16Range selection: NSRange) {
        guard let insertedID = model.commitItem(
            id: itemID,
            replacingUTF16Range: selection
        ) else { return }
        requestFocus(itemID: insertedID, caretOffset: 0)
    }

    private func moveFocus(from id: UUID, direction: Int, caretOffset: Int) {
        guard let index = model.document.items.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard model.document.items.indices.contains(targetIndex) else { return }
        requestFocus(itemID: model.document.items[targetIndex].id, caretOffset: caretOffset)
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
    let onUndo: (_ caretOffset: Int) -> OutlineHistoryFocus?
    let onRedo: (_ caretOffset: Int) -> OutlineHistoryFocus?
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
        field.textColor = textColor
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
        field.onUndo = onUndo
        field.onRedo = onRedo
        field.onBeginEditing = onBeginEditing
        field.onEndEditing = onEndEditing
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
        (field as? OutlineTextField)?.applyTextAppearance(
            textColor: textColor,
            insertionPointColor: insertionPointColor
        )
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
            (field as? OutlineTextField)?.invalidateWrappingHeight()
        }
        (field as? OutlineTextField)?.applyStrikethrough(isStruck)
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

    func applyStrikethrough(_ enabled: Bool) {
        let styleKey = NSAttributedString.Key.strikethroughStyle
        let styleValue = NSUnderlineStyle.single.rawValue
        if let editor = currentEditor() as? NSTextView, let storage = editor.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            if range.length > 0 {
                if enabled {
                    storage.addAttribute(styleKey, value: styleValue, range: range)
                } else {
                    storage.removeAttribute(styleKey, range: range)
                }
            }
            var attributes = editor.typingAttributes
            if enabled {
                attributes[styleKey] = styleValue
            } else {
                attributes.removeValue(forKey: styleKey)
            }
            editor.typingAttributes = attributes
            return
        }

        let attributed = NSMutableAttributedString(string: stringValue)
        let range = NSRange(location: 0, length: attributed.length)
        if range.length > 0 {
            if let font = font {
                attributed.addAttribute(.font, value: font, range: range)
            }
            attributed.addAttribute(.foregroundColor, value: textColor ?? NSColor.labelColor, range: range)
            if enabled {
                attributed.addAttribute(styleKey, value: styleValue, range: range)
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
