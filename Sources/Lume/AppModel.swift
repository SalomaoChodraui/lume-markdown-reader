import AppKit
import LumeKit
import Observation
import UniformTypeIdentifiers

/// One Markdown document in the open library.
@Observable
final class DocumentFile: Identifiable {
    let id = UUID()
    /// The path inside the library, which is also the sidebar id.
    var path: String
    /// nil for a document that has never been saved.
    var url: URL?
    /// Guide pages live inside the app: Save asks where to put a copy.
    var isReadOnly: Bool
    var content: String
    var savedContent: String
    var modified: Date?

    var name: String { (path as NSString).lastPathComponent }
    var title: String { MarkdownFiles.stem(name) }
    var isDirty: Bool { content != savedContent }

    init(path: String, url: URL?, content: String, modified: Date?, isReadOnly: Bool = false) {
        self.path = path
        self.url = url
        self.content = content
        self.savedContent = content
        self.modified = modified
        self.isReadOnly = isReadOnly
    }
}

struct OutlineItem: Identifiable, Hashable {
    let id: String
    let label: String
    let depth: Int
}

/// The find bar over the reading page.
struct FindState {
    var isVisible = false
    var query = ""
    var count = 0
    var active = 0
}

enum LibraryKind: String {
    case folder, file, guide
}

/// The answer to "save your changes?".
enum UnsavedChoice {
    case save, discard, cancel
}

/// Everything the window, the menus, and the reader share.
@Observable
final class AppModel {
    static let shared = AppModel()

    let prefs = Preferences()
    let reader = ReaderController()

    // The library: a folder, a few loose files, or the built-in guide.
    private(set) var kind: LibraryKind?
    private(set) var rootURL: URL?
    private(set) var title = ""
    private(set) var files: [DocumentFile] = []
    private(set) var tree: [FileNode] = []
    var expanded: Set<String> = []
    private(set) var isLoading = false

    // Where the person is.
    private(set) var currentPath: String?
    private(set) var history: [String] = []
    private(set) var historyIndex = -1
    var editing = false
    var outline: [OutlineItem] = []
    var currentHeading: String?
    var scrollPositions: [String: Double] = [:]
    /// A heading to reach once the next document renders.
    var pendingHeading: String?

    // Panels and search.
    var showInspector: Bool { didSet { prefs.set(showInspector, for: "view.inspector") } }
    var fileQuery = ""
    var fileSearchFocusRequest = 0
    var find = FindState()
    var readingPopoverShown = false
    var dropTargeted = false

    private(set) var recents: [RecentItem] = []
    weak var window: NSWindow?
    weak var editorView: NSTextView?
    /// Self-test answer for the unsaved-changes question.
    var unsavedAnswer: UnsavedChoice?

    private var watcher: Task<Void, Never>?

    init() {
        showInspector = prefs.value("view.inspector") ?? true
        if let data: Data = prefs.value("recents"),
           let stored = try? JSONDecoder().decode([RecentItem].self, from: data) {
            recents = stored
        }
        reader.model = self
        startWatching()
    }

    // MARK: Derived state

    var current: DocumentFile? { files.first { $0.path == currentPath } }
    var hasUnsaved: Bool { files.contains(where: \.isDirty) }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
    var properties: [Property] { Frontmatter.split(current?.content ?? "").properties }
    var paths: [String] { files.map(\.path) }

