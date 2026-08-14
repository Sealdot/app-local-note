import Foundation
import Network
import SwiftUI
#if canImport(LocalNoteCore)
import LocalNoteCore
#endif

enum AppSyncState: Equatable {
    case notConfigured
    case idle
    case saving
    case syncing
    case synced
    case conflict
    case error(String)

    var label: String {
        switch self {
        case .notConfigured: return "未配置 Notion"
        case .idle: return "仅本地"
        case .saving: return "正在保存…"
        case .syncing: return "正在同步…"
        case .synced: return "已同步"
        case .conflict: return "发现同步冲突"
        case let .error(message): return message
        }
    }
}

final class AppModel: ObservableObject {
    static let tokenAccount = "notion-token"
    static let pageIDDefaultsKey = "notionPageID"

    @Published private(set) var document: DayDocument
    @Published private(set) var dateKey: String
    @Published private(set) var syncState: AppSyncState
    @Published var notionPageID: String
    @Published var notionToken: String

    private let dayStore: DayStoring
    private let snapshotStore: SyncSnapshotStore
    private let secretStore: SecretStoring
    private let notionClient: NotionClient
    private let defaults: UserDefaults
    private var saveWorkItem: DispatchWorkItem?
    private var syncWorkItem: DispatchWorkItem?
    private var syncInFlight = false
    private var syncRequestedWhileInFlight = false
    private let networkMonitor: NWPathMonitor?
    private var networkWasAvailable = false

    init(
        dayStore: DayStoring,
        snapshotStore: SyncSnapshotStore,
        secretStore: SecretStoring,
        notionClient: NotionClient,
        defaults: UserDefaults = .standard,
        today: Date = Date(),
        monitorsNetwork: Bool = true
    ) {
        self.dayStore = dayStore
        self.snapshotStore = snapshotStore
        self.secretStore = secretStore
        self.notionClient = notionClient
        self.defaults = defaults
        networkMonitor = monitorsNetwork ? NWPathMonitor() : nil
        let key = DateKey.make(from: today)
        dateKey = key
        document = (try? dayStore.load(dateKey: key)) ?? DayDocument(dateKey: key)
        let storedPageID = defaults.string(forKey: Self.pageIDDefaultsKey) ?? ""
        let storedToken = (try? secretStore.read(account: Self.tokenAccount)) ?? ""
        notionPageID = storedPageID
        notionToken = storedToken
        syncState = storedPageID.isEmpty || storedToken.isEmpty ? .notConfigured : .idle
        if monitorsNetwork { startNetworkMonitor() }
    }

    convenience init() {
        do {
            try self.init(
                dayStore: FileDayStore(),
                snapshotStore: SyncSnapshotStore(),
                secretStore: KeychainSecretStore(),
                notionClient: NotionClient()
            )
        } catch {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("LocalNote", isDirectory: true)
            self.init(
                dayStore: FileDayStore(rootURL: temporary.appendingPathComponent("days", isDirectory: true)),
                snapshotStore: SyncSnapshotStore(rootURL: temporary.appendingPathComponent("sync", isDirectory: true)),
                secretStore: KeychainSecretStore(),
                notionClient: NotionClient()
            )
            syncState = .error("无法打开应用数据目录")
        }
    }

    deinit {
        networkMonitor?.cancel()
    }

