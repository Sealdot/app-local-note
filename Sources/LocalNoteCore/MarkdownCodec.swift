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
           escaped.range(of: #"^(?:- |\d+\. )"#, options: .regularExpression) != nil {
            escaped = "\\" + escaped
        }
        let content = item.isStruck && !escaped.isEmpty ? "~~\(escaped)~~" : escaped
        return indent + prefix + content
    }

    private static func decodeLine(_ line: String, now: Date) -> OutlineItem? {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let depth = line.prefix { $0 == "\t" }.count
        var content = String(line.dropFirst(depth))
        var kind = OutlineItemKind.text
        var checked = false

        if content.hasPrefix("- [ ] ") {
            kind = .checkbox
            content.removeFirst(6)
        } else if content.hasPrefix("- [x] ") || content.hasPrefix("- [X] ") {
            kind = .checkbox
            checked = true
            content.removeFirst(6)
        } else if content.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
            kind = .numbered
            if let range = content.range(of: #"^\d+\. "#, options: .regularExpression) {
                content.removeSubrange(range)
            }
        } else if content.hasPrefix("- ") {
            kind = .bullet
            content.removeFirst(2)
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
        return normalize(lines[bodyStart..<range.upperBound].joined(separator: "\n"))
    }

    public static func replacingSection(in pageMarkdown: String, dateKey: String, body: String) -> String {
        var lines = pageMarkdown.components(separatedBy: .newlines)
        let header = "## \(DateKey.compact(dateKey))"
        let bodyLines = normalize(body).isEmpty ? [] : normalize(body).components(separatedBy: .newlines)
        let replacement = [header, ""] + bodyLines

        if let range = dayRange(in: lines, dateKey: dateKey) {
            lines.replaceSubrange(range, with: replacement)
        } else {
            let prefix = replacement + (pageMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [""])
            lines.insert(contentsOf: prefix, at: 0)
        }
        return normalize(lines.joined(separator: "\n"))
    }

    private static func dayRange(in lines: [String], dateKey: String) -> Range<Int>? {
        let compact = DateKey.compact(dateKey)
        let dashed = dateKey
        guard let start = lines.firstIndex(where: { headingValue($0) == compact || headingValue($0) == dashed }) else {
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

    private static func isDateHeading(_ line: String) -> Bool {
        guard let value = headingValue(line) else { return false }
        return value.range(of: #"^\d{8}$"#, options: .regularExpression) != nil
            || value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
