import Foundation

/// Finding Markdown files on disk.
public enum MarkdownFiles {
    public static let extensions: Set<String> = ["md", "markdown", "mdown"]
    /// Folders that hold tooling, never notes. Skipping them keeps big repos fast.
    static let skippedFolders: Set<String> = ["node_modules", ".git", ".build", "DerivedData", "Pods"]

    public static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// The name without a Markdown extension: "Atalhos.md" -> "Atalhos".
    public static func stem(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return extensions.contains(ext) ? (name as NSString).deletingPathExtension : name
    }

    /// Every Markdown file under `folder`, skipping hidden items and tooling folders.
    public static func collect(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) { walker.skipDescendants() }
            } else if values?.isRegularFile == true, isMarkdown(url) {
                found.append(url)
            }
        }
        return found
    }

    /// `url`'s path inside `folder`, with forward slashes: "notas/ideia.md".
    public static func relativePath(of url: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// True when `url` sits inside `folder`.
    public static func contains(_ folder: URL, _ url: URL) -> Bool {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}

/// A Markdown file read from disk, ready for the library.
public struct LoadedDocument: Sendable {
    public let url: URL
    public let path: String
    public let content: String
    public let modified: Date?
}

extension MarkdownFiles {
    /// Reads one file. Text that is not valid UTF-8 is repaired, never refused.
    public static func read(_ url: URL, path: String) throws -> LoadedDocument {
        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return LoadedDocument(url: url, path: path, content: content, modified: modificationDate(of: url))
    }

    /// Reads every Markdown file under `folder`. Unreadable files are skipped.
    public static func load(folder: URL) -> [LoadedDocument] {
        collect(in: folder).compactMap { try? read($0, path: relativePath(of: $0, in: folder)) }
    }

    /// Read fresh from disk each time (URL caches its resource values).
    public static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}
