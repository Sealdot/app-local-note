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
            try expect(action(for: "c") == #selector(NSText.copy(_:)), "Command-C must route to the text responder")
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
            try sendKey(keyCode: 36, characters: "\r", to: editor, window: window)
            try expect(waitUntil { fixture.model.document.items.count == 3 }, "Return should add a peer row")
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
            try expect(transport.requests.count == 2, "first sync should issue its PATCH")
            try transport.succeedNext(markdown: "")
            try expect(waitUntil { transport.requests.count == 3 }, "pending edit should start another retrieve")
        }
    ]
}

#endif