    func itemBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.document.items.first(where: { $0.id == id })?.text ?? "" },
            set: { [weak self] value in self?.updateText(id: id, text: value) }
        )
    }

    func addItem() {
        mutate { document in
            _ = OutlineEditor.append(to: &document)
        }
    }

    func addPeer(after id: UUID) {
        mutate { document in
            _ = OutlineEditor.insertPeer(in: &document, after: id)
        }
    }

    func updateText(id: UUID, text: String) {
        mutate { OutlineEditor.updateText(in: &$0, id: id, text: text) }
    }

    func toggleCompletion(id: UUID) {
        mutate { OutlineEditor.toggleCompletion(in: &$0, id: id) }
    }

    func toggleStrike(id: UUID) {
        mutate { OutlineEditor.toggleManualStrike(in: &$0, id: id) }
    }

    func indent(id: UUID) {
        mutate { OutlineEditor.indent(in: &$0, id: id) }
    }

    func outdent(id: UUID) {
        mutate { OutlineEditor.outdent(in: &$0, id: id) }
    }

    func delete(id: UUID) {
        mutate { OutlineEditor.delete(in: &$0, id: id) }
    }

    func changeKind(id: UUID, kind: OutlineItemKind) {
        mutate { OutlineEditor.changeKind(in: &$0, id: id, kind: kind) }
    }

    func navigate(days: Int) {
        flushSave()
        guard let next = DateKey.adding(days: days, to: dateKey) else { return }
        load(dateKey: next)
    }

    func navigateToToday() {
        flushSave()
        load(dateKey: DateKey.make(from: Date()))
    }

    @discardableResult
    func saveSettings() -> Bool {
        let pageIDInput = notionPageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenInput = notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pageIDInput.isEmpty, NotionPageID.normalize(pageIDInput) == nil {
            syncState = .error("Notion 页面 ID 或 URL 无效")
            return false
        }
        let normalizedPageID = NotionPageID.normalize(pageIDInput) ?? ""
        notionPageID = normalizedPageID
        notionToken = tokenInput
        defaults.set(normalizedPageID, forKey: Self.pageIDDefaultsKey)
        do {
            if tokenInput.isEmpty {
                try secretStore.delete(account: Self.tokenAccount)
            } else {
                try secretStore.save(tokenInput, account: Self.tokenAccount)
            }
            syncState = normalizedPageID.isEmpty || tokenInput.isEmpty ? .notConfigured : .idle
            return true
        } catch {
            syncState = .error("无法保存 Notion Token")
            return false
        }
    }

    func syncNow(queueIfBusy: Bool = false) {
        syncWorkItem?.cancel()
        guard !syncInFlight else {
            if queueIfBusy { syncRequestedWhileInFlight = true }
            return
        }
        let pageID = notionPageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageID.isEmpty, !token.isEmpty else {
            syncState = .notConfigured
            return
        }

        flushSave()
        syncInFlight = true
        syncState = .syncing
        let currentDateKey = dateKey
        let localDocument = document
        let localMarkdown = MarkdownCodec.encode(localDocument)
        let storedBase = snapshotStore.load(dateKey: currentDateKey)?.baseMarkdown ?? ""
        let base = canonicalMarkdown(storedBase, dateKey: currentDateKey)

        notionClient.retrievePageMarkdown(pageID: pageID, token: token) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .failure(error):
                self.finishSync(state: .error(error.description))
            case let .success(fullPage):
                let remoteDay = WorkLogMarkdown.section(in: fullPage, dateKey: currentDateKey)
                let remoteMarkdown = self.canonicalMarkdown(remoteDay, dateKey: currentDateKey)
                switch SyncPlanner.decide(base: base, local: localMarkdown, remote: remoteMarkdown) {
                case .noChange:
                    self.persistSnapshot(dateKey: currentDateKey, markdown: localMarkdown)
                    self.finishSync(state: .synced)
                case .pull:
                    let pulled = MarkdownCodec.decode(remoteMarkdown, dateKey: currentDateKey)
                    do {
                        try self.dayStore.save(pulled)
                        self.persistSnapshot(dateKey: currentDateKey, markdown: remoteMarkdown)
                        DispatchQueue.main.async {
                            if self.dateKey == currentDateKey { self.document = pulled }
                            self.finishSync(state: .synced)
                        }
                    } catch {
                        self.finishSync(state: .error("同步内容无法保存到本地"))
                    }
                case .conflict:
                    self.finishSync(state: .conflict)
                case .push:
                    let updatedPage = WorkLogMarkdown.replacingSection(
                        in: fullPage,
                        dateKey: currentDateKey,
                        body: localMarkdown
                    )
                    self.notionClient.replacePageMarkdown(pageID: pageID, token: token, markdown: updatedPage) { replaceResult in
                        switch replaceResult {
                        case let .failure(error):
                            self.finishSync(state: .error(error.description))
                        case .success:
                            self.persistSnapshot(dateKey: currentDateKey, markdown: localMarkdown)
                            self.finishSync(state: .synced)
                        }
                    }
                }
            }
        }
    }

    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try dayStore.save(document)
            if syncState == .saving { syncState = .idle }
        } catch {
            syncState = .error("本地保存失败")
        }
    }

    func displayPrefix(for item: OutlineItem) -> String {
        switch item.kind {
        case .checkbox, .text: return ""
        case .bullet: return "•"
        case .numbered:
            guard let index = document.items.firstIndex(where: { $0.id == item.id }) else { return "1." }
            var number = 1
            if index > 0 {
                for previous in document.items[..<index].reversed() {
                    if previous.depth < item.depth { break }
                    if previous.depth == item.depth && previous.kind == .numbered { number += 1 }
                }
            }
            if item.depth == 2 { return alphabetic(number) + "." }
            if item.depth >= 3 { return roman(number).lowercased() + "." }
            return "\(number)."
        }
    }

    private func mutate(_ mutation: (inout DayDocument) -> Void) {
        var updated = document
        mutation(&updated)
        document = updated
        scheduleSave()
        scheduleSync()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        syncState = .saving
        let workItem = DispatchWorkItem { [weak self] in self?.flushSave() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func scheduleSync() {
        guard !notionPageID.isEmpty, !notionToken.isEmpty else { return }
        syncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.syncNow(queueIfBusy: true) }
        syncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func load(dateKey: String) {
        self.dateKey = dateKey
        do {
            document = try dayStore.load(dateKey: dateKey)
            syncState = notionPageID.isEmpty || notionToken.isEmpty ? .notConfigured : .idle
        } catch {
            document = DayDocument(dateKey: dateKey)
            syncState = .error("当天记录文件损坏，已停止覆盖")
        }
    }

    private func persistSnapshot(dateKey: String, markdown: String) {
        try? snapshotStore.save(SyncSnapshot(dateKey: dateKey, baseMarkdown: markdown))
    }

    private func canonicalMarkdown(_ markdown: String, dateKey: String) -> String {
        MarkdownCodec.encode(MarkdownCodec.decode(markdown, dateKey: dateKey))
    }

    private func finishSync(state: AppSyncState) {
        DispatchQueue.main.async {
            self.syncInFlight = false
            self.syncState = state
            if self.syncRequestedWhileInFlight {
                self.syncRequestedWhileInFlight = false
                self.syncNow()
            }
        }
    }

    private func startNetworkMonitor() {
        guard let networkMonitor = networkMonitor else { return }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let available = path.status == .satisfied
            if available && !self.networkWasAvailable {
                DispatchQueue.main.async { self.syncNow() }
            }
            self.networkWasAvailable = available
        }
        networkMonitor.start(queue: DispatchQueue(label: "dev.sealdot.LocalNote.network", qos: .utility))
    }

    private func alphabetic(_ value: Int) -> String {
        guard value > 0 else { return "a" }
        return String(UnicodeScalar(96 + min(value, 26))!)
    }

    private func roman(_ value: Int) -> String {
        let values = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var number = max(1, min(value, 20))
        var result = ""
        for pair in values {
            while number >= pair.0 {
                result += pair.1
                number -= pair.0
            }
        }
        return result
    }
}
