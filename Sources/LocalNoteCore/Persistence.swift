import Foundation

public enum DayStoreError: Error, Equatable {
    case invalidDateKey
    case corruptFile(String)
}

public protocol DayStoring {
    func load(dateKey: String) throws -> DayDocument
    func save(_ document: DayDocument) throws
}

public final class FileDayStore: DayStoring {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(rootURL: support.appendingPathComponent("LocalNote/days", isDirectory: true), fileManager: fileManager)
    }

    public func load(dateKey: String) throws -> DayDocument {
        let url = try fileURL(dateKey: dateKey)
        guard fileManager.fileExists(atPath: url.path) else {
            return DayDocument(dateKey: dateKey)
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try decoder.decode(DayDocument.self, from: data)
        } catch {
            throw DayStoreError.corruptFile(url.path)
        }
    }

    public func save(_ document: DayDocument) throws {
        let url = try fileURL(dateKey: document.dateKey)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    public func fileURL(dateKey: String) throws -> URL {
        guard DateKey.isValid(dateKey) else { throw DayStoreError.invalidDateKey }
        return rootURL.appendingPathComponent(dateKey).appendingPathExtension("json")
    }
}

public struct SyncSnapshot: Codable, Equatable {
    public var dateKey: String
    public var baseMarkdown: String
    public var updatedAt: Date

    public init(dateKey: String, baseMarkdown: String, updatedAt: Date = Date()) {
        self.dateKey = dateKey
        self.baseMarkdown = baseMarkdown
        self.updatedAt = updatedAt
    }
}

public final class SyncSnapshotStore {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(rootURL: support.appendingPathComponent("LocalNote/sync", isDirectory: true), fileManager: fileManager)
    }

    public func load(dateKey: String) -> SyncSnapshot? {
        guard DateKey.isValid(dateKey) else { return nil }
        let url = rootURL.appendingPathComponent(dateKey).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return try? decoder.decode(SyncSnapshot.self, from: data)
    }

    public func save(_ snapshot: SyncSnapshot) throws {
        guard DateKey.isValid(snapshot.dateKey) else { throw DayStoreError.invalidDateKey }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        let url = rootURL.appendingPathComponent(snapshot.dateKey).appendingPathExtension("json")
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

