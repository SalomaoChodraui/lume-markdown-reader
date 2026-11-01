import LumeKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            FileSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 248, max: 360)
        } detail: {
            DocumentPane()
        }
        .inspector(isPresented: $model.showInspector) {
            OutlineInspector()
                .inspectorColumnWidth(min: 180, ideal: 248, max: 340)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        Button("Sumário", systemImage: "sidebar.trailing") { model.showInspector.toggle() }
                            .help("Mostrar ou ocultar o sumário (⌃⌘I)")
                    }
                }
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.windowSubtitle)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            Task { await model.open(url) }
            return true
        } isTargeted: { model.dropTargeted = $0 }
        .overlay {
            if model.dropTargeted {
                // The drop target outline, like Finder's.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 4)
                    .padding(Space.xs)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(WindowAccessor { window in
            model.window = window
        })
        .onChange(of: model.hasUnsaved, initial: true) { _, dirty in
            model.window?.isDocumentEdited = dirty
        }
        .onChange(of: model.current?.url, initial: true) { _, url in
            model.window?.representedURL = model.kind == .guide ? nil : url
        }
        .onChange(of: columns) { _, value in
            model.prefs.set(value == .detailOnly, for: "view.sidebarHidden")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.rescanFolder() }
        }
        .task {
            if model.prefs.value("view.sidebarHidden") == true { columns = .detailOnly }
            if Snapshot.requested || SelfTest.requested {
                SelfTest.runIfRequested(model: model)
                Snapshot.runIfRequested(model: model, openSettings: openSettings)
            } else {
                await model.restoreLastSession()
            }
        }
    }
}

/// The detail column: the document, the editor, or the empty state.
struct DocumentPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var inspectorFolded = false

    var body: some View {
        Group {
            if let file = model.current {
                if model.editing {
                    MarkdownEditor(file: file, showLineNumbers: model.prefs.showLineNumbers,
                                   scale: model.prefs.scale) { model.editorView = $0 }
                        .id(file.id)
                } else {
                    ReaderPane(controller: model.reader)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if model.find.isVisible { FindBar() }
                        }
                }
            } else if model.isLoading {
                ProgressView("Lendo a pasta…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyLibraryView()
            }
        }
        .toolbar { DocumentToolbar() }
        // Push the document into the page whenever it or the look changes.
        // While editing, the page renders in the background after a pause in
        // typing, so the outline follows the text.
        .task(id: renderKey) {
            if model.editing {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
            }
            render()
        }
        // A narrow window gives its width to the text: the outline folds away
        // first and comes back when there is room again.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // Change the columns after this layout pass, never inside it.
            if width < 460, model.showInspector {
                Task { @MainActor in
                    inspectorFolded = true
                    model.showInspector = false
                }
            } else if width > 760, inspectorFolded {
                Task { @MainActor in
                    inspectorFolded = false
                    model.showInspector = true
                }
            }
        }
        .onChange(of: appearanceKey, initial: true) { applyAppearance() }
        .onChange(of: model.editing) { _, editing in
            if !editing { model.editorView = nil }
        }
    }

    private var resolvedTheme: ReadingTheme {
        model.prefs.theme.resolved(dark: colorScheme == .dark)
    }

    private var renderKey: String {
        guard let file = model.current else { return "" }
        return "\(file.path)\u{0}\(file.content.hashValue)\u{0}\(model.pendingHeading ?? "")"
    }

    private var appearanceKey: String {
        let terminal = model.prefs.terminal.cssValues.sorted { $0.key < $1.key }.map(\.value).joined(separator: ",")
        return "\(resolvedTheme.rawValue)|\(model.prefs.width.rawValue)|\(model.prefs.scale)|\(terminal)"
    }

    private func render() {
        guard let file = model.current else {
            model.reader.clear()
            model.outline = []
            return
        }
        model.reader.show(file, ratio: model.scrollPositions[file.path] ?? 0, heading: model.pendingHeading)
    }

    private func applyAppearance() {
        model.reader.setAppearance(theme: resolvedTheme, width: model.prefs.width,
                                   scale: model.prefs.scale, terminal: model.prefs.terminal)
    }
}

