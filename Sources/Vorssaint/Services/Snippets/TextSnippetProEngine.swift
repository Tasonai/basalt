// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Argument placeholder specification extracted from `{{arg:name=default}}` or `{{choice:Label|Opt1|Opt2}}` tokens.
struct TextSnippetArgumentField: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let defaultValue: String
    let options: [String]

    init(id: String? = nil, name: String, defaultValue: String = "", options: [String] = []) {
        self.id = id ?? name
        self.name = name
        self.defaultValue = defaultValue
        self.options = options
    }
}

/// Portable snippet item serialized inside `.vorssaintsnippets` export packs.
struct SnippetPackItem: Codable, Equatable, Sendable {
    let trigger: String
    let title: String
    let content: String

    init(trigger: String, title: String, content: String) {
        self.trigger = trigger
        self.title = title
        self.content = content
    }
}

/// Shareable `.vorssaintsnippets` JSON pack container (Snippets 3.0).
struct SnippetExportPack: Codable, Equatable, Sendable {
    let version: Int
    let snippets: [SnippetPackItem]

    init(version: Int = 1, snippets: [SnippetPackItem]) {
        self.version = version
        self.snippets = snippets
    }
}

/// Output of expanding a Snippets 2.0 template including final caret rewind offset and rich-text styling.
struct TextSnippetExpansionResult: Equatable {
    let text: String
    let cursorMoveBackUTF16: Int
    let cursorMoveBackCharacters: Int
    let containsMarkdownFormatting: Bool
    let markdownRTFAttributed: NSAttributedString?

    init(text: String,
         cursorMoveBackUTF16: Int,
         cursorMoveBackCharacters: Int? = nil,
         containsMarkdownFormatting: Bool,
         markdownRTFAttributed: NSAttributedString?) {
        self.text = text
        self.cursorMoveBackUTF16 = cursorMoveBackUTF16
        self.cursorMoveBackCharacters = cursorMoveBackCharacters ?? cursorMoveBackUTF16
        self.containsMarkdownFormatting = containsMarkdownFormatting
        self.markdownRTFAttributed = markdownRTFAttributed
    }
}

/// Snippets 2.0 engine: `{{cursor}}` caret placement, `{{arg:name=default}}` form tokens,
/// date/time arithmetic (`{{date+7d:yyyy-MM-dd}}`), cycle-safe nested `{{snippet:...}}`, and RTF styling.
enum TextSnippetProEngine {
    static let cursorMarker = "{{cursor}}"
    static let maxRecursionDepth = 8
    static let maxTemplateDepth = 5
    private static let argumentPattern = #"\{\{arg:([A-Za-z0-9_.\-]+)(?:=([^{}]*))?\}\}"#
    private static let choicePattern = #"\{\{choice:([^{}]+)\}\}"#

    /// Extracts deduplicated `{{arg:name=default}}` and `{{choice:Label|Opt1|Opt2}}` fields in appearance order.
    static func extractArgumentSpecs(from template: String) -> [TextSnippetArgumentField] {
        var located: [(location: Int, field: TextSnippetArgumentField)] = []
        let nsRange = NSRange(template.startIndex..<template.endIndex, in: template)

        if template.contains("{{arg:"),
           let regex = try? NSRegularExpression(pattern: argumentPattern) {
            for match in regex.matches(in: template, range: nsRange) {
                guard let nameRange = Range(match.range(at: 1), in: template) else { continue }
                let name = String(template[nameRange])
                let defaultValue: String
                if match.range(at: 2).location != NSNotFound,
                   let defRange = Range(match.range(at: 2), in: template) {
                    defaultValue = String(template[defRange])
                } else {
                    defaultValue = ""
                }
                located.append((
                    match.range.location,
                    TextSnippetArgumentField(id: name, name: name, defaultValue: defaultValue)
                ))
            }
        }

        if template.contains("{{choice:"),
           let regex = try? NSRegularExpression(pattern: choicePattern) {
            for match in regex.matches(in: template, range: nsRange) {
                guard let bodyRange = Range(match.range(at: 1), in: template),
                      let parsed = parseChoiceBody(String(template[bodyRange])) else { continue }
                located.append((
                    match.range.location,
                    TextSnippetArgumentField(
                        id: parsed.label,
                        name: parsed.label,
                        defaultValue: parsed.options.first ?? "",
                        options: parsed.options
                    )
                ))
            }
        }

        located.sort { $0.location < $1.location }
        var seen = Set<String>()
        var fields: [TextSnippetArgumentField] = []
        for entry in located {
            guard seen.insert(entry.field.name).inserted else { continue }
            fields.append(entry.field)
        }
        return fields
    }

