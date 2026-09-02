import Foundation

public enum OutlineItemKind: String, Codable, CaseIterable {
    case checkbox
    case numbered
    case bullet
    case text
}

public struct OutlineItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var depth: Int
    public var kind: OutlineItemKind
    public var text: String
    public var checked: Bool
    public var manualStrikethrough: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public var isStruck: Bool {
        checked || manualStrikethrough
    }

    public init(
        id: UUID = UUID(),
        depth: Int = 0,
        kind: OutlineItemKind = .checkbox,
        text: String = "",
        checked: Bool = false,
        manualStrikethrough: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.depth = max(0, depth)
        self.kind = kind
        self.text = text
        self.checked = checked
        self.manualStrikethrough = manualStrikethrough
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, depth, kind, text, checked, manualStrikethrough, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        depth = max(0, try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0)
        kind = try container.decodeIfPresent(OutlineItemKind.self, forKey: .kind) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        manualStrikethrough = try container.decodeIfPresent(Bool.self, forKey: .manualStrikethrough) ?? false
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = decodedCreatedAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedCreatedAt
    }
}

public struct DayDocument: Codable, Equatable {
    public var dateKey: String
    public var items: [OutlineItem]
    public var updatedAt: Date

    public init(dateKey: String, items: [OutlineItem] = [], updatedAt: Date = Date()) {
        self.dateKey = dateKey
        self.items = items
        self.updatedAt = updatedAt
    }
}

public struct DayActivitySummary: Equatable {
    public let dateKey: String
    public let totalTodos: Int
    public let completedTodos: Int

    public var hasTodos: Bool {
        totalTodos > 0
    }

    /// GitHub-contribution-style activity level. Zero means no to-dos; level
    /// one marks an active day with no completed to-dos; higher levels reflect
    /// absolute completed counts so productive days remain visually distinct.
    public var intensityLevel: Int {
        guard hasTodos else { return 0 }
        switch completedTodos {
        case 0: return 1
        case 1: return 2
        case 2...3: return 3
        case 4...6: return 4
        default: return 5
        }
    }

    public init(document: DayDocument) {
        let todos = document.items.filter {
            $0.kind == .checkbox && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        dateKey = document.dateKey
        totalTodos = todos.count
        completedTodos = todos.filter(\.checked).count
    }
}

public enum OutlineTypingShortcut {
    /// Recognizes the marker typed at the beginning of an empty outline row.
    /// The trailing space is intentional: it lets users enter a literal number
    /// and period without unexpectedly changing the row type.
    public static func kind(for text: String) -> OutlineItemKind? {
        guard text.last == " " else { return nil }
        let marker = text.dropLast()
        guard marker.count >= 2, marker.last == "." || marker.last == ")" else { return nil }
        return Int(marker.dropLast()) == nil ? nil : .numbered
    }
}

public enum OutlineEditor {
    public static func append(
        to document: inout DayDocument,
        kind: OutlineItemKind = .checkbox,
        depth: Int = 0,
        now: Date = Date()
    ) -> UUID {
        let maximumDepth = document.items.last.map { $0.depth + 1 } ?? 0
        let item = OutlineItem(depth: min(max(0, depth), maximumDepth), kind: kind, createdAt: now, updatedAt: now)
        document.items.append(item)
        document.updatedAt = now
        synchronizeParentCompletions(
            in: &document,
            parentIDs: checkboxAncestorIDs(in: document.items, ofItemAt: document.items.count - 1),
            now: now
        )
        return item.id
    }

    public static func insertPeer(
        in document: inout DayDocument,
        after id: UUID,
        now: Date = Date()
    ) -> UUID? {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return nil }
        let rootDepth = document.items[index].depth
        var insertionIndex = index + 1
        while insertionIndex < document.items.count && document.items[insertionIndex].depth > rootDepth {
            insertionIndex += 1
        }
        let item = OutlineItem(
            depth: rootDepth,
            kind: document.items[index].kind,
            createdAt: now,
            updatedAt: now
        )
        document.items.insert(item, at: insertionIndex)
        document.updatedAt = now
        synchronizeParentCompletions(
            in: &document,
            parentIDs: checkboxAncestorIDs(in: document.items, ofItemAt: insertionIndex),
            now: now
        )
        return item.id
    }

    /// Splits an item at the field editor's UTF-16 selection. The right-hand
    /// item is inserted immediately after the edited row so any existing
    /// descendants continue to follow the text that was moved to that row.
    public static func splitItem(
        in document: inout DayDocument,
        id: UUID,
        replacingUTF16Range selection: NSRange,
        now: Date = Date()
    ) -> UUID? {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return nil }
        let original = document.items[index]
        let text = original.text as NSString
        let location = min(max(0, selection.location), text.length)
        let length = min(max(0, selection.length), text.length - location)
        let prefix = text.substring(to: location)
        let suffix = text.substring(from: location + length)

