#if LOCAL_NOTE_DIRECT_TESTS
import AppKit
import Foundation
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TestSecretStore: SecretStoring {
    var values: [String: String] = [:]
    var failure: Error?

    func read(account: String) throws -> String? {
        if let failure = failure { throw failure }
        return values[account]
    }

    func save(_ value: String, account: String) throws {
        if let failure = failure { throw failure }
        values[account] = value
    }

    func delete(account: String) throws {
        if let failure = failure { throw failure }
        values.removeValue(forKey: account)
    }
}

final class DelayedTransport: HTTPTransporting {
    typealias Completion = (Result<(Data, HTTPURLResponse), Error>) -> Void
    var requests: [URLRequest] = []
    private var completions: [Completion] = []

    func send(_ request: URLRequest, completion: @escaping Completion) {
        requests.append(request)
        completions.append(completion)
    }

    func succeedNext(markdown: String, truncated: Bool = false) throws {
        guard !completions.isEmpty else { throw TestFailure.message("no delayed request is waiting") }
        let request = requests[requests.count - completions.count]
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let data = try JSONSerialization.data(withJSONObject: [
            "object": "page_markdown",
            "id": "12345678-90ab-cdef-1234-567890abcdef",
            "markdown": markdown,
            "truncated": truncated,
            "unknown_block_ids": []
        ])
        let completion = completions.removeFirst()
        completion(.success((data, response)))
    }
}

private struct IntentionalStoreError: Error {}

private final class FailingDayStore: DayStoring {
    func load(dateKey: String) throws -> DayDocument { DayDocument(dateKey: dateKey) }
    func save(_ document: DayDocument) throws { throw IntentionalStoreError() }
}

private struct AppFixture {
    let root: URL
    let dayStore: FileDayStore
    let snapshotStore: SyncSnapshotStore
    let secrets: TestSecretStore
    let defaults: UserDefaults
    let model: AppModel
}

private func appFixture(
    transport: HTTPTransporting = StubTransport(),
    pageID: String = "",
    token: String = ""
) throws -> AppFixture {
    let root = try temporaryDirectory()
    let dayStore = FileDayStore(rootURL: root.appendingPathComponent("days", isDirectory: true))
    let snapshotStore = SyncSnapshotStore(rootURL: root.appendingPathComponent("sync", isDirectory: true))
    let secrets = TestSecretStore()
    if !token.isEmpty { secrets.values[AppModel.tokenAccount] = token }
    let suiteName = "dev.sealdot.LocalNote.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    if !pageID.isEmpty { defaults.set(pageID, forKey: AppModel.pageIDDefaultsKey) }
    let model = AppModel(
        dayStore: dayStore,
        snapshotStore: snapshotStore,
        secretStore: secrets,
        notionClient: NotionClient(transport: transport, baseURL: URL(string: "https://example.test")!),
        defaults: defaults,
        monitorsNetwork: false
    )
    return AppFixture(
        root: root,
        dayStore: dayStore,
        snapshotStore: snapshotStore,
        secrets: secrets,
        defaults: defaults,
        model: model
    )
}

@discardableResult
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

private func allTextFields(in view: NSView) -> [NSTextField] {
    let current = (view as? NSTextField).map { [$0] } ?? []
    return current + view.subviews.flatMap(allTextFields)
}

private func sendKey(
    keyCode: UInt16,
    characters: String,
    modifiers: NSEvent.ModifierFlags = [],
    to editor: NSTextView,
    window: NSWindow
) throws {
    let event = try NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    ).unwrap("keyboard event should be created")
    editor.interpretKeyEvents([event])
}

private func pasteboardSnapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { source in
        let copy = NSPasteboardItem()
        for type in source.types {
            if let data = source.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }
}