    private static func parseChoiceBody(_ body: String) -> (label: String, options: [String])? {
        let parts = body
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let rawLabel = parts.first, !rawLabel.isEmpty else { return nil }
        let options = parts.dropFirst().filter { !$0.isEmpty }
        guard !options.isEmpty else { return nil }
        return (rawLabel, options)
    }

    /// Expands Snippets 3.0 templates: nested `{{snippet:...}}` (cycle-safe, maxDepth 5),
    /// `{{choice: Label | Opt1 | Opt2}}` dropdowns, and deterministic date arithmetic.
    static func resolveAdvancedTemplate(
        _ template: String,
        choiceSelections: [String: String],
        snippetsByTrigger: [String: String],
        referenceDate: Date = Date(),
        depth: Int = 0
    ) -> String {
        var visited = Set<String>()
        return resolveAdvancedTemplateInternal(
            template,
            choiceSelections: choiceSelections,
            snippetsByTrigger: snippetsByTrigger,
            referenceDate: referenceDate,
            depth: depth,
            visited: &visited
        )
    }

    private static func resolveAdvancedTemplateInternal(
        _ template: String,
        choiceSelections: [String: String],
        snippetsByTrigger: [String: String],
        referenceDate: Date,
        depth: Int,
        visited: inout Set<String>
    ) -> String {
        var expanded = resolveNestedSnippets(
            template,
            lookup: { snippetsByTrigger[$0] },
            visited: &visited,
            depth: depth,
            maxDepth: maxTemplateDepth
        )
        expanded = resolveChoices(in: expanded, selections: choiceSelections)
        let utc = TimeZone(secondsFromGMT: 0)!
        let posixLocale = Locale(identifier: "en_US_POSIX")
        expanded = resolveDateArithmetic(in: expanded, baseDate: referenceDate, locale: posixLocale, timeZone: utc)
        expanded = expandBaseDateTokens(expanded, date: referenceDate, locale: posixLocale, timeZone: utc)
        return expanded
    }

    static func expandAdvanced(
        _ template: String,
        date: Date = Date(),
        clipboard: String? = nil,
        locale: Locale = .current,
        arguments: [String: String] = [:],
        snippetLookup: ((String) -> String?)? = nil
    ) -> TextSnippetExpansionResult {
        var visited = Set<String>()
        var expanded = resolveNestedSnippets(template,
                                             lookup: snippetLookup,
                                             visited: &visited,
                                             depth: 0)
        expanded = resolveArguments(in: expanded, values: arguments)
        expanded = resolveChoices(in: expanded, selections: arguments)
        expanded = resolveDateArithmetic(in: expanded, baseDate: date, locale: locale)

        // Replace basic {{date}} / {{time}} / {{datetime}} / {{date:...}} / {{date-tz(...):...}} before clipboard injection.
        expanded = expandBaseDateTokens(expanded, date: date, locale: locale)

        // Resolve {{cursor}} against final text, inserting clipboard after cursor computation if needed.
        // We replace {{clipboard}} right before stripping {{cursor}} so lengths after {{cursor}} are exact,
        // and we guard clipboard content from re-expanding tokens because all token passes have already finished.
        let withClipboard = expanded.replacingOccurrences(of: "{{clipboard}}", with: clipboard ?? "")

        let finalText: String
        let suffixText: String
        let moveBackUTF16: Int
        if let cursorRange = withClipboard.range(of: cursorMarker) {
            let prefix = String(withClipboard[..<cursorRange.lowerBound])
            let suffix = String(withClipboard[cursorRange.upperBound...])
                .replacingOccurrences(of: cursorMarker, with: "")
            finalText = prefix + suffix
            suffixText = suffix
            moveBackUTF16 = suffix.utf16.count
        } else {
            finalText = withClipboard
            suffixText = ""
            moveBackUTF16 = 0
        }

        let hasMarkdown = containsMarkdownSyntax(finalText)
        let attributed = hasMarkdown ? renderMarkdownAttributedString(finalText) : nil
        let moveBackCharacters: Int
        if suffixText.isEmpty {
            moveBackCharacters = 0
        } else if hasMarkdown {
            moveBackCharacters = renderMarkdownAttributedString(suffixText).string.count
        } else {
            moveBackCharacters = suffixText.count
        }

        return TextSnippetExpansionResult(
            text: finalText,
            cursorMoveBackUTF16: moveBackUTF16,
            cursorMoveBackCharacters: moveBackCharacters,
            containsMarkdownFormatting: hasMarkdown,
            markdownRTFAttributed: attributed
        )
    }