        document.items[index].text = prefix
        document.items[index].updatedAt = now
        let item = OutlineItem(
            depth: original.depth,
            kind: original.kind,
            text: suffix,
            createdAt: now,
            updatedAt: now
        )
        document.items.insert(item, at: index + 1)
        document.updatedAt = now
        var parentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index + 1)
        if item.kind == .checkbox { parentIDs.append(item.id) }
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
        return item.id
    }

    public static func updateText(
        in document: inout DayDocument,
        id: UUID,
        text: String,
        now: Date = Date()
    ) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        document.items[index].text = text
        document.items[index].updatedAt = now
        document.updatedAt = now
    }

    public static func toggleCompletion(in document: inout DayDocument, id: UUID, now: Date = Date()) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let parentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        document.items[index].checked.toggle()
        document.items[index].updatedAt = now
        document.updatedAt = now
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
    }

    public static func toggleManualStrike(in document: inout DayDocument, id: UUID, now: Date = Date()) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let parentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        document.items[index].manualStrikethrough.toggle()
        document.items[index].updatedAt = now
        document.updatedAt = now
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
    }

    public static func setManualStrike(
        in document: inout DayDocument,
        ids: Set<UUID>,
        enabled: Bool,
        now: Date = Date()
    ) {
        let indices = document.items.indices.filter { ids.contains(document.items[$0].id) }
        guard indices.contains(where: { document.items[$0].manualStrikethrough != enabled }) else { return }

        let parentIDs = indices.flatMap { checkboxAncestorIDs(in: document.items, ofItemAt: $0) }
        for index in indices where document.items[index].manualStrikethrough != enabled {
            document.items[index].manualStrikethrough = enabled
            document.items[index].updatedAt = now
        }
        document.updatedAt = now
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
    }

    public static func changeKind(
        in document: inout DayDocument,
        id: UUID,
        kind: OutlineItemKind,
        now: Date = Date()
    ) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        var parentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        document.items[index].kind = kind
        if kind != .checkbox {
            document.items[index].checked = false
        } else {
            parentIDs.append(id)
        }
        document.items[index].updatedAt = now
        document.updatedAt = now
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
    }

    public static func indent(in document: inout DayDocument, id: UUID, now: Date = Date()) {
        guard let index = document.items.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let previousParentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        let allowedDepth = document.items[index - 1].depth + 1
        let newDepth = min(document.items[index].depth + 1, allowedDepth)
        guard newDepth != document.items[index].depth else { return }
        shiftSubtree(in: &document, rootIndex: index, delta: 1, now: now)
        let newParentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        synchronizeParentCompletions(
            in: &document,
            parentIDs: previousParentIDs + newParentIDs,
            now: now
        )
    }

    public static func outdent(in document: inout DayDocument, id: UUID, now: Date = Date()) {
        guard let index = document.items.firstIndex(where: { $0.id == id }), document.items[index].depth > 0 else { return }
        let previousParentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        shiftSubtree(in: &document, rootIndex: index, delta: -1, now: now)
        let newParentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        synchronizeParentCompletions(
            in: &document,
            parentIDs: previousParentIDs + newParentIDs,
            now: now
        )
    }

    public static func delete(in document: inout DayDocument, id: UUID, now: Date = Date()) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let parentIDs = checkboxAncestorIDs(in: document.items, ofItemAt: index)
        let rootDepth = document.items[index].depth
        var end = index + 1
        while end < document.items.count && document.items[end].depth > rootDepth {
            end += 1
        }
        document.items.removeSubrange(index..<end)
        document.updatedAt = now
        synchronizeParentCompletions(in: &document, parentIDs: parentIDs, now: now)
    }

    /// Keeps checkbox parents derived from the completion state of their
    /// descendants. A parent with no descendants remains manually controlled.
    private static func synchronizeParentCompletions(
        in document: inout DayDocument,
        parentIDs: [UUID],
        now: Date
    ) {
        let parentIndices = Set(parentIDs).compactMap { id in
            document.items.firstIndex(where: { $0.id == id })
        }.sorted(by: >)

        for parentIndex in parentIndices where document.items[parentIndex].kind == .checkbox {
            let parentDepth = document.items[parentIndex].depth
            var end = parentIndex + 1
            while end < document.items.count && document.items[end].depth > parentDepth {
                end += 1
            }
            guard end > parentIndex + 1 else { continue }

            let allChildrenCompleted = document.items[(parentIndex + 1)..<end].allSatisfy(\.isStruck)
            guard document.items[parentIndex].checked != allChildrenCompleted else { continue }
            document.items[parentIndex].checked = allChildrenCompleted
            document.items[parentIndex].updatedAt = now
            document.updatedAt = now
        }
    }

    private static func checkboxAncestorIDs(in items: [OutlineItem], ofItemAt index: Int) -> [UUID] {
        guard items.indices.contains(index), items[index].depth > 0 else { return [] }
        var ancestorIDs: [UUID] = []
        var descendantDepth = items[index].depth

        for candidateIndex in stride(from: index - 1, through: 0, by: -1) {
            let candidate = items[candidateIndex]
            guard candidate.depth < descendantDepth else { continue }
            descendantDepth = candidate.depth
            if candidate.kind == .checkbox {
                ancestorIDs.append(candidate.id)
            }
            if descendantDepth == 0 { break }
        }
        return ancestorIDs
    }

    private static func shiftSubtree(
        in document: inout DayDocument,
        rootIndex: Int,
        delta: Int,
        now: Date
    ) {
        let rootDepth = document.items[rootIndex].depth
        var end = rootIndex + 1
        while end < document.items.count && document.items[end].depth > rootDepth {
            end += 1
        }
        for index in rootIndex..<end {
            document.items[index].depth = max(0, document.items[index].depth + delta)
            document.items[index].updatedAt = now
        }
        document.updatedAt = now
    }
}
