import LumeKit
import SwiftUI

/// The menu bar. Every toolbar button and context menu item lives here too,
/// with its shortcut. Command map:
///   Arquivo     Abrir… ⌘O, Abrir Recente, Salvar ⌘S, Salvar Como… ⇧⌘S,
///               Mostrar no Finder, Copiar Caminho ⌥⌘C, Imprimir… ⌘P
///   Editar      Buscar ▸ Buscar… ⌘F, Buscar Seguinte ⌘G, Buscar Anterior ⇧⌘G,
///               Buscar nos Arquivos ⌥⌘F
///   Visualizar  Barra lateral ⌃⌘S, Sumário ⌃⌘I, Editar Markdown ⇧⌘E,
///               Números de Linha ⌥⌘L, Tamanho Real ⌘0, Aumentar ⌘+, Diminuir ⌘-,
///               Largura ▸, Tema ▸
///   Ir          Voltar ⌘[, Avançar ⌘]
///   Ajuda       Guia do Lume, Atalhos de Teclado
struct LumeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()

        CommandGroup(replacing: .newItem) {
            Button("Abrir…") { model.showOpenPanel() }
                .keyboardShortcut("o")
            Menu("Abrir Recente") {
                ForEach(model.recents) { item in
                    Button(item.name) { Task { await model.open(URL(fileURLWithPath: item.path)) } }
                }
                Divider()
                Button("Limpar Menu") { model.clearRecents() }
                    .disabled(model.recents.isEmpty)
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Salvar") { model.save() }
                .keyboardShortcut("s")
                .disabled(!model.canSave)
            Button("Salvar Como…") { model.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.current == nil)
            Divider()
            Button("Mostrar no Finder") { model.revealInFinder() }
                .disabled(model.current?.url == nil || model.kind == .guide)
            Button("Copiar Caminho") { model.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.current?.url == nil || model.kind == .guide)
        }

        CommandGroup(replacing: .printItem) {
            Button("Imprimir…") { model.printDocument() }
                .keyboardShortcut("p")
                .disabled(model.current == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Buscar") {
                Button("Buscar…") { model.startFind() }
                    .keyboardShortcut("f")
                    .disabled(model.current == nil)
                Button("Buscar Seguinte") { model.findNext(1) }
                    .keyboardShortcut("g")
                    .disabled(model.current == nil)
                Button("Buscar Anterior") { model.findNext(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(model.current == nil)
                Divider()
                Button("Buscar nos Arquivos") { model.focusFileSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(model.kind == nil)
            }
        }

        CommandGroup(after: .sidebar) {
            // Our own item: InspectorCommands reads "Inspetor de Show" in pt-BR on macOS 27.
            Button(model.showInspector ? "Ocultar Sumário" : "Mostrar Sumário") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .control])
            Divider()
            Button(model.editing ? "Voltar à Leitura" : "Editar Markdown") { model.toggleEditing() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.current == nil)
            Button(model.prefs.showLineNumbers ? "Ocultar Números de Linha" : "Mostrar Números de Linha") {
                model.prefs.showLineNumbers.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button("Tamanho Real") { model.zoom(0) }
                .keyboardShortcut("0")
                .disabled(model.prefs.scale == 1)
            Button("Aumentar Texto") { model.zoom(1) }
                .keyboardShortcut("+")
                .disabled(model.prefs.scale >= ReaderScale.maximum)
            Button("Diminuir Texto") { model.zoom(-1) }
                .keyboardShortcut("-")
                .disabled(model.prefs.scale <= ReaderScale.minimum)
            Picker("Largura da Leitura", selection: Binding(get: { model.prefs.width }, set: { model.prefs.width = $0 })) {
                ForEach(ReadingWidth.allCases) { Text($0.label).tag($0) }
            }
            Picker("Tema", selection: Binding(get: { model.prefs.theme }, set: { model.prefs.theme = $0 })) {
                ForEach(ReadingTheme.allCases) { Text($0.label).tag($0) }
            }
            Divider()
        }

        CommandMenu("Ir") {
            Button("Voltar") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(!model.canGoBack)
            Button("Avançar") { model.goForward() }
                .keyboardShortcut("]")
                .disabled(!model.canGoForward)
        }

        CommandGroup(replacing: .help) {
            Button("Guia do Lume") { Task { await model.openGuide() } }
            Button("Atalhos de Teclado") { Task { await model.openGuide(page: "Atalhos.md") } }
        }
    }
}
