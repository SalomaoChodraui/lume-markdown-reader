import Foundation

/// Finds the document a wiki link or a relative Markdown link points to.
public enum LinkResolver {
    public struct Target: Equatable, Sendable {
        public let path: String
        public let heading: String?
    }

    /// `link` is "Nota", "Nota#Seção", "../pasta/Nota.md" or "Nota.md#Seção".
    /// Looks next to the current file first, then the exact path from the
    /// library root, then any file with that name.
    public static func resolve(_ link: String, from current: String, in paths: [String]) -> Target? {
        let decoded = link.removingPercentEncoding ?? link
        let pieces = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pieces.first ?? "").trimmingCharacters(in: .whitespaces)
        let heading = pieces.count > 1 ? String(pieces[1]) : nil
        guard !rawPath.isEmpty else { return nil }

        let wanted = MarkdownFiles.stem(rawPath).lowercased()
        let directory = FileTree.directory(of: current)
        let relative = MarkdownFiles.stem(FileTree.normalize(directory.isEmpty ? rawPath : "\(directory)/\(rawPath)")).lowercased()
        let exact = MarkdownFiles.stem(FileTree.normalize(rawPath)).lowercased()

        let stems = paths.map { (path: $0, stem: MarkdownFiles.stem(FileTree.normalize($0)).lowercased()) }
        let match = stems.first { $0.stem == relative }
            ?? stems.first { $0.stem == exact }
            ?? stems.first { ($0.stem as NSString).lastPathComponent == (wanted as NSString).lastPathComponent }
        return match.map { Target(path: $0.path, heading: heading?.isEmpty == true ? nil : heading) }
    }
}