    /// Files that match the sidebar search, by name or content.
    var searchResults: [DocumentFile] {
        files.filter { SearchText.matches(fileQuery, name: $0.name, content: $0.content) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    var windowTitle: String { current?.title ?? "Início" }

    var windowSubtitle: String {
        switch kind {
        case .folder, .file: title
        case .guide: "Guia do Lume"
        case nil: "Nenhum documento aberto"
        }
    }

    // MARK: Opening

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.markdownTypes + [.folder]
        panel.message = "Escolha um arquivo Markdown ou uma pasta."
        panel.prompt = "Abrir"
        let handle = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            Task { await self.open(url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    /// Opens a Markdown file or a folder, after asking about unsaved changes.
    func open(_ url: URL, at path: String? = nil, ratio: Double? = nil, askFirst: Bool = true) async {
        if askFirst, hasUnsaved, await resolveUnsaved(action: "abrir outro documento") == false { return }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.filePath, isDirectory: &isFolder) else {
            removeRecent(url.filePath)
            showError("Não encontrei “\(url.lastPathComponent)”.", detail: "O item pode ter sido movido ou apagado.")
            return
        }
        if isFolder.boolValue {
            isLoading = true
            let loaded = await Task.detached { MarkdownFiles.load(folder: url) }.value
            isLoading = false
            guard !loaded.isEmpty else {
                showError("Nenhum Markdown em “\(url.lastPathComponent)”.", detail: "A pasta e as subpastas não têm arquivos .md, .markdown ou .mdown.")
                return
            }
            replaceLibrary(kind: .folder, root: url, title: url.lastPathComponent, files: loaded.map {
                DocumentFile(path: $0.path, url: $0.url, content: $0.content, modified: $0.modified)
            })
        } else {
            guard MarkdownFiles.isMarkdown(url) else {
                showError("“\(url.lastPathComponent)” não é um arquivo Markdown.", detail: "O Lume abre arquivos .md, .markdown e .mdown.")
                return
            }
            do {
                let document = try MarkdownFiles.read(url, path: url.lastPathComponent)
                replaceLibrary(kind: .file, root: url.deletingLastPathComponent(), title: url.deletingLastPathComponent().lastPathComponent, files: [
                    DocumentFile(path: document.path, url: url, content: document.content, modified: document.modified),
                ])
            } catch {
                showError("Não consegui abrir “\(url.lastPathComponent)”.", detail: error.localizedDescription)
                return
            }
        }
        addRecent(RecentItem(path: url.filePath, isFolder: isFolder.boolValue))
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        prefs.set(url.filePath, for: "restore.library")
        if let path, let ratio, files.contains(where: { $0.path == path }) {
            scrollPositions[path] = ratio
        }
        navigate(to: path.flatMap { p in files.first { $0.path == p }?.path } ?? firstPath, record: true)
    }

    /// Opens the guide that ships inside the app, read only.
    func openGuide(page: String = "Boas-vindas.md") async {
        if hasUnsaved, await resolveUnsaved(action: "abrir o guia") == false { return }
        guard let folder = Bundle.main.resourceURL?.appending(path: "Guide") else { return }
        let loaded = MarkdownFiles.load(folder: folder)
        replaceLibrary(kind: .guide, root: nil, title: "Guia do Lume", files: loaded.map {
            DocumentFile(path: $0.path, url: $0.url, content: $0.content, modified: $0.modified, isReadOnly: true)
        })
        navigate(to: files.contains { $0.path == page } ? page : firstPath, record: true)
    }

    /// Files from Finder, the Dock, or a drop. Only the first one opens.
    func openFromSystem(_ urls: [URL]) {
        guard let url = urls.first else { return }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await open(url) }
    }

    /// Reopens what was open at quit, without asking.
    func restoreLastSession() async {
        guard kind == nil, prefs.reopenLast, let path: String = prefs.value("restore.library") else { return }
        let file: String? = prefs.value("restore.file")
        let ratio: Double? = prefs.value("restore.ratio")
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        await open(url, at: file, ratio: ratio, askFirst: false)
    }

    private var firstPath: String? {
        func first(_ nodes: [FileNode]) -> String? {
            // Files at a level come before descending into folders.
            if let file = nodes.first(where: { !$0.isFolder }) { return file.path }
            for node in nodes { if let found = first(node.children ?? []) { return found } }
            return nil
        }
        return first(tree)
    }

    private func replaceLibrary(kind: LibraryKind, root: URL?, title: String, files: [DocumentFile]) {
        self.kind = kind
        rootURL = root
        self.title = title
        self.files = files
        tree = FileTree.build(paths: files.map(\.path))
        expanded = []
        history = []
        historyIndex = -1
        currentPath = nil
        editing = false
        outline = []
        scrollPositions = [:]
        fileQuery = ""
    }

    // MARK: Navigation

    func navigate(to path: String?, heading: String? = nil, record: Bool = true) {
        guard let path, files.contains(where: { $0.path == path }) else { return }
        pendingHeading = heading
        if path == currentPath {
            if let heading { reader.scrollTo(heading: heading) }
            return
        }
        currentPath = path
        currentHeading = nil
        expanded.formUnion(FileTree.ancestors(of: path))
        if record {
            history = Array(history.prefix(historyIndex + 1))
            if history.last != path { history.append(path) }
            historyIndex = history.count - 1
        }
        prefs.set(path, for: "restore.file")
        if let url = current?.url, kind != .guide {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigate(to: history[historyIndex], record: false)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigate(to: history[historyIndex], record: false)
    }

    /// A click on a link in the document.
    func followLink(kind linkKind: String, target: String) {
        if linkKind == "external" {
            guard let url = URL(string: target), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
            NSWorkspace.shared.open(url)
            return
        }
        guard let currentPath else { return }
        if let found = LinkResolver.resolve(target, from: currentPath, in: paths) {
            navigate(to: found.path, heading: found.heading)
            return
        }
        // Not in the library: look next to the current file on disk.
        let pieces = target.split(separator: "#", maxSplits: 1).map(String.init)
        var relative = pieces.first ?? target
        if !MarkdownFiles.isMarkdown(URL(fileURLWithPath: relative)) { relative += ".md" }
        if let base = current?.url?.deletingLastPathComponent(), kind != .guide {
            let candidate = base.appending(path: relative).standardizedFileURL
            if let document = try? MarkdownFiles.read(candidate, path: libraryPath(for: candidate)) {
                add(DocumentFile(path: document.path, url: candidate, content: document.content, modified: document.modified))
                navigate(to: document.path, heading: pieces.count > 1 ? pieces[1] : nil)
                return
            }
        }
        showError("Não encontrei a nota “\(pieces.first ?? target)”.", detail: "Confira o nome do arquivo ou abra a pasta que contém a nota.")
    }

    /// The path a file gets in this library: relative inside the root, else its name.
    private func libraryPath(for url: URL) -> String {
        var path = url.lastPathComponent
        if let rootURL, MarkdownFiles.contains(rootURL, url) {
            path = MarkdownFiles.relativePath(of: url, in: rootURL)
        }
        var unique = path
        var counter = 2
        while files.contains(where: { $0.path == unique && $0.url != url }) {
            unique = "\(MarkdownFiles.stem(path)) \(counter).\((path as NSString).pathExtension)"
            counter += 1
        }
        return unique
    }

    private func add(_ file: DocumentFile) {
        guard !files.contains(where: { $0.path == file.path }) else { return }
        files.append(file)
        tree = FileTree.build(paths: paths)
    }

    func toggleEditing() {
        guard current != nil else { return }
        if editing == false { find.isVisible = false }
        editing.toggle()
    }

    // MARK: Reading size

    func zoom(_ direction: Int) {
        prefs.scale = direction == 0 ? 1 : ReaderScale.step(prefs.scale, by: direction)
    }

    // MARK: Find

    func startFind() {
        if editing {
            editorFind(.showFindInterface)
        } else if current != nil {
            find.isVisible = true
        }
    }

    func findNext(_ direction: Int) {
        if editing {
            editorFind(direction > 0 ? .nextMatch : .previousMatch)
            return
        }
        guard find.isVisible, find.count > 0 else { return }
        find.active = (find.active + direction + find.count) % find.count
        reader.search(find.query, active: find.active)
    }

    func closeFind() {
        find.isVisible = false
        find.query = ""
        find.count = 0
        reader.search("", active: 0)
    }

    func focusFileSearch() {
        fileSearchFocusRequest += 1
    }

    private func editorFind(_ action: NSTextFinder.Action) {
        guard let editorView else { return }
        let item = NSMenuItem()
        item.tag = action.rawValue
        editorView.window?.makeFirstResponder(editorView)
        editorView.performTextFinderAction(item)
    }

    // MARK: Saving

    var canSave: Bool { current?.isDirty == true }

    func save() {
        guard let file = current else { return }
        Task { _ = await save(file) }
    }

    func saveAs() {
        guard let file = current else { return }
        Task { _ = await save(file, choosingLocation: true) }
    }

    /// Writes one file. Asks where when it has no place yet or is read only.
    @discardableResult
    func save(_ file: DocumentFile, choosingLocation: Bool = false, modal: Bool = false) async -> Bool {
        var target = file.url
        if choosingLocation || file.isReadOnly || target == nil {
            target = await chooseSaveURL(for: file, modal: modal)
        }
        guard let target else { return false }
        do {
            try file.content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            showError("Não consegui salvar “\(target.lastPathComponent)”.", detail: error.localizedDescription)
            return false
        }
        file.savedContent = file.content
        file.modified = MarkdownFiles.modificationDate(of: target)
        if target != file.url {
            let oldPath = file.path
            if kind == .guide { kind = .file; title = target.deletingLastPathComponent().lastPathComponent; rootURL = target.deletingLastPathComponent() }
            file.url = target
            file.isReadOnly = false
            file.path = libraryPath(for: target)
            history = history.map { $0 == oldPath ? file.path : $0 }
            if currentPath == oldPath { currentPath = file.path }
            tree = FileTree.build(paths: paths)
            addRecent(RecentItem(path: target.filePath, isFolder: false))
        }
        return true
    }

    private func chooseSaveURL(for file: DocumentFile, modal: Bool) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.nameFieldStringValue = file.name
        panel.directoryURL = file.isReadOnly ? URL.documentsDirectory : (file.url?.deletingLastPathComponent() ?? rootURL)
        panel.message = file.isReadOnly ? "Páginas do guia ficam dentro do app. Escolha onde salvar uma cópia." : ""
        let response: NSApplication.ModalResponse
        if !modal, let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    /// Asks about unsaved changes before `action`. True when it is safe to go on.
    func resolveUnsaved(action: String, modal: Bool = false) async -> Bool {
        let dirty = files.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        let choice: UnsavedChoice
        if let unsavedAnswer { choice = unsavedAnswer } else { choice = await askAboutUnsaved(dirty, modal: modal) }
        switch choice {
        case .cancel:
            return false
        case .discard:
            for file in dirty { file.content = file.savedContent }
            return true
        case .save:
            for file in dirty where await save(file, modal: modal) == false { return false }
            return true
        }
    }

    private func askAboutUnsaved(_ dirty: [DocumentFile], modal: Bool) async -> UnsavedChoice {
        let alert = NSAlert()
        if dirty.count == 1 {
            alert.messageText = "Deseja salvar as alterações feitas em “\(dirty[0].name)”?"
        } else {
            alert.messageText = "Há alterações não salvas em \(dirty.count) documentos. Deseja salvá-las?"
        }
        alert.informativeText = "Suas alterações serão perdidas se você não salvá-las."
        alert.addButton(withTitle: dirty.count == 1 ? "Salvar" : "Salvar Todos")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"
        let discard = alert.addButton(withTitle: "Não Salvar")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        discard.hasDestructiveAction = true
        let response: NSApplication.ModalResponse
        if !modal, let window, window.isVisible, window.attachedSheet == nil {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        switch response {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }

    // MARK: Watching for outside changes

    private func startWatching() {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.checkForOutsideChanges()
            }
        }
    }

    /// Reloads the open document when another app saved it, unless it has edits here.
    func checkForOutsideChanges() {
        guard let file = current, let url = file.url, !file.isDirty, !file.isReadOnly else { return }
        guard let date = MarkdownFiles.modificationDate(of: url), date != file.modified,
              let document = try? MarkdownFiles.read(url, path: file.path) else { return }
        file.content = document.content
        file.savedContent = document.content
        file.modified = document.modified
    }

    /// Picks up files added to or removed from the folder while the app was in the background.
    func rescanFolder() async {
        guard kind == .folder, let rootURL else { return }
        let loaded = await Task.detached { MarkdownFiles.load(folder: rootURL) }.value
        let existing = Set(paths)
        let found = Set(loaded.map(\.path))
        guard existing != found else { return }
        let keep = files.filter { found.contains($0.path) || $0.isDirty }
        let added = loaded.filter { !existing.contains($0.path) }.map {
            DocumentFile(path: $0.path, url: $0.url, content: $0.content, modified: $0.modified)
        }
        files = keep + added
        tree = FileTree.build(paths: paths)
        if let currentPath, !files.contains(where: { $0.path == currentPath }) {
            self.currentPath = nil
            navigate(to: firstPath)
        }
    }

    // MARK: Recents

    func addRecent(_ item: RecentItem) {
        recents = RecentItem.adding(item, to: recents)
        saveRecents()
    }

    func removeRecent(_ path: String) {
        recents.removeAll { $0.path == path }
        saveRecents()
    }

    /// Clears the list, with Undo in the Edit menu.
    func clearRecents() {
        let previous = recents
        recents = []
        saveRecents()
        NSDocumentController.shared.clearRecentDocuments(nil)
        let undo = window?.undoManager
        undo?.registerUndo(withTarget: self) { model in
            model.recents = previous
            model.saveRecents()
        }
        undo?.setActionName("Limpar Recentes")
    }

    private func saveRecents() {
        prefs.set(try? JSONEncoder().encode(recents), for: "recents")
    }

    // MARK: File actions

    func revealInFinder(_ url: URL? = nil) {
        guard let url = url ?? current?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL? = nil) {
        guard let url = url ?? current?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.filePath, forType: .string)
    }

    func url(for path: String) -> URL? {
        if let file = files.first(where: { $0.path == path }) { return file.url }
        return rootURL.map { $0.appending(path: path) }
    }

    func printDocument() {
        guard current != nil else { return }
        if editing { editing = false }
        reader.printDocument(window: window)
    }

    // MARK: Errors

    /// Errors show as a sheet on the window, never as a toast that disappears.
    func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        if Store.isOverridden, SelfTest.requested {
            print("ALERT \(message)")
            return
        }
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static let markdownTypes: [UTType] = ["md", "markdown", "mdown"].compactMap { UTType(filenameExtension: $0) }
}

extension URL {
    /// The plain file path, without the trailing slash a folder URL can carry.
    var filePath: String {
        let path = standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