private func restorePasteboard(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

private func colorSignature(_ color: NSColor) -> String {
    let resolved = color.usingColorSpace(.sRGB) ?? color
    return String(
        format: "%.4f-%.4f-%.4f-%.4f",
        resolved.redComponent,
        resolved.greenComponent,
        resolved.blueComponent,
        resolved.alphaComponent
    )
}

func appTests() -> [TestCase] {
    [
        TestCase("menu bar app registers standard editing shortcuts") {
            let mainMenu = ApplicationMenu.make()
            let editMenu = try mainMenu.items.compactMap(\.submenu)
                .first(where: { $0.title == "编辑" })
                .unwrap("edit menu should exist")
            func action(for key: String) -> Selector? {
                editMenu.items.first(where: { $0.keyEquivalent.lowercased() == key })?.action
            }
            try expect(action(for: "v") == #selector(NSText.paste(_:)), "Command-V must route to the text responder")
            try expect(action(for: "a") == #selector(NSText.selectAll(_:)), "Command-A must route to the text responder")
            try expect(action(for: "x") == #selector(NSText.cut(_:)), "Command-X must route to the text responder")
            try expect(
                action(for: "c") == #selector(OutlineCommandRouter.copyLocalNote(_:)),
                "Command-C must route through outline-aware copy handling"
            )
            let copyItem = try editMenu.items.first(where: { $0.keyEquivalent.lowercased() == "c" })
                .unwrap("copy menu item should exist")
            try expect(copyItem.target === OutlineCommandRouter.shared, "copy should use the outline command router")
            let undoItem = try editMenu.items.first(where: { $0.title == "撤销" })
                .unwrap("undo menu item should exist")
            try expect(
                undoItem.action == #selector(OutlineCommandRouter.undoLocalNote(_:)),
                "Command-Z must route to model-backed outline history"
            )
            try expect(undoItem.target === OutlineCommandRouter.shared, "undo should use the outline command router")
            let redoItem = try editMenu.items.first(where: { $0.title == "重做" })
                .unwrap("redo menu item should exist")
            try expect(
                redoItem.action == #selector(OutlineCommandRouter.redoLocalNote(_:)),
                "Command-Shift-Z must route to model-backed outline history"
            )
            try expect(
                redoItem.keyEquivalentModifierMask == [.command, .shift],
                "redo shortcut should use Command-Shift"
            )
            let strikeItem = try editMenu.items
                .first(where: { $0.title == "切换划线" })
                .unwrap("strikethrough menu item should exist")
            try expect(
                strikeItem.action == #selector(OutlineCommandRouter.toggleLocalNoteStrikethrough(_:)),
                "Command-Shift-S must route to the outline responder"
            )
            try expect(strikeItem.keyEquivalent == "s", "strikethrough shortcut should use S")
            try expect(
                strikeItem.keyEquivalentModifierMask == [.command, .shift],
                "strikethrough shortcut should use Command-Shift"
            )
        },
        TestCase("cross-row text selection preserves partial endpoints") {
            let first = OutlineItem(text: "first")
            let second = OutlineItem(text: "second")
            let third = OutlineItem(text: "third")
            let items = [first, second, third]
            let forward = OutlineTextSelection(
                anchor: OutlineTextPosition(itemID: first.id, utf16Offset: 2),
                extent: OutlineTextPosition(itemID: third.id, utf16Offset: 3)
            )
            try expect(forward.text(in: items) == "rst\nsecond\nthi", "forward drag should keep partial endpoints")
            try expect(
                forward.range(for: first, in: items) == NSRange(location: 2, length: 3),
                "the first row should select from the mouse anchor"
            )
            try expect(
                forward.range(for: second, in: items) == NSRange(location: 0, length: 6),
                "intermediate rows should be fully selected"
            )
            try expect(
                forward.range(for: third, in: items) == NSRange(location: 0, length: 3),
                "the last row should select through the mouse extent"
            )

            let reverse = OutlineTextSelection(
                anchor: OutlineTextPosition(itemID: third.id, utf16Offset: 3),
                extent: OutlineTextPosition(itemID: first.id, utf16Offset: 2)
            )
            try expect(reverse.text(in: items) == forward.text(in: items), "reverse drag should copy document order")
        },
        TestCase("mouse drag across outline fields copies multiple lines") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let pasteboard = NSPasteboard.general
            let pasteboardItems = pasteboardSnapshot(pasteboard)
            defer { restorePasteboard(pasteboardItems, to: pasteboard) }
            let firstID = try fixture.model.addItem().unwrap("first row should be added")
            fixture.model.updateText(id: firstID, text: "first")
            let secondID = try fixture.model.addPeer(after: firstID).unwrap("second row should be added")
            fixture.model.updateText(id: secondID, text: "second")
            let thirdID = try fixture.model.addPeer(after: secondID).unwrap("third row should be added")
            fixture.model.updateText(id: thirdID, text: "third")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let fields = allTextFields(in: controller.view)
            let firstField = try fields.first(where: { $0.identifier?.rawValue == firstID.uuidString })
                .unwrap("first field should be rendered")
            let thirdField = try fields.first(where: { $0.identifier?.rawValue == thirdID.uuidString })
                .unwrap("third field should be rendered")
            let firstRect = firstField.convert(firstField.bounds, to: nil)
            let thirdRect = thirdField.convert(thirdField.bounds, to: nil)
            let start = NSPoint(x: firstRect.minX + 1, y: firstRect.midY)
            let end = NSPoint(x: thirdRect.maxX - 1, y: thirdRect.midY)
            func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
                try NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1
                ).unwrap("mouse event should be created")
            }
            let mouseDown = try mouseEvent(.leftMouseDown, at: start)
            let mouseDrag = try mouseEvent(.leftMouseDragged, at: end)
            let mouseUp = try mouseEvent(.leftMouseUp, at: end)
            NSApplication.shared.postEvent(mouseDrag, atStart: false)
            NSApplication.shared.postEvent(mouseUp, atStart: false)
            firstField.mouseDown(with: mouseDown)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            let menu = ApplicationMenu.make()
            NSApplication.shared.mainMenu = menu
            let copyItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "复制" })
                .unwrap("copy menu item should exist")
            pasteboard.clearContents()
            try expect(
                NSApplication.shared.sendAction(copyItem.action!, to: copyItem.target, from: copyItem),
                "copy should reach the cross-row mouse selection"
            )
            let copiedText = pasteboard.string(forType: .string)
            try expect(
                copiedText == "first\nsecond\nthird",
                "mouse-selected rows should copy as newline-delimited text; copied \(String(describing: copiedText))"
            )
            window.close()
        },
        TestCase("Command-V reaches a real SwiftUI outline field") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let pasteboard = NSPasteboard.general
            let pasteboardItems = pasteboardSnapshot(pasteboard)
            defer { restorePasteboard(pasteboardItems, to: pasteboard) }
            fixture.model.addItem()
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let field = try allTextFields(in: controller.view)
                .first(where: { $0.placeholderString == "待办事项" })
                .unwrap("outline text field should be rendered")
            try expect(window.makeFirstResponder(field), "outline field should accept first responder")
            field.selectText(nil)
            try expect(window.firstResponder is NSTextView, "outline field editor should become first responder")

            pasteboard.clearContents()
            pasteboard.setString("快捷键粘贴", forType: .string)
            let menu = ApplicationMenu.make()
            NSApplication.shared.mainMenu = menu
            let pasteItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.keyEquivalent == "v" })
                .unwrap("paste menu item should exist")
            try expect(
                NSApplication.shared.sendAction(pasteItem.action!, to: window.firstResponder, from: pasteItem),
                "paste action should reach the field editor"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let editorValue = (window.firstResponder as? NSTextView)?.string ?? "<no editor>"
            let modelValue = fixture.model.document.items.first?.text ?? "<missing>"
            try expect(
                modelValue == "快捷键粘贴",
                "paste should update the AppModel binding (editor='\(editorValue)', field='\(field.stringValue)', model='\(modelValue)')"
            )
            window.close()
        },
        TestCase("Command-Shift-S toggles the focused outline row") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("outline row should exist")
            fixture.model.updateText(id: id, text: "toggle strike")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let field = try allTextFields(in: controller.view)
                .first(where: { $0.stringValue == "toggle strike" })
                .unwrap("outline text field should be rendered")
            try expect(
                field.allowsEditingTextAttributes,
                "outline fields must preserve strikethrough attributes while the caret is active"
            )
            try expect(window.makeFirstResponder(field), "outline field should accept first responder")
            try expect(window.firstResponder is NSTextView, "outline field editor should become first responder")
            try expect(field.currentEditor() === window.firstResponder, "outline field should own the active field editor")
            try expect(
                field.responds(to: #selector(OutlineCommandRouter.toggleLocalNoteStrikethrough(_:))),
                "outline field should expose the strikethrough responder action"
            )

            let menu = ApplicationMenu.make()
            NSApplication.shared.mainMenu = menu
            let strikeItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "切换划线" })
                .unwrap("strikethrough menu item should exist")
            try expect(
                NSApplication.shared.sendAction(strikeItem.action!, to: strikeItem.target, from: strikeItem),
                "strikethrough action should reach the focused outline field"
            )
            try expect(
                waitUntil { fixture.model.document.items.first?.manualStrikethrough == true },
                "the focused row should become struck"
            )
            try expect(
                NSApplication.shared.sendAction(strikeItem.action!, to: strikeItem.target, from: strikeItem),
                "strikethrough action should remain available after toggling"
            )
            try expect(
                waitUntil { fixture.model.document.items.first?.manualStrikethrough == false },
                "pressing the shortcut again should remove strikethrough"
            )
            window.close()
        },
        TestCase("dark appearance keeps active outline typing visible") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let itemID = try fixture.model.addItem().unwrap("outline row should be added")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.appearance = NSAppearance(named: .darkAqua)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let field = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == itemID.uuidString })
                .unwrap("outline field should be rendered")
            try expect(window.makeFirstResponder(field), "outline field should accept focus")
            let editor = try (field.currentEditor() as? NSTextView).unwrap("field editor should be active")
            let typingColor = editor.typingAttributes[.foregroundColor] as? NSColor
            try expect(
                typingColor?.isEqual(NSColor.labelColor) == true,
                "dark-mode typing should use the system label color"
            )

            editor.insertText("夜间输入", replacementRange: editor.selectedRange())
            let insertedColor = editor.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
            try expect(
                insertedColor?.isEqual(NSColor.labelColor) == true,
                "new dark-mode text should retain the system label color"
            )
            window.close()
        },
        TestCase("Shift-Down selects consecutive rows for one strikethrough action") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let pasteboard = NSPasteboard.general
            let pasteboardItems = pasteboardSnapshot(pasteboard)
            defer { restorePasteboard(pasteboardItems, to: pasteboard) }
            let firstID = try fixture.model.addItem().unwrap("first row should be added")
            fixture.model.updateText(id: firstID, text: "first")
            let secondID = try fixture.model.addPeer(after: firstID).unwrap("second row should be added")
            fixture.model.updateText(id: secondID, text: "second")
            let thirdID = try fixture.model.addPeer(after: secondID).unwrap("third row should be added")
            fixture.model.updateText(id: thirdID, text: "third")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let fields = allTextFields(in: controller.view)
            let firstField = try fields
                .first(where: { $0.identifier?.rawValue == firstID.uuidString })
                .unwrap("first field should be rendered")
            let secondField = try fields
                .first(where: { $0.identifier?.rawValue == secondID.uuidString })
                .unwrap("second field should be rendered")
            try expect(window.makeFirstResponder(firstField), "first field should accept focus")
            let firstEditor = try (firstField.currentEditor() as? NSTextView)
                .unwrap("first editor should be active")

            try sendKey(
                keyCode: 125,
                characters: "\u{f701}",
                modifiers: [.shift],
                to: firstEditor,
                window: window
            )
            try expect(
                waitUntil { secondField.currentEditor() != nil },
                "Shift-Down should extend the row selection and focus its endpoint"
            )
            try expect(firstField.currentEditor() == nil, "only the focused field should expose the shared editor")

            let menu = ApplicationMenu.make()
            NSApplication.shared.mainMenu = menu
            let copyItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "复制" })
                .unwrap("copy menu item should exist")
            pasteboard.clearContents()
            try expect(
                NSApplication.shared.sendAction(copyItem.action!, to: copyItem.target, from: copyItem),
                "copy should reach the multi-row selection endpoint"
            )
            try expect(
                pasteboard.string(forType: .string) == "first\nsecond",
                "copy should preserve selected row boundaries as newlines"
            )
            let strikeItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "切换划线" })
                .unwrap("strikethrough menu item should exist")
            try expect(
                NSApplication.shared.sendAction(strikeItem.action!, to: strikeItem.target, from: strikeItem),
                "strikethrough action should reach the multi-row selection endpoint"
            )
            try expect(
                waitUntil {
                    fixture.model.document.items.map(\.manualStrikethrough) == [true, true, false]
                },
                "one action should strike every selected row and no unselected row"
            )
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    guard firstField.attributedStringValue.length > 0 else { return false }
                    return firstField.attributedStringValue.attribute(
                        .strikethroughStyle,
                        at: 0,
                        effectiveRange: nil
                    ) != nil
                },
                "the inactive selected row should render its strikethrough"
            )
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    guard let storage = (secondField.currentEditor() as? NSTextView)?.textStorage,
                          storage.length > 0 else { return false }
                    return storage.attribute(
                        NSAttributedString.Key.strikethroughStyle,
                        at: 0,
                        effectiveRange: nil
                    ) != nil
                },
                "the focused selected row should render its strikethrough"
            )
            try expect(
                NSApplication.shared.sendAction(strikeItem.action!, to: strikeItem.target, from: strikeItem),
                "the selected rows should remain available for a second action"
            )
            try expect(
                waitUntil {
                    fixture.model.document.items.map(\.manualStrikethrough) == [false, false, false]
                },
                "a second action should remove strikethrough from the whole selection"
            )
            window.close()
        },
        TestCase("long outline text wraps and grows without overlapping the next row") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let longID = try fixture.model.addItem().unwrap("long row should be added")
            fixture.model.updateText(
                id: longID,
                text: "进线中 B 端，用户存在主动挂断的情况：output 有 to_manual 但后续仍有较长的补充说明，需要完整自动换行展示"
            )
            let nextID = try fixture.model.addPeer(after: longID).unwrap("next row should be added")
            fixture.model.updateText(id: nextID, text: "其他事项")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let fields = allTextFields(in: controller.view)
            let longField = try fields
                .first(where: { $0.identifier?.rawValue == longID.uuidString })
                .unwrap("long field should be rendered")
            let nextField = try fields
                .first(where: { $0.identifier?.rawValue == nextID.uuidString })
                .unwrap("next field should be rendered")
            let longRect = longField.convert(longField.bounds, to: controller.view)
            let nextRect = nextField.convert(nextField.bounds, to: controller.view)

            try expect(!longField.usesSingleLineMode, "outline fields must allow automatic wrapping")
            try expect(longField.maximumNumberOfLines == 0, "outline fields must not truncate wrapped lines")
            try expect(
                longRect.height > nextRect.height * 1.5,
                "a wrapped item should grow beyond a one-line item (long=\(longRect.height), short=\(nextRect.height))"
            )
            try expect(
                longRect.maxY <= nextRect.minY + 1 || nextRect.maxY <= longRect.minY + 1,
                "a wrapped item must not overlap the following row (long=\(longRect), next=\(nextRect))"
            )
            try expect(window.makeFirstResponder(longField), "long field should remain editable")
            let editor = try (longField.currentEditor() as? NSTextView).unwrap("long field editor should be active")
            try expect(!editor.isHorizontallyResizable, "the active field editor must wrap instead of scrolling sideways")
            try expect(
                editor.textContainer?.widthTracksTextView == true,
                "the active field editor must wrap at the visible row width"
            )
            let initialHeight = longField.bounds.height
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertText(
                "；继续补充一段足够长的输入内容，验证编辑过程中高度可以实时增长，而且不会让光标离开当前事项",
                replacementRange: editor.selectedRange()
            )
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return longField.bounds.height > initialHeight + 5
                        && fixture.model.document.items.first?.text == editor.string
                },
                "typing past the current line count should grow the active row and update the model"
            )
            try expect(longField.currentEditor() === editor, "growing a row must preserve the active editor")
            let grownRect = longField.convert(longField.bounds, to: controller.view)
            let movedNextRect = nextField.convert(nextField.bounds, to: controller.view)
            try expect(
                grownRect.maxY <= movedNextRect.minY + 1 || movedNextRect.maxY <= grownRect.minY + 1,
                "a row that grows while editing must keep the following row outside its bounds"
            )
            window.close()
        },
        TestCase("Up and Down move focus between outline rows") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let firstID = try fixture.model.addItem().unwrap("first row should be added")
            fixture.model.updateText(id: firstID, text: "1234")
            let secondID = try fixture.model.addPeer(after: firstID).unwrap("second row should be added")
            fixture.model.updateText(id: secondID, text: "xy")
            let thirdID = try fixture.model.addPeer(after: secondID).unwrap("third row should be added")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let fields = allTextFields(in: controller.view)
            let firstField = try fields
                .first(where: { $0.identifier?.rawValue == firstID.uuidString })
                .unwrap("first field should be rendered")
            let secondField = try fields
                .first(where: { $0.identifier?.rawValue == secondID.uuidString })
                .unwrap("second field should be rendered")
            let thirdField = try fields
                .first(where: { $0.identifier?.rawValue == thirdID.uuidString })
                .unwrap("third field should be rendered")

            try expect(window.makeFirstResponder(firstField), "first field should accept focus")
            let firstEditor = try (window.firstResponder as? NSTextView).unwrap("first editor should be active")
            firstEditor.setSelectedRange(NSRange(location: 3, length: 0))
            try sendKey(keyCode: 125, characters: "\u{f701}", to: firstEditor, window: window)
            try expect(waitUntil { secondField.currentEditor() != nil }, "Down should focus the next row")
            let secondEditor = try (secondField.currentEditor() as? NSTextView).unwrap("second editor should be active")
            try expect(secondEditor.selectedRange().location == 2, "Down should preserve and clamp the caret column")

            try sendKey(keyCode: 125, characters: "\u{f701}", to: secondEditor, window: window)
            try expect(waitUntil { thirdField.currentEditor() != nil }, "Down should focus an empty next row")
            let thirdEditor = try (thirdField.currentEditor() as? NSTextView).unwrap("third editor should be active")
            try expect(thirdEditor.selectedRange().location == 0, "an empty row should place the caret at its start")

            try sendKey(keyCode: 126, characters: "\u{f700}", to: thirdEditor, window: window)
            try expect(waitUntil { secondField.currentEditor() != nil }, "Up should focus the previous row")
            try expect(
                fixture.model.document.items.map(\.text) == ["1234", "xy", ""],
                "vertical navigation must not change row content"
            )
            window.close()
        },
        TestCase("save and sync status updates preserve marked text input") {
            let transport = DelayedTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("outline row should exist")
            fixture.model.updateText(id: id, text: "安排")
            fixture.model.flushSave()
            let key = fixture.model.dateKey
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] 安排"))
            fixture.model.syncNow()
            try expect(transport.requests.count == 1, "sync should be in flight before editing starts")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let field = try allTextFields(in: controller.view)
                .first(where: { $0.stringValue == "安排" })
                .unwrap("outline text field should be rendered")
            try expect(window.makeFirstResponder(field), "outline field should accept first responder")
            let editor = try (window.firstResponder as? NSTextView).unwrap("field editor should become first responder")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.setMarkedText(
                "xia'wu",
                selectedRange: NSRange(location: 6, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            let composingText = editor.string
            let composingRange = editor.markedRange()
            try expect(editor.hasMarkedText(), "fixture should contain an active input-method composition")
            try expect(
                fixture.model.document.items.first?.text == "安排",
                "marked text should not be persisted before the input method commits it"
            )

            fixture.model.toggleCompletion(id: id)
            try transport.succeedNext(markdown: "\(DateKey.compact(key))\n\t- [ ] 安排\n<empty-block/>")
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            controller.view.layoutSubtreeIfNeeded()
            try expect(window.firstResponder === editor, "sync status changes must not move keyboard focus")
            try expect(editor.hasMarkedText(), "sync status changes must preserve marked text")
            try expect(editor.string == composingText, "sync status changes must not rewrite the active editor")
            try expect(editor.markedRange() == composingRange, "sync status changes must preserve the composition range")
            window.close()
        },
        TestCase("Backspace clears text before removing an empty outline row") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("outline row should exist")
            fixture.model.updateText(id: id, text: "x")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let field = try allTextFields(in: controller.view)
                .first(where: { $0.placeholderString == "待办事项" })
                .unwrap("outline text field should be rendered")
            try expect(window.makeFirstResponder(field), "outline field should accept first responder")
            let editor = try (window.firstResponder as? NSTextView).unwrap("field editor should become first responder")
            try sendKey(keyCode: 51, characters: "\u{7f}", to: editor, window: window)
            try expect(
                waitUntil { fixture.model.document.items.count == 1 && fixture.model.document.items[0].text.isEmpty },
                "the first Backspace should clear the final character without deleting the row"
            )
            try sendKey(keyCode: 51, characters: "\u{7f}", to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.isEmpty }, "the next Backspace on the empty row should delete it")
            window.close()
        },
        TestCase("Backspace on an empty row focuses the previous row") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let firstID = try fixture.model.addItem().unwrap("first row should be added")
            fixture.model.updateText(id: firstID, text: "previous")
            let secondID = try fixture.model.addPeer(after: firstID).unwrap("second row should be added")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let fields = allTextFields(in: controller.view)
            let firstField = try fields
                .first(where: { $0.identifier?.rawValue == firstID.uuidString })
                .unwrap("first field should be rendered")
            let secondField = try fields
                .first(where: { $0.identifier?.rawValue == secondID.uuidString })
                .unwrap("second field should be rendered")
            try expect(window.makeFirstResponder(secondField), "empty second field should accept focus")
            let editor = try (window.firstResponder as? NSTextView).unwrap("second editor should be active")

            try sendKey(keyCode: 51, characters: "\u{7f}", to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 1 }, "Backspace should remove the empty row")
            try expect(waitUntil { firstField.currentEditor() != nil }, "Backspace should focus the previous row")
            let previousEditor = try (firstField.currentEditor() as? NSTextView).unwrap("previous editor should be active")
            try expect(previousEditor.selectedRange().location == "previous".utf16.count, "caret should move to the previous row end")
            window.close()
        },
        TestCase("Tab and Return follow outline-editor conventions") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let firstID = try fixture.model.document.items.first.map(\.id).unwrap("first row should exist")
            fixture.model.updateText(id: firstID, text: "first")
            fixture.model.addPeer(after: firstID)
            let secondID = try fixture.model.document.items.last.map(\.id).unwrap("second row should exist")
            fixture.model.updateText(id: secondID, text: "second")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let secondField = try allTextFields(in: controller.view)
                .first(where: { $0.stringValue == "second" })
                .unwrap("second outline field should be rendered")
            try expect(window.makeFirstResponder(secondField), "second field should accept first responder")
            let editor = try (window.firstResponder as? NSTextView).unwrap("second field editor should become first responder")

            try sendKey(keyCode: 48, characters: "\t", to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.last?.depth == 1 }, "Tab should indent the current row")
            try sendKey(keyCode: 48, characters: "\u{19}", modifiers: [.shift], to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.last?.depth == 0 }, "Shift-Tab should outdent the current row")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            try sendKey(keyCode: 36, characters: "\r", to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 3 }, "Return should add a peer row")
            let insertedID = try fixture.model.document.items.last.map(\.id).unwrap("inserted peer should exist")
            try expect(
                waitUntil {
                    allTextFields(in: controller.view)
                        .first(where: { $0.identifier?.rawValue == insertedID.uuidString })?
                        .currentEditor() != nil
                },
                "Return should focus the inserted peer row"
            )
            window.close()
        },
        TestCase("adding an incomplete child reopens and unstrikes its completed parent") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let parentID = try fixture.model.addItem().unwrap("parent row should be added")
            fixture.model.updateText(id: parentID, text: "其他事项")
            let childID = try fixture.model.addPeer(after: parentID).unwrap("child row should be added")
            fixture.model.indent(id: childID)
            fixture.model.updateText(id: childID, text: "已完成子任务")
            fixture.model.toggleStrike(id: childID)
            try expect(
                fixture.model.document.items.first?.checked == true,
                "a parent whose children are all complete should start checked"
            )

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let fields = allTextFields(in: controller.view)
            let parentField = try fields
                .first(where: { $0.identifier?.rawValue == parentID.uuidString })
                .unwrap("parent field should be rendered")
            let childField = try fields
                .first(where: { $0.identifier?.rawValue == childID.uuidString })
                .unwrap("child field should be rendered")
            try expect(window.makeFirstResponder(childField), "completed child should accept focus")
            let editor = try (childField.currentEditor() as? NSTextView)
                .unwrap("completed child editor should be active")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))

            try sendKey(keyCode: 36, characters: "\r", to: editor, window: window)
            try expect(
                waitUntil {
                    guard fixture.model.document.items.count == 3 else { return false }
                    let parent = fixture.model.document.items[0]
                    let newChild = fixture.model.document.items[2]
                    return !parent.checked
                        && !parent.isStruck
                        && newChild.depth == 1
                        && newChild.kind == .numbered
                        && !newChild.isStruck
                },
                "Return should immediately reopen the parent when it adds an incomplete child"
            )
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    guard parentField.attributedStringValue.length > 0 else { return false }
                    return parentField.attributedStringValue.attribute(
                        .strikethroughStyle,
                        at: 0,
                        effectiveRange: nil
                    ) == nil
                },
                "the reopened parent should render without strikethrough"
            )
            window.close()
        },
        TestCase("Return at the caret splits a parent before its descendants") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let parentID = try fixture.model.addItem().unwrap("parent row should be added")
            fixture.model.updateText(id: parentID, text: "客诉专项")
            let childID = try fixture.model.addPeer(after: parentID).unwrap("child candidate should be added")
            fixture.model.indent(id: childID)
            fixture.model.updateText(id: childID, text: "问题查看")
            let nextID = try fixture.model.addPeer(after: parentID).unwrap("next parent should be added")
            fixture.model.updateText(id: nextID, text: "客诉梳理")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let parentField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == parentID.uuidString })
                .unwrap("parent field should be rendered")
            try expect(window.makeFirstResponder(parentField), "parent field should accept focus")
            let editor = try (parentField.currentEditor() as? NSTextView).unwrap("parent editor should be active")
            editor.setSelectedRange(NSRange(location: 0, length: 0))

            try sendKey(keyCode: 36, characters: "\r", to: editor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items.map(\.text) == ["", "客诉专项", "问题查看", "客诉梳理"]
                },
                "Return at line start should split where the caret is instead of skipping the child subtree"
            )
            try expect(
                fixture.model.document.items.map(\.depth) == [0, 0, 1, 0],
                "the existing child should remain under the moved parent text"
            )
            let splitID = fixture.model.document.items[1].id
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .first(where: { $0.identifier?.rawValue == splitID.uuidString })?
                        .currentEditor() != nil
                },
                "the right-hand row should receive focus at the split point"
            )

            let menu = ApplicationMenu.make()
            NSApplication.shared.mainMenu = menu
            let undoItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "撤销" })
                .unwrap("undo item should exist")
            try expect(
                NSApplication.shared.sendAction(undoItem.action!, to: undoItem.target, from: undoItem),
                "Command-Z action should reach model history"
            )
            try expect(
                waitUntil { fixture.model.document.items.map(\.text) == ["客诉专项", "问题查看", "客诉梳理"] },
                "undo should restore the parent and remove the caret split"
            )
            let redoItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.title == "重做" })
                .unwrap("redo item should exist")
            try expect(
                NSApplication.shared.sendAction(redoItem.action!, to: redoItem.target, from: redoItem),
                "Command-Shift-Z action should reach model history"
            )
            try expect(
                waitUntil { fixture.model.document.items.map(\.text) == ["", "客诉专项", "问题查看", "客诉梳理"] },
                "redo should reapply the caret split"
            )
            window.close()
        },
        TestCase("number shortcut creates a continuing numbered structure") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let firstID = try fixture.model.addItem().unwrap("first row should be added")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let firstField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == firstID.uuidString })
                .unwrap("first outline field should be rendered")
            try expect(window.makeFirstResponder(firstField), "first field should accept focus")
            let firstEditor = try (window.firstResponder as? NSTextView).unwrap("first editor should be active")

            try sendKey(keyCode: 18, characters: "1", to: firstEditor, window: window)
            try sendKey(keyCode: 47, characters: ".", to: firstEditor, window: window)
            try sendKey(keyCode: 49, characters: " ", to: firstEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items.first?.kind == .numbered
                        && fixture.model.document.items.first?.text.isEmpty == true
                        && firstEditor.string.isEmpty
                },
                "typing 1. and space should convert the live row without leaving marker text"
            )
            try expect(firstField.currentEditor() === firstEditor, "shortcut conversion should preserve keyboard focus")

            try sendKey(keyCode: 0, characters: "first", to: firstEditor, window: window)
            try expect(waitUntil { fixture.model.document.items.first?.text == "first" }, "numbered row text should persist")
            try sendKey(keyCode: 36, characters: "\r", to: firstEditor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 2 }, "Return should add the next numbered row")
            let secondID = try fixture.model.document.items.last.map(\.id).unwrap("second numbered row should exist")
            try expect(fixture.model.document.items.last?.kind == .numbered, "the peer should preserve numbered style")
            try expect(fixture.model.displayPrefix(for: fixture.model.document.items[0]) == "1.", "the first row should display 1.")
            try expect(fixture.model.displayPrefix(for: fixture.model.document.items[1]) == "2.", "the peer should display 2.")
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .contains(where: { $0.identifier?.rawValue == secondID.uuidString && $0.currentEditor() != nil })
                },
                "Return should focus the second numbered row"
            )
            let resolvedSecondField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == secondID.uuidString })
                .unwrap("second outline field should be rendered")
            let secondEditor = try (resolvedSecondField.currentEditor() as? NSTextView).unwrap("second editor should be active")

            try sendKey(keyCode: 51, characters: "\u{7f}", to: secondEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items.count == 2
                        && fixture.model.document.items.last?.kind == .checkbox
                },
                "Backspace on an empty numbered row should return it to a normal to-do instead of deleting it"
            )
            try expect(resolvedSecondField.currentEditor() != nil, "returning to a to-do should preserve focus")

            let thirdID = try fixture.model.addPeer(after: secondID).unwrap("third row should be added")
            fixture.model.changeKind(id: thirdID, kind: .numbered)
            let third = try fixture.model.document.items.first(where: { $0.id == thirdID }).unwrap("third row should exist")
            try expect(fixture.model.displayPrefix(for: third) == "1.", "a numbered sequence should restart after a checkbox peer")
            window.close()
        },
        TestCase("Tab and Backspace create the reference checkbox-number hierarchy") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let parentID = try fixture.model.addItem().unwrap("parent to-do should be added")
            fixture.model.updateText(id: parentID, text: "数据统计")
            let firstChildID = try fixture.model.addPeer(after: parentID).unwrap("empty peer should be added")
            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let firstChildField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == firstChildID.uuidString })
                .unwrap("empty peer field should be rendered")
            try expect(window.makeFirstResponder(firstChildField), "empty peer should accept focus")
            let firstChildEditor = try (window.firstResponder as? NSTextView).unwrap("empty peer editor should be active")
            try sendKey(keyCode: 48, characters: "\t", to: firstChildEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items[1].depth == 1
                        && fixture.model.document.items[1].kind == .numbered
                        && fixture.model.displayPrefix(for: fixture.model.document.items[1]) == "1."
                },
                "Tab on a new empty checkbox should create the first numbered child"
            )
            try expect(firstChildField.currentEditor() === firstChildEditor, "automatic numbering should preserve focus")

            try sendKey(keyCode: 0, characters: "first child", to: firstChildEditor, window: window)
            try expect(waitUntil { fixture.model.document.items[1].text == "first child" }, "first child text should persist")
            try sendKey(keyCode: 36, characters: "\r", to: firstChildEditor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 3 }, "Return should create the second numeric child")
            let alphaID = try fixture.model.document.items.last.map(\.id).unwrap("nested candidate should exist")
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .contains(where: { $0.identifier?.rawValue == alphaID.uuidString && $0.currentEditor() != nil })
                },
                "new numeric child should receive focus"
            )
            let alphaField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == alphaID.uuidString })
                .unwrap("nested candidate field should render")
            let alphaEditor = try (alphaField.currentEditor() as? NSTextView).unwrap("nested candidate editor should be active")
            try sendKey(keyCode: 48, characters: "\t", to: alphaEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items[2].depth == 2
                        && fixture.model.displayPrefix(for: fixture.model.document.items[2]) == "a."
                },
                "a second indent should use the alphabetic child marker from the reference"
            )

            try sendKey(keyCode: 0, characters: "alpha child", to: alphaEditor, window: window)
            try expect(waitUntil { fixture.model.document.items[2].text == "alpha child" }, "alphabetic child text should persist")
            try sendKey(keyCode: 36, characters: "\r", to: alphaEditor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 4 }, "Return should continue the alphabetic list")
            let secondNumericID = try fixture.model.document.items.last.map(\.id).unwrap("second numeric candidate should exist")
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .contains(where: { $0.identifier?.rawValue == secondNumericID.uuidString && $0.currentEditor() != nil })
                },
                "continued alphabetic child should receive focus"
            )
            let secondNumericField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == secondNumericID.uuidString })
                .unwrap("second numeric candidate field should render")
            let secondNumericEditor = try (secondNumericField.currentEditor() as? NSTextView).unwrap("continued child editor should be active")
            try sendKey(keyCode: 48, characters: "\u{19}", modifiers: [.shift], to: secondNumericEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items[3].depth == 1
                        && fixture.model.displayPrefix(for: fixture.model.document.items[3]) == "2."
                },
                "Shift-Tab should return from alphabetic children to the next numeric item"
            )

            try sendKey(keyCode: 0, characters: "second child", to: secondNumericEditor, window: window)
            try expect(waitUntil { fixture.model.document.items[3].text == "second child" }, "second numeric child text should persist")
            try sendKey(keyCode: 36, characters: "\r", to: secondNumericEditor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 5 }, "Return should create an empty third numeric item")
            let nextParentID = try fixture.model.document.items.last.map(\.id).unwrap("next parent candidate should exist")
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .contains(where: { $0.identifier?.rawValue == nextParentID.uuidString && $0.currentEditor() != nil })
                },
                "empty third numeric item should receive focus"
            )
            let nextParentField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == nextParentID.uuidString })
                .unwrap("next parent candidate field should render")
            let nextParentEditor = try (nextParentField.currentEditor() as? NSTextView).unwrap("next parent candidate editor should be active")
            try sendKey(keyCode: 51, characters: "\u{7f}", to: nextParentEditor, window: window)
            try expect(
                waitUntil {
                    fixture.model.document.items.count == 5
                        && fixture.model.document.items[4].depth == 0
                        && fixture.model.document.items[4].kind == .checkbox
                },
                "Backspace should turn an empty numbered child into the next top-level checkbox"
            )
            try expect(nextParentField.currentEditor() != nil, "returning to the next parent should preserve focus")
            window.close()
        },
        TestCase("Backspace on an empty alphabetic row continues the parent numbered list") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let parentID = try fixture.model.addItem().unwrap("parent to-do should be added")
            fixture.model.updateText(id: parentID, text: "其他事项")

            let firstNumberID = try fixture.model.addPeer(after: parentID).unwrap("first numbered row should be added")
            fixture.model.indent(id: firstNumberID)
            fixture.model.updateText(id: firstNumberID, text: "部门周会")

            let firstAlphaID = try fixture.model.addPeer(after: firstNumberID).unwrap("first alphabetic row should be added")
            fixture.model.indent(id: firstAlphaID)
            fixture.model.updateText(id: firstAlphaID, text: "更新周报内容")

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()

            let firstAlphaField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == firstAlphaID.uuidString })
                .unwrap("first alphabetic field should be rendered")
            try expect(window.makeFirstResponder(firstAlphaField), "first alphabetic field should accept focus")
            let editor = try (window.firstResponder as? NSTextView).unwrap("first alphabetic editor should be active")
            try sendKey(keyCode: 36, characters: "\r", to: editor, window: window)

            try expect(
                waitUntil {
                    fixture.model.document.items.count == 4
                        && fixture.model.document.items[3].depth == 2
                        && fixture.model.document.items[3].kind == .numbered
                        && fixture.model.displayPrefix(for: fixture.model.document.items[3]) == "b."
                },
                "Return on non-empty a. should create an empty b."
            )
            let emptyAlphaID = fixture.model.document.items[3].id
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .first(where: { $0.identifier?.rawValue == emptyAlphaID.uuidString })?
                        .currentEditor() != nil
                },
                "the empty b. row should receive keyboard focus"
            )

            let emptyAlphaField = try allTextFields(in: controller.view)
                .first(where: { $0.identifier?.rawValue == emptyAlphaID.uuidString })
                .unwrap("empty alphabetic field should be rendered")
            let emptyAlphaEditor = try (emptyAlphaField.currentEditor() as? NSTextView)
                .unwrap("empty alphabetic editor should be active")
            try sendKey(keyCode: 51, characters: "\u{7f}", to: emptyAlphaEditor, window: window)

            try expect(
                waitUntil {
                    fixture.model.document.items.count == 4
                        && fixture.model.document.items[3].id == emptyAlphaID
                        && fixture.model.document.items[3].depth == 1
                        && fixture.model.document.items[3].kind == .numbered
                        && fixture.model.displayPrefix(for: fixture.model.document.items[3]) == "2."
                },
                "Backspace on empty b. should reuse the row as parent-level 2."
            )
            try expect(
                waitUntil {
                    controller.view.layoutSubtreeIfNeeded()
                    return allTextFields(in: controller.view)
                        .first(where: { $0.identifier?.rawValue == emptyAlphaID.uuidString })?
                        .currentEditor() != nil
                },
                "the converted 2. row should keep keyboard focus"
            )
            window.close()
        },
        TestCase("paste reaches both real Notion settings fields") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let pasteboard = NSPasteboard.general
            let pasteboardItems = pasteboardSnapshot(pasteboard)
            defer { restorePasteboard(pasteboardItems, to: pasteboard) }
            let controller = NSHostingController(
                rootView: ContentView(model: fixture.model, initiallyShowingSettings: true)
            )
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let fields = allTextFields(in: controller.view)
            let pageField = try fields.first(where: { $0.placeholderString == "Notion 页面 ID" })
                .unwrap("page ID field should be rendered")
            let tokenField = try fields.first(where: { $0.placeholderString == "ntn_…" })
                .unwrap("token field should be rendered")
            let menu = ApplicationMenu.make()
            let pasteItem = try menu.items.compactMap(\.submenu)
                .flatMap(\.items)
                .first(where: { $0.keyEquivalent == "v" })
                .unwrap("paste menu item should exist")

            try expect(window.makeFirstResponder(pageField), "page field should accept first responder")
            pageField.selectText(nil)
            pasteboard.clearContents()
            pasteboard.setString("https://notion.so/1234567890abcdef1234567890abcdef", forType: .string)
            try expect(
                NSApplication.shared.sendAction(pasteItem.action!, to: window.firstResponder, from: pasteItem),
                "paste should reach the page field"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            try expect(fixture.model.notionPageID.contains("1234567890abcdef"), "page URL should update its binding")

            try expect(window.makeFirstResponder(tokenField), "token field should accept first responder")
            tokenField.selectText(nil)
            pasteboard.clearContents()
            pasteboard.setString("ntn_settings_test", forType: .string)
            try expect(
                NSApplication.shared.sendAction(pasteItem.action!, to: window.firstResponder, from: pasteItem),
                "paste should reach the secure token field"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            try expect(fixture.model.notionToken == "ntn_settings_test", "token paste should update its binding")
            window.close()
        },
        TestCase("appearance preferences persist immediately and reset together") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let itemID = try fixture.model.addItem().unwrap("appearance fixture row should exist")
            fixture.model.updateText(id: itemID, text: "appearance must not edit content")
            fixture.model.notionPageID = "notion-value-stays-local"
            let originalDocument = fixture.model.document

            fixture.model.setAppearanceMode(.dark)
            fixture.model.setTheme(.midnight)
            fixture.model.setAccent(.teal)

            try expect(
                AppearancePreferences(defaults: fixture.defaults)
                    == AppearancePreferences(mode: .dark, theme: .midnight, accent: .teal),
                "appearance changes should persist without a save button"
            )
            try expect(fixture.model.document == originalDocument, "appearance changes must not mutate note content")
            try expect(fixture.model.notionPageID == "notion-value-stays-local", "appearance changes must not touch Notion settings")

            fixture.model.resetAppearance()
            try expect(fixture.model.appearance == .standard, "reset should update the live appearance")
            try expect(AppearancePreferences(defaults: fixture.defaults) == .standard, "reset should persist every default")
        },
        TestCase("unknown stored appearance values recover to safe defaults") {
            let suiteName = "dev.sealdot.LocalNote.appearance.invalid.\(UUID().uuidString)"
            let defaults = try UserDefaults(suiteName: suiteName).unwrap("appearance defaults suite should exist")
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("future-mode", forKey: AppearancePreferences.modeDefaultsKey)
            defaults.set("removed-theme", forKey: AppearancePreferences.themeDefaultsKey)
            defaults.set("missing-accent", forKey: AppearancePreferences.accentDefaultsKey)
            try expect(
                AppearancePreferences(defaults: defaults) == .standard,
                "unknown persisted values should never block launch"
            )
        },
        TestCase("appearance modes and paired themes resolve deterministically") {
            try expect(
                AppearanceMode.system.resolvedColorScheme(systemColorScheme: .dark) == .dark,
                "follow-system should use the environment scheme"
            )
            try expect(
                AppearanceMode.light.resolvedColorScheme(systemColorScheme: .dark) == .light,
                "forced light should ignore a dark environment"
            )
            try expect(
                AppearanceMode.dark.resolvedColorScheme(systemColorScheme: .light) == .dark,
                "forced dark should ignore a light environment"
            )

            for themeID in ThemeID.allCases {
                let light = LocalNoteTheme.resolve(
                    preferences: AppearancePreferences(mode: .light, theme: themeID),
                    systemColorScheme: .dark
                )
                let dark = LocalNoteTheme.resolve(
                    preferences: AppearancePreferences(mode: .dark, theme: themeID),
                    systemColorScheme: .light
                )
                try expect(light.colorScheme == .light && dark.colorScheme == .dark, "each theme should provide paired modes")
                try expect(
                    colorSignature(light.backgroundNSColor) != colorSignature(dark.backgroundNSColor),
                    "paired theme backgrounds should be visually distinct"
                )
            }
        },
        TestCase("every accent produces distinct calendar levels with readable high intensity text") {
            for themeID in ThemeID.allCases {
                for accentID in AccentID.allCases {
                    for mode in [AppearanceMode.light, .dark] {
                        let theme = LocalNoteTheme.resolve(
                            preferences: AppearancePreferences(mode: mode, theme: themeID, accent: accentID),
                            systemColorScheme: .light
                        )
                        try expect(theme.activityNSColors.count == 6, "calendar themes should always expose six levels")
                        try expect(
                            Set(theme.activityNSColors.map(colorSignature)).count == 6,
                            "calendar completion levels should remain visually distinct"
                        )
                        for level in 4...5 {
                            let ratio = LocalNoteTheme.contrastRatio(
                                theme.activityTextNSColor(level: level),
                                theme.activityNSColors[level]
                            )
                            try expect(ratio >= 4.5, "high-intensity day text should meet the readable contrast target")
                        }
                    }
                }
            }
        },
        TestCase("AppModel undo and redo restore text edits") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let id = try fixture.model.addItem().unwrap("row should be added")
            fixture.model.updateText(id: id, text: "第一版")
            fixture.model.updateText(id: id, text: "第二版")
            try expect(fixture.model.canUndo, "text editing should create undo history")
            try expect(fixture.model.undo(), "undo should succeed")
            try expect(fixture.model.document.items.first?.text == "第一版", "undo should restore the previous text")
            try expect(fixture.model.canRedo, "undo should create redo history")
            try expect(fixture.model.redo(), "redo should succeed")
            try expect(fixture.model.document.items.first?.text == "第二版", "redo should restore the newer text")
        },
        TestCase("AppModel edits persist across date navigation") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let originalDate = fixture.model.dateKey
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("new row should exist")
            fixture.model.updateText(id: id, text: "离线记录")
            fixture.model.toggleCompletion(id: id)
            fixture.model.flushSave()
            fixture.model.navigate(days: -1)
            try expect(fixture.model.document.items.isEmpty, "another day should load independently")
            fixture.model.navigate(days: 1)
            try expect(fixture.model.dateKey == originalDate, "navigation should return to the original day")
            try expect(fixture.model.document.items.first?.text == "离线记录", "text should survive reload")
            try expect(fixture.model.document.items.first?.checked == true, "completion should survive reload")
        },
        TestCase("calendar summaries combine historical files with the live selected day") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let currentKey = fixture.model.dateKey
            let historicalKey = try DateKey.adding(days: -2, to: currentKey).unwrap("historical date should exist")
            let history = DayDocument(dateKey: historicalKey, items: [
                OutlineItem(kind: .checkbox, text: "finished", checked: true),
                OutlineItem(kind: .checkbox, text: "open")
            ])
            try fixture.dayStore.save(history)

            let liveID = try fixture.model.addItem().unwrap("live row should be created")
            fixture.model.updateText(id: liveID, text: "not saved yet")
            let summaries = fixture.model.activitySummaries(for: [historicalKey, currentKey])

            try expect(summaries[historicalKey]?.completedTodos == 1, "history should load from its daily file")
            try expect(summaries[historicalKey]?.totalTodos == 2, "history should include open and completed to-dos")
            try expect(summaries[currentKey]?.totalTodos == 1, "the selected day should reflect unsaved in-memory edits")

            fixture.model.navigate(to: historicalKey)
            try expect(fixture.model.dateKey == historicalKey, "calendar selection should navigate directly to its date")
            try expect(fixture.model.document.items.map(\.text) == ["finished", "open"], "calendar selection should load the target day's outline")
        },
        TestCase("Notion settings validate normalize and use the secret store") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.notionPageID = "https://www.notion.so/Work-1234567890abcdef1234567890abcdef?pvs=4"
            fixture.model.notionToken = "  ntn_test-token  "
            try expect(fixture.model.saveSettings(), "valid settings should save")
            let expected = "12345678-90ab-cdef-1234-567890abcdef"
            try expect(fixture.model.notionPageID == expected, "page URL should normalize")
            try expect(fixture.defaults.string(forKey: AppModel.pageIDDefaultsKey) == expected, "page ID should use defaults")
            try expect(fixture.secrets.values[AppModel.tokenAccount] == "ntn_test-token", "token should be trimmed and stored as a secret")
            fixture.model.notionPageID = "not a Notion page"
            try expect(!fixture.model.saveSettings(), "invalid page IDs should be rejected before networking")
            try expect(fixture.defaults.string(forKey: AppModel.pageIDDefaultsKey) == expected, "invalid input must not overwrite valid settings")
        },
        TestCase("clearing settings removes the saved token") {
            let fixture = try appFixture(
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_existing"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.notionPageID = ""
            fixture.model.notionToken = ""
            try expect(fixture.model.saveSettings(), "empty settings should disable sync cleanly")
            try expect(fixture.secrets.values[AppModel.tokenAccount] == nil, "clearing token should delete the secret")
            try expect(fixture.model.syncState == .notConfigured, "cleared settings should show not configured")
        },
        TestCase("secret-store failure is surfaced without pretending to save") {
            let fixture = try appFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.secrets.failure = IntentionalStoreError()
            fixture.model.notionPageID = "12345678-90ab-cdef-1234-567890abcdef"
            fixture.model.notionToken = "ntn_test"
            try expect(!fixture.model.saveSettings(), "secret failure should fail settings save")
            try expect(fixture.model.syncState.label.contains("无法保存"), "secret failure should be visible")
        },
        TestCase("local save failures remain visible") {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(
                dayStore: FailingDayStore(),
                snapshotStore: SyncSnapshotStore(rootURL: root.appendingPathComponent("sync")),
                secretStore: TestSecretStore(),
                notionClient: NotionClient(transport: StubTransport(), baseURL: URL(string: "https://example.test")!),
                monitorsNetwork: false
            )
            model.addItem()
            model.flushSave()
            try expect(model.syncState.label == "本地保存失败", "failed local writes must not appear successful")
        },
        TestCase("Notion local-only change pushes the selected day") {
            let transport = StubTransport()
            transport.responseData = try notionResponse(markdown: "")
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("new row should exist")
            fixture.model.updateText(id: id, text: "push me")
            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .synced }, "push should finish")
            try expect(transport.requests.map(\.httpMethod) == ["GET", "PATCH"], "push should read before replacing")
            let patch = try transport.requests.last.unwrap("PATCH should be sent")
            let body = try JSONSerialization.jsonObject(with: patch.httpBody ?? Data()) as? [String: Any]
            let replace = body?["replace_content"] as? [String: Any]
            let markdown = replace?["new_str"] as? String
            try expect(markdown?.contains("push me") == true, "replacement should contain the local row")
        },
        TestCase("Notion remote-only change pulls without writing remote") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let remote = "\(DateKey.compact(fixture.model.dateKey))\n\t- [x] remote row\n<empty-block/>"
            transport.responseData = try notionResponse(markdown: remote)
            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .synced }, "pull should finish")
            try expect(transport.requests.count == 1, "pull should not PATCH Notion")
            try expect(fixture.model.document.items.first?.text == "remote row", "remote content should load locally")
            try expect(fixture.model.document.items.first?.checked == true, "remote completion should load locally")
        },
        TestCase("Notion numbering normalization does not create a false conflict") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let key = DateKey.compact(fixture.model.dateKey)
            transport.responseData = try notionResponse(
                markdown: "\(key)\n\t- [ ] group\n\t\t1. first\n\t\t2. second\n<empty-block/>"
            )

            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .synced }, "initial numbered pull should finish")
            try expect(fixture.model.document.items.map(\.depth) == [0, 1, 1], "numbered pull should preserve hierarchy")

            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .synced && transport.requests.count == 2 }, "a repeated pull should remain synced")
            try expect(transport.requests.map(\.httpMethod) == ["GET", "GET"], "equivalent Notion numbering must not trigger PATCH")
        },
        TestCase("Notion bare empty numbering does not conflict with local edits") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let parentID = try fixture.model.addItem().unwrap("parent should be added")
            fixture.model.updateText(id: parentID, text: "group")
            let childID = try fixture.model.addPeer(after: parentID).unwrap("empty child candidate should be added")
            fixture.model.indent(id: childID)
            fixture.model.flushSave()
            let baseMarkdown = MarkdownCodec.encode(fixture.model.document)
            try fixture.snapshotStore.save(
                SyncSnapshot(dateKey: fixture.model.dateKey, baseMarkdown: baseMarkdown)
            )

            fixture.model.updateText(id: childID, text: "local child")
            let key = DateKey.compact(fixture.model.dateKey)
            transport.responseData = try notionResponse(
                markdown: "\(key)\n\t- [ ] group\n\t\t1.\n<empty-block/>"
            )
            fixture.model.syncNow()

            try expect(waitUntil { fixture.model.syncState == .synced }, "Notion whitespace normalization should still allow the local push")
            try expect(transport.requests.map(\.httpMethod) == ["GET", "PATCH"], "equivalent empty numbering must not trigger a conflict")
            let patch = try transport.requests.last.unwrap("local edits should be pushed")
            let body = try JSONSerialization.jsonObject(with: patch.httpBody ?? Data()) as? [String: Any]
            let replacement = body?["replace_content"] as? [String: Any]
            try expect((replacement?["new_str"] as? String)?.contains("local child") == true, "the safe push should retain local edits")
        },
        TestCase("unchanged Notion day performs no remote write") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("row should exist")
            fixture.model.updateText(id: id, text: "same")
            fixture.model.flushSave()
            let localMarkdown = MarkdownCodec.encode(fixture.model.document)
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: fixture.model.dateKey, baseMarkdown: localMarkdown))
            transport.responseData = try notionResponse(
                markdown: "## \(DateKey.compact(fixture.model.dateKey))\n\n\(localMarkdown)"
            )
            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .synced }, "no-change sync should finish")
            try expect(transport.requests.count == 1, "unchanged content should only be retrieved")
        },
        TestCase("Notion concurrent changes stop at conflict") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let key = fixture.model.dateKey
            fixture.model.addItem()
            let localID = try fixture.model.document.items.first.map(\.id).unwrap("local row should exist")
            fixture.model.updateText(id: localID, text: "local")
            fixture.model.flushSave()
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] base"))
            transport.responseData = try notionResponse(
                markdown: "## \(DateKey.compact(key))\n\n- [ ] remote"
            )
            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .conflict }, "concurrent edits should surface a conflict")
            try expect(transport.requests.count == 1, "conflict must never PATCH remote content")
            try expect(fixture.model.document.items.first?.text == "local", "conflict must retain local content")
        },
        TestCase("a conflict can be resolved using Notion") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let key = fixture.model.dateKey
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("local row should exist")
            fixture.model.updateText(id: id, text: "local")
            fixture.model.flushSave()
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] base"))
            transport.responseData = try notionResponse(
                markdown: "\(DateKey.compact(key))\n\t- [ ] remote\n<empty-block/>"
            )

            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .conflict }, "fixture should enter conflict")
            fixture.model.resolveConflictUsingNotion()
            try expect(waitUntil { fixture.model.syncState == .synced }, "Notion resolution should finish")
            try expect(fixture.model.document.items.first?.text == "remote", "Notion resolution should replace the local day")
            try expect(transport.requests.map(\.httpMethod) == ["GET", "GET"], "Notion resolution should never PATCH remote content")
        },
        TestCase("a conflict can be resolved using local content") {
            let transport = StubTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let key = fixture.model.dateKey
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("local row should exist")
            fixture.model.updateText(id: id, text: "local winner")
            fixture.model.flushSave()
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] base"))
            transport.responseData = try notionResponse(
                markdown: "\(DateKey.compact(key))\n\t- [ ] remote\n<empty-block/>"
            )

            fixture.model.syncNow()
            try expect(waitUntil { fixture.model.syncState == .conflict }, "fixture should enter conflict")
            fixture.model.resolveConflictUsingLocal()
            try expect(waitUntil { fixture.model.syncState == .synced }, "local resolution should finish")
            try expect(transport.requests.map(\.httpMethod) == ["GET", "GET", "PATCH"], "local resolution should re-read before one PATCH")
            let patch = try transport.requests.last.unwrap("resolution PATCH should be sent")
            let body = try JSONSerialization.jsonObject(with: patch.httpBody ?? Data()) as? [String: Any]
            let replace = body?["replace_content"] as? [String: Any]
            try expect((replace?["new_str"] as? String)?.contains("local winner") == true, "local resolution should write the selected local day")
        },
        TestCase("truncated Notion pages fail safely before replacement") {
            let transport = StubTransport()
            transport.responseData = try notionResponse(markdown: "partial", truncated: true)
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            fixture.model.syncNow()
            try expect(waitUntil {
                if case .error = fixture.model.syncState { return true }
                return false
            }, "truncation should become an error")
            try expect(transport.requests.count == 1, "partial remote content must never be replaced")
            try expect(fixture.model.syncState.label.contains("页面过大"), "error should explain the safety stop")
        },
        TestCase("passive sync triggers do not queue redundant requests") {
            let transport = DelayedTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            fixture.model.syncNow()
            fixture.model.syncNow()
            try expect(transport.requests.count == 1, "an in-flight passive sync should not queue another GET")
            try transport.succeedNext(markdown: "")
            try expect(waitUntil { fixture.model.syncState == .synced }, "the original passive sync should finish")
            try expect(transport.requests.count == 1, "finishing a passive sync should not start a duplicate")
        },
        TestCase("edits requested during a sync trigger a follow-up sync") {
            let transport = DelayedTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            fixture.model.syncNow()
            try expect(transport.requests.count == 1, "first retrieve should be waiting")
            let id = try fixture.model.document.items.first.map(\.id).unwrap("new row should exist")
            fixture.model.updateText(id: id, text: "newer edit")
            fixture.model.syncNow(queueIfBusy: true)
            try transport.succeedNext(markdown: "")
            try expect(waitUntil { transport.requests.count == 2 }, "first sync should issue its PATCH")
            try transport.succeedNext(markdown: "")
            try expect(waitUntil { transport.requests.count == 3 }, "pending edit should start another retrieve")
        },
        TestCase("a remote pull cannot overwrite an edit made during the request") {
            let transport = DelayedTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("local row should exist")
            fixture.model.updateText(id: id, text: "base")
            fixture.model.flushSave()
            let key = fixture.model.dateKey
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] base"))

            fixture.model.syncNow()
            try expect(transport.requests.count == 1, "retrieve should be waiting")
            fixture.model.updateText(id: id, text: "正在输入")
            try transport.succeedNext(
                markdown: "\(DateKey.compact(key))\n\t- [ ] remote edit\n<empty-block/>"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            try expect(
                fixture.model.document.items.first?.text == "正在输入",
                "the response must not replace a newer local edit"
            )
        },
        TestCase("a remote pull waits until the active editor resigns") {
            let transport = DelayedTransport()
            let fixture = try appFixture(
                transport: transport,
                pageID: "12345678-90ab-cdef-1234-567890abcdef",
                token: "ntn_test"
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.model.addItem()
            let id = try fixture.model.document.items.first.map(\.id).unwrap("local row should exist")
            fixture.model.updateText(id: id, text: "base")
            fixture.model.flushSave()
            let key = fixture.model.dateKey
            try fixture.snapshotStore.save(SyncSnapshot(dateKey: key, baseMarkdown: "- [ ] base"))
            let remotePage = "\(DateKey.compact(key))\n\t- [ ] remote edit\n<empty-block/>"

            let controller = NSHostingController(rootView: ContentView(model: fixture.model))
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 440, height: 560))
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            controller.view.layoutSubtreeIfNeeded()
            let field = try allTextFields(in: controller.view)
                .first(where: { $0.stringValue == "base" })
                .unwrap("outline text field should be rendered")
            try expect(window.makeFirstResponder(field), "outline field should accept first responder")
            let editor = try (window.firstResponder as? NSTextView).unwrap("field editor should become first responder")

            fixture.model.syncNow()
            try transport.succeedNext(markdown: remotePage)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            try expect(window.firstResponder === editor, "a deferred pull must preserve editor focus")
            try expect(fixture.model.document.items.first?.text == "base", "a focused row must not be replaced")

            try expect(window.makeFirstResponder(nil), "the field editor should be able to resign")
            fixture.model.syncNow()
            try expect(waitUntil { transport.requests.count == 2 }, "sync should retry after editing ends")
            try transport.succeedNext(markdown: remotePage)
            try expect(waitUntil { fixture.model.syncState == .synced }, "the deferred pull should finish")
            try expect(fixture.model.document.items.first?.text == "remote edit", "remote content should apply after editing")
            window.close()
        }
    ]
}

#endif
