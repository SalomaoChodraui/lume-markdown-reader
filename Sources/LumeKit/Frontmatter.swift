import Foundation

/// One `key: value` line from a document's YAML front matter.
public struct Property: Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Splits YAML front matter (between two `---` lines at the top) from the body.
public enum Frontmatter {
    public static func split(_ source: String) -> (properties: [Property], body: String) {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") else { return ([], text) }
        let rest = text.dropFirst(4)
        guard let closing = rest.range(of: "\n---") ?? (rest.hasPrefix("---") ? rest.range(of: "---") : nil) else {
            return ([], text)
        }
        let header = rest[rest.startIndex..<closing.lowerBound]
        var body = rest[closing.upperBound...]
        // The closing fence may carry trailing spaces before its newline.
        if let newline = body.firstIndex(of: "\n") {
            if body[body.startIndex..<newline].allSatisfy(\.isWhitespace) {
                body = body[body.index(after: newline)...]
            }
        } else if body.allSatisfy(\.isWhitespace) {
            body = ""
        }
        let properties = header.split(separator: "\n").compactMap { line -> Property? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return Property(key: key, value: value)
        }
        return (properties, String(body.drop(while: { $0 == "\n" })))
    }
}
