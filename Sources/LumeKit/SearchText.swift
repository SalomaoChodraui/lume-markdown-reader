import Foundation

/// Plain-text helpers for searching across documents.
public enum SearchText {
    /// True when `query` appears in the name or the text, ignoring case and accents.
    public static func matches(_ query: String, name: String, content: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return name.range(of: clean, options: options) != nil || content.range(of: clean, options: options) != nil
    }

    /// A short excerpt around the first match, or nil when only the name matched.
    public static func snippet(_ query: String, in content: String, radius: Int = 48) -> String? {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let plain = Frontmatter.split(content).body
            .replacingOccurrences(of: #"[`*_>#\[\]()|~]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let range = plain.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        var start = plain.index(range.lowerBound, offsetBy: -radius, limitedBy: plain.startIndex) ?? plain.startIndex
        // Start on a whole word.
        if start > plain.startIndex, let space = plain[start..<range.lowerBound].firstIndex(of: " ") {
            start = plain.index(after: space)
        }
        let end = plain.index(range.upperBound, offsetBy: radius * 2, limitedBy: plain.endIndex) ?? plain.endIndex
        let excerpt = plain[start..<end].trimmingCharacters(in: .whitespaces)
        return (start > plain.startIndex ? "…" : "") + excerpt + (end < plain.endIndex ? "…" : "")
    }
}
