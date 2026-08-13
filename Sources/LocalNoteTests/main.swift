import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(LocalNoteCore)
import LocalNoteCore
#endif

enum TestFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value): return value
        }
    }
}

struct TestCase {
    let name: String
    let isPerformance: Bool
    let body: () throws -> Void

    init(_ name: String, performance: Bool = false, body: @escaping () throws -> Void) {
        self.name = name
        isPerformance = performance
        self.body = body
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.message(message) }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalNoteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

final class StubTransport: HTTPTransporting {
    var requests: [URLRequest] = []
    var responseData = Data()
    var statusCode = 200
    var headers: [String: String] = [:]
    var error: Error?

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        requests.append(request)
        if let error = error {
            completion(.failure(error))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        completion(.success((responseData, response)))
    }
}

let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

let tests: [TestCase] = [
    TestCase("new document and append") {
        var document = DayDocument(dateKey: "2026-08-13", updatedAt: fixedDate)
        let id = OutlineEditor.append(to: &document, now: fixedDate)
        try expect(document.items.count == 1, "append should add one row")
        try expect(document.items[0].id == id, "append should return the new ID")
        try expect(document.items[0].kind == .checkbox, "top-level rows default to checkbox")
    },
    TestCase("peer insertion skips child subtree") {
        let parent = OutlineItem(depth: 0, kind: .checkbox, text: "parent", createdAt: fixedDate, updatedAt: fixedDate)
        let child = OutlineItem(depth: 1, kind: .numbered, text: "child", createdAt: fixedDate, updatedAt: fixedDate)
        let next = OutlineItem(depth: 0, kind: .checkbox, text: "next", createdAt: fixedDate, updatedAt: fixedDate)
        var document = DayDocument(dateKey: "2026-08-13", items: [parent, child, next], updatedAt: fixedDate)
        _ = OutlineEditor.insertPeer(in: &document, after: parent.id, now: fixedDate)
        try expect(document.items.count == 4, "peer insertion should add a row")
        try expect(document.items[2].text.isEmpty, "peer should be inserted after descendants")
        try expect(document.items[2].depth == 0, "peer should preserve depth")
    },
    TestCase("indent and outdent move subtree") {
        let first = OutlineItem(depth: 0, text: "first", createdAt: fixedDate, updatedAt: fixedDate)
        let second = OutlineItem(depth: 0, text: "second", createdAt: fixedDate, updatedAt: fixedDate)
        let child = OutlineItem(depth: 1, text: "child", createdAt: fixedDate, updatedAt: fixedDate)
        var document = DayDocument(dateKey: "2026-08-13", items: [first, second, child], updatedAt: fixedDate)
        OutlineEditor.indent(in: &document, id: second.id, now: fixedDate)
        try expect(document.items.map { $0.depth } == [0, 1, 2], "indent should move the whole subtree")
        OutlineEditor.outdent(in: &document, id: second.id, now: fixedDate)
        try expect(document.items.map { $0.depth } == [0, 0, 1], "outdent should restore the subtree")
    },
    TestCase("delete removes descendants") {
        let parent = OutlineItem(depth: 0, text: "parent")
        let child = OutlineItem(depth: 1, text: "child")
        let grandchild = OutlineItem(depth: 2, text: "grandchild")
        let next = OutlineItem(depth: 0, text: "next")
        var document = DayDocument(dateKey: "2026-08-13", items: [parent, child, grandchild, next])
        OutlineEditor.delete(in: &document, id: parent.id)
        try expect(document.items == [next], "deleting a parent should remove descendants")
    },
    TestCase("completion and manual strike are independent") {
        let item = OutlineItem(kind: .checkbox, text: "task")
        var document = DayDocument(dateKey: "2026-08-13", items: [item])
        OutlineEditor.toggleManualStrike(in: &document, id: item.id)
        OutlineEditor.toggleCompletion(in: &document, id: item.id)
        OutlineEditor.toggleCompletion(in: &document, id: item.id)
        try expect(document.items[0].manualStrikethrough, "explicit strike should survive unchecking")
        try expect(document.items[0].isStruck, "explicitly struck item should remain struck")
    },
    TestCase("date keys follow the provided local calendar") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = Date(timeIntervalSince1970: 1_786_555_199)
        let key = DateKey.make(from: date, calendar: calendar)
        try expect(DateKey.isValid(key), "generated date key should be valid")
        try expect(DateKey.adding(days: 1, to: "2026-12-31", calendar: calendar) == "2027-01-01", "date addition should cross years")
    },
    TestCase("file store round-trip") {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDayStore(rootURL: root)
        let item = OutlineItem(depth: 1, kind: .numbered, text: "测试", createdAt: fixedDate, updatedAt: fixedDate)
        let document = DayDocument(dateKey: "2026-08-13", items: [item], updatedAt: fixedDate)
        try store.save(document)
        let loaded = try store.load(dateKey: document.dateKey)
        try expect(loaded == document, "saved document should load unchanged")
    },
    TestCase("missing and corrupt day files are distinct") {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDayStore(rootURL: root)
        let missing = try store.load(dateKey: "2026-08-13")
        try expect(missing.items.isEmpty, "missing file should return an empty day")
        try Data("not-json".utf8).write(to: try store.fileURL(dateKey: "2026-08-13"))
        do {
            _ = try store.load(dateKey: "2026-08-13")
            throw TestFailure.message("corrupt file should throw")
        } catch DayStoreError.corruptFile {
            // Expected.
        }
    },
    TestCase("older JSON tolerates optional fields") {
        let json = #"{"id":"F8245B35-0D9C-43D2-98DB-6B15D4CC7C88","text":"legacy"}"#
        let item = try JSONDecoder().decode(OutlineItem.self, from: Data(json.utf8))
        try expect(item.kind == .text, "legacy rows should default to text")
        try expect(item.depth == 0 && !item.checked, "legacy defaults should be safe")
    },
    TestCase("markdown round-trip preserves supported structure") {
        let items = [
            OutlineItem(depth: 0, kind: .checkbox, text: "一级", checked: true, createdAt: fixedDate, updatedAt: fixedDate),
            OutlineItem(depth: 1, kind: .numbered, text: "二级 *literal*", createdAt: fixedDate, updatedAt: fixedDate),
            OutlineItem(depth: 2, kind: .bullet, text: "三级", manualStrikethrough: true, createdAt: fixedDate, updatedAt: fixedDate),
            OutlineItem(depth: 0, kind: .text, text: "正文", createdAt: fixedDate, updatedAt: fixedDate)
        ]
        let document = DayDocument(dateKey: "2026-08-13", items: items, updatedAt: fixedDate)
        let markdown = MarkdownCodec.encode(document)
        let decoded = MarkdownCodec.decode(markdown, dateKey: document.dateKey, now: fixedDate)
        try expect(decoded.items.map { $0.depth } == items.map { $0.depth }, "depth should round-trip")
        try expect(decoded.items.map { $0.kind } == items.map { $0.kind }, "kind should round-trip")
        try expect(decoded.items.map { $0.text } == items.map { $0.text }, "text and escaping should round-trip")
        try expect(decoded.items[0].checked, "checked state should round-trip")
        try expect(decoded.items[2].manualStrikethrough, "manual strike should round-trip")
    },
    TestCase("work log section extraction and replacement") {
        let page = "## 20260813\n\n- [ ] old\n\n## 20260812\n\n- [x] history"
        try expect(WorkLogMarkdown.section(in: page, dateKey: "2026-08-13") == "- [ ] old", "current day should be extracted")
        let replaced = WorkLogMarkdown.replacingSection(in: page, dateKey: "2026-08-13", body: "- [x] new")
        try expect(WorkLogMarkdown.section(in: replaced, dateKey: "2026-08-13") == "- [x] new", "current day should be replaced")
        try expect(replaced.contains("- [x] history"), "other dates must remain intact")
        let inserted = WorkLogMarkdown.replacingSection(in: page, dateKey: "2026-08-14", body: "- [ ] newest")
        try expect(inserted.hasPrefix("## 20260814"), "new day should be inserted first")
    },
    TestCase("sync planner never silently overwrites concurrent edits") {
        try expect(SyncPlanner.decide(base: "a", local: "b", remote: "a") == .push, "local-only change should push")
        try expect(SyncPlanner.decide(base: "a", local: "a", remote: "b") == .pull, "remote-only change should pull")
        try expect(SyncPlanner.decide(base: "a", local: "b", remote: "c") == .conflict, "concurrent changes should conflict")
        try expect(SyncPlanner.decide(base: "a", local: "b", remote: "b") == .noChange, "equal sides need no write")
    },
    TestCase("Notion page IDs normalize from URLs") {
        let raw = "1234567890abcdef1234567890abcdef"
        let expected = "12345678-90ab-cdef-1234-567890abcdef"
        try expect(NotionPageID.normalize(raw) == expected, "raw ID should normalize")
        let url = "https://www.notion.so/Work-Record-\(raw)?pvs=4"
        try expect(NotionPageID.normalize(url) == expected, "URL ID should normalize without query contamination")
        try expect(NotionPageID.normalize("not-a-page") == nil, "invalid IDs should fail")
    },
    TestCase("Notion GET request is correct and redaction-safe") {
        let transport = StubTransport()
        transport.responseData = try JSONSerialization.data(withJSONObject: ["markdown": "hello"])
        let client = NotionClient(transport: transport, baseURL: URL(string: "https://example.test")!)
        var received: Result<String, NotionError>?
        client.retrievePageMarkdown(pageID: "1234567890abcdef1234567890abcdef", token: "secret-token") { received = $0 }
        let markdown = try received?.get()
        try expect(markdown == "hello", "client should parse markdown")
        let request = try transport.requests.first.unwrap("request should be sent")
        try expect(request.httpMethod == "GET", "retrieve should use GET")
        try expect(request.url?.path.hasSuffix("/markdown") == true, "retrieve path should target markdown")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token", "token should be in the authorization header")
        try expect(request.value(forHTTPHeaderField: "Notion-Version") == NotionClient.apiVersion, "API version should be explicit")
    },
    TestCase("Notion PATCH sends replace_content") {
        let transport = StubTransport()
        transport.responseData = try JSONSerialization.data(withJSONObject: ["markdown": "updated"])
        let client = NotionClient(transport: transport, baseURL: URL(string: "https://example.test")!)
        var received: Result<String, NotionError>?
        client.replacePageMarkdown(pageID: "1234567890abcdef1234567890abcdef", token: "token", markdown: "body") { received = $0 }
        let markdown = try received?.get()
        try expect(markdown == "updated", "client should parse update response")
        let request = try transport.requests.first.unwrap("request should be sent")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        try expect(request.httpMethod == "PATCH", "replace should use PATCH")
        try expect(body?["type"] as? String == "replace_content", "replace payload should use replace_content")
        let replacement = body?["replace_content"] as? [String: Any]
        try expect(replacement?["new_str"] as? String == "body", "replace payload should contain markdown")
    },
    TestCase("Notion API errors are actionable") {
        let transport = StubTransport()
        transport.statusCode = 429
        transport.headers = ["Retry-After": "4"]
        transport.responseData = Data()
        let client = NotionClient(transport: transport, baseURL: URL(string: "https://example.test")!)
        var received: Result<String, NotionError>?
        client.retrievePageMarkdown(pageID: "1234567890abcdef1234567890abcdef", token: "token") { received = $0 }
        guard case let .failure(error)? = received else { throw TestFailure.message("429 should fail") }
        try expect(error == .http(status: 429, retryAfter: 4), "Retry-After should be retained")
    },
    TestCase("common Notion HTTP failures remain distinguishable") {
        for status in [401, 403, 404, 409, 500, 503] {
            let transport = StubTransport()
            transport.statusCode = status
            let client = NotionClient(transport: transport, baseURL: URL(string: "https://example.test")!)
            var received: Result<String, NotionError>?
            client.retrievePageMarkdown(pageID: "1234567890abcdef1234567890abcdef", token: "token") { received = $0 }
            guard case let .failure(error)? = received else {
                throw TestFailure.message("HTTP \(status) should fail")
            }
            try expect(error == .http(status: status, retryAfter: nil), "HTTP \(status) should remain distinguishable")
        }
    },
    TestCase("Keychain round-trip uses an isolated test service") {
        let account = "test-\(UUID().uuidString)"
        let store = KeychainSecretStore(service: "dev.sealdot.LocalNote.tests.\(UUID().uuidString)")
        defer { try? store.delete(account: account) }
        try store.save("temporary-secret", account: account)
        let saved = try store.read(account: account)
        try expect(saved == "temporary-secret", "Keychain should return the saved secret")
        try store.delete(account: account)
        let deleted = try store.read(account: account)
        try expect(deleted == nil, "Keychain delete should remove the secret")
    },
    TestCase("ten years of history do not affect direct day loading", performance: true) {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDayStore(rootURL: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        for index in 0..<3650 {
            let url = root.appendingPathComponent("history-\(index).json")
            try Data("garbage".utf8).write(to: url)
        }
        let today = DayDocument(dateKey: "2026-08-13", items: [OutlineItem(text: "today")])
        try store.save(today)
        let start = Date()
        let loaded = try store.load(dateKey: today.dateKey)
        let elapsed = Date().timeIntervalSince(start)
        try expect(loaded.items.first?.text == "today", "today should load")
        try expect(elapsed < 1, "direct day load should not scan history")
    },
    TestCase("two thousand rows encode and decode linearly", performance: true) {
        let items = (0..<2000).map { index in
            OutlineItem(depth: min(index % 4, 3), kind: index % 5 == 0 ? .checkbox : .numbered, text: "row \(index)")
        }
        let document = DayDocument(dateKey: "2026-08-13", items: items)
        let start = Date()
        let markdown = MarkdownCodec.encode(document)
        let decoded = MarkdownCodec.decode(markdown, dateKey: document.dateKey)
        let elapsed = Date().timeIntervalSince(start)
        try expect(decoded.items.count == 2000, "all rows should round-trip")
        try expect(elapsed < 2, "2,000 rows should complete within smoke-test budget")
    }
]

extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw TestFailure.message(message) }
        return value
    }
}

let performanceOnly = CommandLine.arguments.contains("--performance")
let selected = performanceOnly ? tests.filter { $0.isPerformance } : tests
var failures = 0
let suiteStart = Date()

for test in selected {
    do {
        try test.body()
        print("✓ \(test.name)")
    } catch {
        failures += 1
        print("✗ \(test.name): \(error)")
    }
}

let elapsed = String(format: "%.3f", Date().timeIntervalSince(suiteStart))
print("\n\(selected.count - failures)/\(selected.count) tests passed in \(elapsed)s")
if failures > 0 { exit(1) }