/// Toolbar over the document column. Back and forward lead; the mode
/// switch and its partner, then reading options, trail.
struct DocumentToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup(placement: .navigation) {
            Button("Voltar", systemImage: "chevron.backward") { model.goBack() }
                .disabled(!model.canGoBack)
                .help("Voltar ao documento anterior (⌘[)")
            Button("Avançar", systemImage: "chevron.forward") { model.goForward() }
                .disabled(!model.canGoForward)
                .help("Avançar ao próximo documento (⌘])")
        }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
            if model.editing, model.current != nil {
                Button("Ler", systemImage: "book") { model.toggleEditing() }
                    .help("Voltar à leitura (⇧⌘E)")
                Button("Salvar", systemImage: "square.and.arrow.down") { model.save() }
                    .disabled(!model.canSave)
                    .help("Salvar as alterações no arquivo (⌘S)")
            } else {
                Button("Editar", systemImage: "pencil") { model.toggleEditing() }
                    .disabled(model.current == nil)
                    .help("Editar o Markdown deste documento (⇧⌘E)")
                Button("Buscar", systemImage: "magnifyingglass") {
                    model.find.isVisible ? model.closeFind() : model.startFind()
                }
                .disabled(model.current == nil)
                .help("Buscar neste documento (⌘F)")
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button("Leitura", systemImage: "textformat.size") { model.readingPopoverShown.toggle() }
                .help("Ajustar o tamanho do texto, a largura e o tema")
                .popover(isPresented: $model.readingPopoverShown, arrowEdge: .bottom) {
                    ReadingPopover()
                        .environment(model)
                }
        }
    }
}

/// The find bar over the reading page, like Safari's.
struct FindBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.sm) {
            TextField("Buscar no documento", text: $model.find.query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(maxWidth: 320)
                .onSubmit { model.findNext(NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                .onChange(of: model.find.query) { _, query in
                    model.find.active = 0
                    model.reader.search(query, active: 0)
                }
                .onKeyPress(.escape) {
                    model.closeFind()
                    return .handled
                }
            Text(countLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ControlGroup {
                Button("Anterior", systemImage: "chevron.left") { model.findNext(-1) }
                    .help("Ir à ocorrência anterior (⇧⌘G)")
                Button("Próxima", systemImage: "chevron.right") { model.findNext(1) }
                    .help("Ir à próxima ocorrência (⌘G)")
            }
            .disabled(model.find.count == 0)
            .fixedSize()
            Spacer()
            Button("OK") { model.closeFind() }
                .help("Fechar a busca (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
    }

    private var countLabel: String {
        let query = model.find.query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return "" }
        if model.find.count == 0 { return "Nenhuma ocorrência" }
        return "\(model.find.active + 1) de \(model.find.count)"
    }
}

/// Before anything is open: one action, plus the way to the guide.
struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Nenhum documento aberto", systemImage: "doc.text")
        } description: {
            Text("Abra um arquivo Markdown ou uma pasta, ou solte-os nesta janela.")
        } actions: {
            Button("Abrir…") { model.showOpenPanel() }
                .buttonStyle(.borderedProminent)
                .help("Escolher um arquivo ou uma pasta (⌘O)")
            Button("Ver o Guia do Lume") { Task { await model.openGuide() } }
        }
    }
}

/// Text size, column width, and theme, next to the page they change.
struct ReadingPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            LabeledContent("Tamanho do texto") {
                HStack(spacing: Space.sm) {
                    Button("Diminuir", systemImage: "textformat.size.smaller") { model.zoom(-1) }
                        .labelStyle(.iconOnly)
                        .disabled(prefs.scale <= ReaderScale.minimum)
                        .help("Diminuir o texto (⌘-)")
                    Text(prefs.scale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: 44)
                    Button("Aumentar", systemImage: "textformat.size.larger") { model.zoom(1) }
                        .labelStyle(.iconOnly)
                        .disabled(prefs.scale >= ReaderScale.maximum)
                        .help("Aumentar o texto (⌘+)")
                }
            }
            Picker("Largura", selection: $prefs.width) {
                ForEach(ReadingWidth.allCases) { Text($0.label).tag($0) }
            }
            Picker("Tema", selection: $prefs.theme) {
                ForEach(ReadingTheme.allCases) { Text($0.label).tag($0) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .noInitialFocus()
    }
}
