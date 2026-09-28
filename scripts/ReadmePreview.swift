import AppKit
import Foundation
import SwiftUI

private final class ReadmePreviewSecretStore: SecretStoring {
    func read(account: String) throws -> String? { nil }
    func save(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}

@main
private enum ReadmePreview {
    static func main() throws {
        let outputDirectory = CommandLine.arguments.dropFirst().first ?? "build/readme-media"
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let application = NSApplication.shared
        application.appearance = NSAppearance(named: .aqua)

        try render(outputDirectory: outputDirectory)
    }

    private static func render(outputDirectory: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNoteReadmePreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dayStore = FileDayStore(rootURL: root.appendingPathComponent("days", isDirectory: true))
        let dateKey = "2026-09-28"
        // Fictional workday, rendered by the production ContentView and AppModel.
        let sampleItems = [
            OutlineItem(kind: .checkbox, text: "准备周会", checked: true),
            OutlineItem(depth: 1, kind: .numbered, text: "整理上周进展", manualStrikethrough: true),
            OutlineItem(depth: 1, kind: .numbered, text: "列出本周优先事项"),
            OutlineItem(kind: .checkbox, text: "跟进反馈"),
            OutlineItem(depth: 1, kind: .numbered, text: "确认下一步安排"),
            OutlineItem(kind: .checkbox, text: "写下今天的复盘")
        ]
        try dayStore.save(DayDocument(dateKey: dateKey, items: sampleItems))

        let suiteName = "dev.sealdot.LocalNote.readme-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        AppearancePreferences(mode: .light, theme: .systemNative, accent: .blue).save(to: defaults)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = DateKey.date(from: dateKey, calendar: calendar)!
        let model = AppModel(
            dayStore: dayStore,
            snapshotStore: SyncSnapshotStore(rootURL: root.appendingPathComponent("sync", isDirectory: true)),
            secretStore: ReadmePreviewSecretStore(),
            notionClient: NotionClient(),
            defaults: defaults,
            today: date,
            monitorsNetwork: false
        )

        // Verify that a completion edit survives the same save/reload path used by the app.
        let editedID = sampleItems[0].id
        model.toggleCompletion(id: editedID)
        model.toggleCompletion(id: editedID)
        model.flushSave()
        model.navigate(days: -1)
        model.navigate(to: dateKey)
        guard MarkdownCodec.encode(model.document) == MarkdownCodec.encode(DayDocument(dateKey: dateKey, items: sampleItems)) else {
            throw NSError(domain: "ReadmePreview", code: 3)
        }
        print("Verified isolated completion/save/day-navigation: \(dateKey)")

        let controller = NSHostingController(
            rootView: ContentView(model: model)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 440, height: 560))
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        controller.view.layoutSubtreeIfNeeded()

        let bounds = controller.view.bounds
        guard let image = controller.view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw NSError(domain: "ReadmePreview", code: 1)
        }
        controller.view.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ReadmePreview", code: 2)
        }
        let output = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent("workday-light.png")
        try png.write(to: output, options: .atomic)
        print(output.path)
        window.close()
    }

}
