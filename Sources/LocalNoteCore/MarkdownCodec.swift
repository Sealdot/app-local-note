import Foundation

public enum MarkdownCodec {
    private static let escapable = CharacterSet(charactersIn: "\\*~`$[]<>{}|^")

    public static func encode(_ document: DayDocument) -> String {
        document.items.map(encode).joined(separator: "\n")
    }

    public static func decode(_ markdown: String, dateKey: String, now: Date = Date()) -> DayDocument {
        let lines = markdown.components(separatedBy: .newlines)
        let items = lines.compactMap { decodeLine($0, now: now) }
        return DayDocument(dateKey: dateKey, items: items, updatedAt: now)
    }

    public static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func encode(_ item: OutlineItem) -> String {
        let indent = String(repeating: "\t", count: max(0, item.depth))
        let prefix: String
        switch item.kind {
        case .checkbox:
            prefix = item.checked ? "- [x] " : "- [ ] "
        case .numbered:
            prefix = "1. "
        case .bullet:
            prefix = "- "
        case .text:
            prefix = ""
        }
        var escaped = escape(item.text)
        if item.kind == .text,
           escaped.range(of: #"^(?:-(?: |$)|\d+\.(?: |$))"#, options: .regularExpression) != nil {
            escaped = "\\" + escaped
        }
        let content = item.isStruck && !escaped.isEmpty ? "~~\(escaped)~~" : escaped
        return indent + prefix + content
    }

    private static func decodeLine(_ line: String, now: Date) -> OutlineItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "<empty-block/>" { return nil }
        let depth = line.prefix { $0 == "\t" }.count
        var content = String(line.dropFirst(depth))
        var kind = OutlineItemKind.text
        var checked = false

        if content == "- [ ]" {
            kind = .checkbox
            content = ""
        } else if content == "- [x]" || content == "- [X]" {
            kind = .checkbox
            checked = true
            content = ""
        } else if content.hasPrefix("- [ ] ") {
            kind = .checkbox
            content.removeFirst(6)
        } else if content.hasPrefix("- [x] ") || content.hasPrefix("- [X] ") {
            kind = .checkbox
            checked = true
            content.removeFirst(6)
        } else if let range = content.range(of: #"^\d+\.(?: |$)"#, options: .regularExpression) {
            kind = .numbered
            content.removeSubrange(range)
        } else if content == "-" || content.hasPrefix("- ") {
            kind = .bullet
            content = content == "-" ? "" : String(content.dropFirst(2))
        }

        var manualStrike = false
        if content.hasPrefix("~~"), content.hasSuffix("~~"), content.count >= 4 {
            content.removeFirst(2)
            content.removeLast(2)
            manualStrike = !checked
        }

        return OutlineItem(
            depth: min(depth, 12),
            kind: kind,
            text: unescape(content),
            checked: checked,
            manualStrikethrough: manualStrike,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            if escapable.contains(scalar) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }
}

public enum WorkLogMarkdown {
    public static func section(in pageMarkdown: String, dateKey: String) -> String {
        let lines = pageMarkdown.components(separatedBy: .newlines)
        guard let range = dayRange(in: lines, dateKey: dateKey) else { return "" }
        let bodyStart = range.lowerBound + 1
        guard bodyStart < range.upperBound else { return "" }
        let nestedUnderPlainDate = headingValue(lines[range.lowerBound]) == nil
        let body = lines[bodyStart..<range.upperBound].compactMap { line -> String? in
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "<empty-block/>" {
                return nil
            }
            if nestedUnderPlainDate, line.hasPrefix("\t") {
                return String(line.dropFirst())
            }
            return line
        }
        return normalize(body.joined(separator: "\n"))
    }

    public static func replacingSection(in pageMarkdown: String, dateKey: String, body: String) -> String {
        var lines = pageMarkdown.components(separatedBy: .newlines)
        let existingRange = dayRange(in: lines, dateKey: dateKey)
        let usesPlainDates: Bool
        let marker: String
        if let existingRange = existingRange {
            marker = lines[existingRange.lowerBound]
            usesPlainDates = headingValue(marker) == nil
        } else if let plainMarker = lines.first(where: { isPlainDateMarker($0) }) {
            marker = DateKey.compact(dateKey)
            usesPlainDates = headingValue(plainMarker) == nil
        } else {
            marker = "## \(DateKey.compact(dateKey))"
            usesPlainDates = false
        }

        let normalizedBody = normalize(body)
        var bodyLines = normalizedBody.isEmpty ? [] : normalizedBody.components(separatedBy: .newlines)
        if usesPlainDates {
            bodyLines = bodyLines.map { "\t" + $0 }
        }

        var replacement = usesPlainDates ? [marker] + bodyLines : [marker, ""] + bodyLines
        let hasFollowingContent = existingRange.map { $0.upperBound < lines.count }
            ?? !pageMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if usesPlainDates && hasFollowingContent {
            replacement.append("<empty-block/>")
        }

        if let range = existingRange {
            lines.replaceSubrange(range, with: replacement)
        } else {
            let prefix = replacement + (!usesPlainDates && hasFollowingContent ? [""] : [])
            lines.insert(contentsOf: prefix, at: 0)
        }
        return normalize(lines.joined(separator: "\n"))
    }

    private static func dayRange(in lines: [String], dateKey: String) -> Range<Int>? {
        let compact = DateKey.compact(dateKey)
        let dashed = dateKey
        guard let start = lines.firstIndex(where: { dateMarkerValue($0) == compact || dateMarkerValue($0) == dashed }) else {
            return nil
        }
        var end = lines.count
        if start + 1 < lines.count {
            for index in (start + 1)..<lines.count where isDateHeading(lines[index]) {
                end = index
                break
            }
        }
        return start..<end
    }

    private static func headingValue(_ line: String) -> String? {
        guard let range = line.range(of: #"^#{1,4}\s+"#, options: .regularExpression) else { return nil }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private static func dateMarkerValue(_ line: String) -> String? {
        if let heading = headingValue(line) { return heading }
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line == value && isDateValue(value) ? value : nil
    }

    private static func isPlainDateMarker(_ line: String) -> Bool {
        headingValue(line) == nil && dateMarkerValue(line) != nil
    }

    private static func isDateHeading(_ line: String) -> Bool {
        guard let value = dateMarkerValue(line) else { return false }
        return isDateValue(value)
    }

    private static func isDateValue(_ value: String) -> Bool {
        return value.range(of: #"^\d{8}$"#, options: .regularExpression) != nil
            || value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
