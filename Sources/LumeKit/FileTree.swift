import Foundation

/// A row in the sidebar: a folder with children, or a file.
public struct FileNode: Identifiable, Hashable, Sendable {
    /// The relative path, which is also the id.
    public let path: String
    public let name: String
    /// nil for a file, so `List(children:)` shows no disclosure triangle.
    public var children: [FileNode]?

    public var id: String { path }
    public var isFolder: Bool { children != nil }

    public init(path: String, name: String, children: [FileNode]?) {
        self.path = path
        self.name = name
        self.children = children
    }
}

public enum FileTree {
    /// Builds the folder tree from relative paths. Folders come first, then
    /// files, each sorted like Finder ("Nota 2" before "Nota 10").
    public static func build(paths: [String]) -> [FileNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [String] = []
        }
        let root = Folder()
        for path in paths {
            let pieces = normalize(path).split(separator: "/").map(String.init)
            guard let fileName = pieces.last else { continue }
            var folder = root
            for piece in pieces.dropLast() {
                if let next = folder.folders[piece] {
                    folder = next
                } else {
                    let next = Folder()
                    folder.folders[piece] = next
                    folder = next
                }
            }
            folder.files.append(fileName)
        }
        func nodes(_ folder: Folder, prefix: String) -> [FileNode] {
            let join = { (name: String) in prefix.isEmpty ? name : "\(prefix)/\(name)" }
            let folders = folder.folders.keys.sorted(by: finderOrder).map { name in
                FileNode(path: join(name), name: name, children: nodes(folder.folders[name]!, prefix: join(name)))
            }
            let files = folder.files.sorted(by: finderOrder).map { name in
                FileNode(path: join(name), name: name, children: nil)
            }
            return folders + files
        }
        return nodes(root, prefix: "")
    }

    /// The folders that hold `path`, outermost first: "a/b/c.md" -> ["a", "a/b"].
    public static func ancestors(of path: String) -> [String] {
        let pieces = normalize(path).split(separator: "/").dropLast()
        return pieces.indices.map { pieces[pieces.startIndex...$0].joined(separator: "/") }
    }

    /// Resolves "." and ".." and drops empty pieces: "a/./b/../c.md" -> "a/c.md".
    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }

    public static func directory(of path: String) -> String {
        let pieces = normalize(path).split(separator: "/")
        return pieces.dropLast().joined(separator: "/")
    }

    static func finderOrder(_ left: String, _ right: String) -> Bool {
        left.localizedStandardCompare(right) == .orderedAscending
    }
}