    static func resolveNestedSnippets(
        _ input: String,
        lookup: ((String) -> String?)?,
        visited: inout Set<String>,
        depth: Int,
        maxDepth: Int = maxRecursionDepth
    ) -> String {
        guard let lookup, depth < maxDepth, input.contains("{{snippet:") else {
            return stripRemainingSnippetTokensIfCycle(input)
        }
        guard let regex = try? NSRegularExpression(pattern: #"\{\{snippet:([^{}]+)\}\}"#) else {
            return input
        }
        var output = input
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, range: nsRange).reversed()
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: output),
                  let triggerRange = Range(match.range(at: 1), in: output) else { continue }
            let trigger = String(output[triggerRange]).trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty, !visited.contains(trigger), let body = lookup(trigger) else {
                output.replaceSubrange(fullRange, with: "")
                continue
            }
            visited.insert(trigger)
            let nested = resolveNestedSnippets(body, lookup: lookup, visited: &visited, depth: depth + 1, maxDepth: maxDepth)
            visited.remove(trigger)
            output.replaceSubrange(fullRange, with: nested)
        }
        return output
    }

    private static func stripRemainingSnippetTokensIfCycle(_ text: String) -> String {
        guard text.contains("{{snippet:") else { return text }
        return text.replacingOccurrences(of: #"\{\{snippet:[^{}]+\}\}"#, with: "", options: .regularExpression)
    }

    static func resolveArguments(in text: String, values: [String: String]) -> String {
        guard text.contains("{{arg:"),
              let regex = try? NSRegularExpression(pattern: #"\{\{arg:([A-Za-z0-9_.\-]+)(?:=([^{}]*))?\}\}"#) else {
            return text
        }
        var output = text
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in regex.matches(in: output, range: nsRange).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let nameRange = Range(match.range(at: 1), in: output) else { continue }
            let name = String(output[nameRange])
            let defaultValue: String
            if match.range(at: 2).location != NSNotFound,
               let defRange = Range(match.range(at: 2), in: output) {
                defaultValue = String(output[defRange])
            } else {
                defaultValue = ""
            }
            let resolved = values[name] ?? defaultValue
            output.replaceSubrange(fullRange, with: resolved)
        }
        return output
    }

    static func resolveChoices(in text: String, selections: [String: String]) -> String {
        guard text.contains("{{choice:"),
              let regex = try? NSRegularExpression(pattern: choicePattern) else {
            return text
        }
        var output = text
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in regex.matches(in: output, range: nsRange).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let bodyRange = Range(match.range(at: 1), in: output),
                  let parsed = parseChoiceBody(String(output[bodyRange])) else { continue }
            let resolved = selections[parsed.label] ?? parsed.options.first ?? ""
            output.replaceSubrange(fullRange, with: resolved)
        }
        return output
    }

    static func resolveDateArithmetic(in text: String, baseDate: Date, locale: Locale, timeZone: TimeZone? = nil) -> String {
        guard text.contains("{{date") || text.contains("{{time") else { return text }
        let pattern = #"\{\{(datetime|date|time):?([+\-]\d+)(min|d|w|m|y|h)(?::([^{}]+))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var calendar: Calendar
        if let timeZone {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = timeZone
            calendar = gregorian
        } else {
            calendar = Calendar.current
        }
        var output = text
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in regex.matches(in: output, range: nsRange).reversed() {
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range(at: 0), in: output),
                  let kindRange = Range(match.range(at: 1), in: output),
                  let offsetRange = Range(match.range(at: 2), in: output),
                  let unitRange = Range(match.range(at: 3), in: output),
                  let delta = Int(output[offsetRange]) else { continue }

            let kind = String(output[kindRange])
            let unit = String(output[unitRange])
            let targetDate = addDateOffset(delta: delta, unit: unit, to: baseDate, calendar: calendar)

            let formatter = DateFormatter()
            formatter.locale = locale
            if let timeZone { formatter.timeZone = timeZone }
            if match.numberOfRanges >= 5,
               match.range(at: 4).location != NSNotFound,
               let patRange = Range(match.range(at: 4), in: output) {
                formatter.dateFormat = String(output[patRange])
            } else {
                switch kind {
                case "time":
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                case "datetime":
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                default:
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none
                }
            }
            output.replaceSubrange(fullRange, with: formatter.string(from: targetDate))
        }
        return output
    }

    private static func addDateOffset(delta: Int, unit: String, to date: Date, calendar: Calendar) -> Date {
        switch unit {
        case "min": return calendar.date(byAdding: .minute, value: delta, to: date) ?? date
        case "h": return calendar.date(byAdding: .hour, value: delta, to: date) ?? date
        case "w": return calendar.date(byAdding: .weekOfYear, value: delta, to: date) ?? date
        case "m": return calendar.date(byAdding: .month, value: delta, to: date) ?? date
        case "y": return calendar.date(byAdding: .year, value: delta, to: date) ?? date
        default: return calendar.date(byAdding: .day, value: delta, to: date) ?? date
        }
    }

    private static func expandBaseDateTokens(_ text: String, date: Date, locale: Locale, timeZone: TimeZone? = nil) -> String {
        guard text.contains("{{") else { return text }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        if let timeZone { dateFormatter.timeZone = timeZone }
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        if let timeZone { timeFormatter.timeZone = timeZone }
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let dStr = dateFormatter.string(from: date)
        let tStr = timeFormatter.string(from: date)
        var out = text
            .replacingOccurrences(of: "{{date}}", with: dStr)
            .replacingOccurrences(of: "{{time}}", with: tStr)
            .replacingOccurrences(of: "{{datetime}}", with: "\(dStr) \(tStr)")

        if let regex = try? NSRegularExpression(pattern: #"\{\{(datetime|date|time)-tz\(([^(){}]+)\):([^{}]+)\}\}"#) {
            let nsRange = NSRange(out.startIndex..<out.endIndex, in: out)
            for match in regex.matches(in: out, range: nsRange).reversed() {
                guard match.numberOfRanges >= 4,
                      let fullRange = Range(match.range(at: 0), in: out),
                      let tzRange = Range(match.range(at: 2), in: out),
                      let patRange = Range(match.range(at: 3), in: out) else { continue }
                let tzID = String(out[tzRange])
                guard let tz = TimeZone(identifier: tzID) else { continue }
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = tz
                formatter.dateFormat = String(out[patRange])
                out.replaceSubrange(fullRange, with: formatter.string(from: date))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\{\{(datetime|date|time):([^{}]+)\}\}"#) {
            let nsRange = NSRange(out.startIndex..<out.endIndex, in: out)
            for match in regex.matches(in: out, range: nsRange).reversed() {
                guard let fullRange = Range(match.range(at: 0), in: out),
                      let patRange = Range(match.range(at: 2), in: out) else { continue }
                let formatter = DateFormatter()
                formatter.locale = locale
                if let timeZone { formatter.timeZone = timeZone }
                formatter.dateFormat = String(out[patRange])
                out.replaceSubrange(fullRange, with: formatter.string(from: date))
            }
        }
        return out
    }

    static func containsMarkdownSyntax(_ text: String) -> Bool {
        let patterns = [
            #"\*\*[^*\n]+\*\*"#,
            #"`[^`\n]+`"#,
            #"\[[^\]\n]+\]\(https?://[^\)\s]+\)"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Lightweight inline Markdown-to-RTF `NSAttributedString` builder (`**bold**`, `*italic*`, `` `code` ``, `[label](url)`).
    static func renderMarkdownAttributedString(_ markdown: String, baseFontSize: CGFloat = 13) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let boldFont = NSFont.boldSystemFont(ofSize: baseFontSize)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize - 0.5, weight: .regular)

        let combinedPattern = #"(\*\*[^*\n]+\*\*|`[^`\n]+`|\[[^\]\n]+\]\(https?://[^\)\s]+\)|\*[^*\n]+\*)"#
        guard let regex = try? NSRegularExpression(pattern: combinedPattern) else {
            return NSAttributedString(string: markdown, attributes: [.font: baseFont])
        }

        let nsText = markdown as NSString
        var cursor = 0
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)) {
            if match.range.location > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(NSAttributedString(string: plain, attributes: [.font: baseFont]))
            }
            let token = nsText.substring(with: match.range)
            if token.hasPrefix("**"), token.hasSuffix("**"), token.count > 4 {
                let inner = String(token.dropFirst(2).dropLast(2))
                result.append(NSAttributedString(string: inner, attributes: [.font: boldFont]))
            } else if token.hasPrefix("`"), token.hasSuffix("`"), token.count > 2 {
                let inner = String(token.dropFirst().dropLast())
                result.append(NSAttributedString(string: inner, attributes: [.font: monoFont]))
            } else if token.hasPrefix("*"), token.hasSuffix("*"), token.count > 2 {
                let inner = String(token.dropFirst().dropLast())
                result.append(NSAttributedString(string: inner, attributes: [.font: italicFont]))
            } else if token.hasPrefix("["),
                      let split = token.range(of: "]("),
                      token.hasSuffix(")") {
                let label = String(token[token.index(after: token.startIndex)..<split.lowerBound])
                let urlStr = String(token[split.upperBound..<token.index(before: token.endIndex)])
                var attrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                if let url = URL(string: urlStr) { attrs[.link] = url }
                result.append(NSAttributedString(string: label, attributes: attrs))
            } else {
                result.append(NSAttributedString(string: token, attributes: [.font: baseFont]))
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < nsText.length {
            result.append(NSAttributedString(string: nsText.substring(from: cursor), attributes: [.font: baseFont]))
        }
        return result
    }
}
