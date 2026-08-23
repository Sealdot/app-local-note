import AppKit
import Foundation
import SwiftUI

private final class ThemePreviewSecretStore: SecretStoring {
    func read(account: String) throws -> String? { nil }
    func save(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}

private enum PreviewSurface {
    case settings
    case outline
    case calendar
}

@main
private enum ThemePreview {
    static func main() throws {
        let outputDirectory = CommandLine.arguments.dropFirst().first ?? "build/theme-qa"
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let application = NSApplication.shared
        application.appearance = NSAppearance(named: .aqua)

        try render(
            name: "01-settings-system-light",
            surface: .settings,
            preferences: AppearancePreferences(mode: .system, theme: .systemNative, accent: .blue),
            outputDirectory: outputDirectory
        )
        try render(
            name: "02-outline-midnight-dark",
            surface: .outline,
            preferences: AppearancePreferences(mode: .dark, theme: .midnight, accent: .purple),
            outputDirectory: outputDirectory
        )
        try render(
            name: "03-calendar-paper-light",
            surface: .calendar,
            preferences: AppearancePreferences(mode: .light, theme: .paper, accent: .green),
            outputDirectory: outputDirectory
        )
        try render(
            name: "04-settings-midnight-dark",
            surface: .settings,
            preferences: AppearancePreferences(mode: .dark, theme: .midnight, accent: .purple),
            outputDirectory: outputDirectory
        )
    }

    private static func render(
        name: String,
        surface: PreviewSurface,
        preferences: AppearancePreferences,
        outputDirectory: String
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNoteThemePreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dayStore = FileDayStore(rootURL: root.appendingPathComponent("days", isDirectory: true))
        let dateKey = "2026-08-19"
        let sampleItems = [
            OutlineItem(kind: .checkbox, text: "今日优先事项"),
            OutlineItem(depth: 1, kind: .numbered, text: "整理本周工作记录", manualStrikethrough: true),
            OutlineItem(depth: 1, kind: .numbered, text: "确认明天的安排"),
            OutlineItem(kind: .checkbox, text: "数据复盘", checked: true),
            OutlineItem(depth: 1, kind: .numbered, text: "完成趋势检查", manualStrikethrough: true),
            OutlineItem(kind: .checkbox, text: "其他事项")
        ]
        try dayStore.save(DayDocument(dateKey: dateKey, items: sampleItems))
        try saveCalendarSamples(to: dayStore)

        let suiteName = "dev.sealdot.LocalNote.theme-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        preferences.save(to: defaults)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = DateKey.date(from: dateKey, calendar: calendar)!
        let model = AppModel(
            dayStore: dayStore,
            snapshotStore: SyncSnapshotStore(rootURL: root.appendingPathComponent("sync", isDirectory: true)),
            secretStore: ThemePreviewSecretStore(),
            notionClient: NotionClient(),
            defaults: defaults,
            today: date,
            monitorsNetwork: false
        )

        let controller = NSHostingController(
            rootView: ContentView(
                model: model,
                initiallyShowingSettings: surface == .settings,
                initiallyShowingCalendar: surface == .calendar
            )
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
            throw NSError(domain: "ThemePreview", code: 1)
        }
        controller.view.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ThemePreview", code: 2)
        }
        let output = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        try png.write(to: output, options: .atomic)
        print(output.path)
        window.close()
    }

    private static func saveCalendarSamples(to store: FileDayStore) throws {
        let samples: [(String, Int, Int)] = [
            ("2026-08-03", 0, 2), ("2026-08-05", 1, 1),
            ("2026-08-10", 2, 3), ("2026-08-14", 4, 5),
            ("2026-08-18", 7, 8), ("2026-08-24", 1, 4),
            ("2026-08-28", 6, 7)
        ]
        for (dateKey, completed, total) in samples {
            let items = (0..<total).map { index in
                OutlineItem(kind: .checkbox, text: "示例待办 \(index + 1)", checked: index < completed)
            }
            try store.save(DayDocument(dateKey: dateKey, items: items))
        }
    }
}
