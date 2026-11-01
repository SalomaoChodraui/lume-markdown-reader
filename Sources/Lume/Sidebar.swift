import LumeKit
import SwiftUI

/// The files of the open folder, as a tree, or search results across them.
struct FileSidebar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        List(selection: selection) {
            if model.kind == nil {
                recentSection
            } else if model.fileQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Section(model.kind == .guide ? "Guia do Lume" : model.title) {
                    TreeRows(nodes: model.tree)
                }
            } else {
                Section(resultsTitle) {
                    ForEach(model.searchResults) { file in
                        SearchResultRow(file: file, query: model.fileQuery)
                            .tag(file.path)
                    }
                }
            }
        }
        .searchable(text: $model.fileQuery, placement: .sidebar, prompt: "Buscar nos arquivos")
        .modifier(SearchFocus(focused: $searchFocused))
        .onChange(of: model.fileSearchFocusRequest) {
            if #available(macOS 15, *) {
                searchFocused = true
            } else {
                model.focusSearchFieldInWindow()
            }
        }
        .overlay {
            if model.kind != nil, !model.fileQuery.isEmpty, model.searchResults.isEmpty {
                ContentUnavailableView.search(text: model.fileQuery)
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.currentPath }, set: { path in
            if let path, path != model.currentPath { model.navigate(to: path) }
        })
    }

    private var resultsTitle: String {
        let count = model.searchResults.count
        return count == 1 ? "1 resultado" : "\(count) resultados"
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recents.isEmpty {
            Section("Recentes") {
                ForEach(model.recents) { item in
                    Button {
                        Task { await model.open(URL(fileURLWithPath: item.path)) }
                    } label: {
                        Label(item.name, systemImage: item.isFolder ? "folder" : "doc.text")
                    }
                    .buttonStyle(.plain)
                    .help(item.path)
                    .contextMenu {
                        Button("Mostrar no Finder") { model.revealInFinder(URL(fileURLWithPath: item.path)) }
                        Divider()
                        Button("Remover dos Recentes") { model.removeRecent(item.path) }
                    }
                }
            }
        }
    }
}

/// Folders and files, with disclosure triangles like Finder's sidebar.
struct TreeRows: View {
    @Environment(AppModel.self) private var model
    let nodes: [FileNode]

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansion(node.path)) {
                    TreeRows(nodes: children)
                } label: {
                    Label(node.name, systemImage: "folder")
                        .contextMenu { FileContextMenu(path: node.path) }
                }
            } else {
                FileRow(path: node.path)
                    .tag(node.path)
            }
        }
    }

    private func expansion(_ path: String) -> Binding<Bool> {
        Binding(get: { model.expanded.contains(path) }, set: { open in
            // Option-click opens a folder and everything inside it.
            let all = NSEvent.modifierFlags.contains(.option) ? subfolders(of: path) : [path]
            if open { model.expanded.formUnion(all) } else { model.expanded.subtract(all) }
        })
    }

    private func subfolders(of path: String) -> [String] {
        model.files.flatMap { FileTree.ancestors(of: $0.path) }.filter { $0 == path || $0.hasPrefix(path + "/") }
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        let file = model.files.first { $0.path == path }
        HStack {
            Label(file?.title ?? (path as NSString).lastPathComponent, systemImage: "doc.text")
            Spacer(minLength: 0)
            if file?.isDirty == true {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
                    .help("Alterações não salvas")
                    .accessibilityLabel("Alterações não salvas")
            }
        }
        .contextMenu { FileContextMenu(path: path) }
        .onDrag {
            // A drag to Finder copies the real file.
            guard let url = model.url(for: path) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}

struct SearchResultRow: View {
    let file: DocumentFile
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(file.title, systemImage: "doc.text")
            Text(SearchText.snippet(query, in: file.content) ?? file.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }
}

/// The same actions as File > Show in Finder and Copy Path, for any row.
struct FileContextMenu: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        if let url = model.url(for: path), model.kind != .guide {
            Button("Mostrar no Finder") { model.revealInFinder(url) }
            Button("Copiar Caminho") { model.copyPath(url) }
        }
    }
}

/// `searchFocused` exists from macOS 15. On 14, ⌥⌘F finds the field in the window instead.
private struct SearchFocus: ViewModifier {
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(focused)
        } else {
            content
        }
    }
}
