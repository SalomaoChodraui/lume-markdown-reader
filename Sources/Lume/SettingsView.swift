import AppKit
import LumeKit
import SwiftUI

/// The Settings window (⌘,). One tab per topic, each a grouped Form sized
/// to its content.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: SettingsTab = .current

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
        .onChange(of: tab) { _, value in SettingsTab.current = value }
        .onReceive(NotificationCenter.default.publisher(for: SettingsTab.select)) { note in
            if let value = note.object as? SettingsTab { tab = value }
        }
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .reading: ReadingSettings()
            case .terminal: TerminalSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, reading, terminal

    static let select = Notification.Name("LumeSelectSettingsTab")

    /// Settings reopens on the last tab.
    static var current: SettingsTab {
        get { SettingsTab(rawValue: Store.defaults.string(forKey: "settings.tab") ?? "") ?? .general }
        set { Store.defaults.set(newValue.rawValue, forKey: "settings.tab") }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Geral"
        case .reading: "Leitura"
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .reading: "textformat"
        case .terminal: "apple.terminal"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            Toggle("Reabrir o último documento ao abrir o Lume", isOn: $prefs.reopenLast)
                .controlSize(.mini)
        }
        Section {
            LabeledContent("Documentos recentes") {
                Button("Limpar Lista") { model.clearRecents() }
                    .disabled(model.recents.isEmpty)
            }
        } footer: {
            Text("A lista fica somente neste Mac. Editar > Desfazer traz a lista de volta.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ReadingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            Picker("Tema", selection: $prefs.theme) {
                ForEach(ReadingTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            ThemeStrip(selected: $prefs.theme)
        } footer: {
            Text(prefs.theme.summary).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Tamanho do texto") {
                HStack(spacing: Space.sm) {
                    Slider(value: $prefs.scale, in: ReaderScale.minimum...ReaderScale.maximum, step: ReaderScale.step)
                        .frame(width: 180)
                    Text(prefs.scale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            Picker("Largura da leitura", selection: $prefs.width) {
                ForEach(ReadingWidth.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        Section("Editor") {
            Toggle("Mostrar números de linha", isOn: $prefs.showLineNumbers)
                .controlSize(.mini)
        }
    }
}

/// A row of small page samples, one per theme. Clicking one picks it.
private struct ThemeStrip: View {
    @Binding var selected: ReadingTheme

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(ReadingTheme.allCases.filter { $0 != .automatic }) { theme in
                let swatch = theme.swatch
                let isOn = selected == theme
                Button {
                    selected = theme
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color(hex: swatch.text)).frame(width: 24, height: 4)
                        Capsule().fill(Color(hex: swatch.text).opacity(0.5)).frame(width: 32, height: 4)
                        Capsule().fill(Color(hex: swatch.accent)).frame(width: 12, height: 4)
                    }
                    .frame(width: 52, height: 36)
                    .background(Color(hex: swatch.background), in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                          lineWidth: isOn ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(theme.label)
                .accessibilityLabel(theme.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct TerminalSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ForEach(TerminalPalette.fields, id: \.name) { field in
                ColorPicker(field.label, selection: binding(field.key), supportsOpacity: false)
            }
        } header: {
            Text("Cores do tema Terminal")
        } footer: {
            Text(model.prefs.theme == .terminal
                 ? "As mudanças aparecem no documento na hora."
                 : "Valem quando o tema Terminal está em uso.")
                .foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Cores originais") {
                Button("Restaurar") { restore() }
                    .disabled(model.prefs.terminal == TerminalPalette())
            }
        }
    }

    private func binding(_ key: WritableKeyPath<TerminalPalette, String>) -> Binding<Color> {
        Binding(get: {
            Color(hex: UInt32(model.prefs.terminal[keyPath: key].dropFirst(), radix: 16) ?? 0)
        }, set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02x%02x%02x",
                             Int((srgb.redComponent * 255).rounded()),
                             Int((srgb.greenComponent * 255).rounded()),
                             Int((srgb.blueComponent * 255).rounded()))
            model.prefs.terminal[keyPath: key] = hex
        })
    }

    /// Restores the default colors, with Undo.
    private func restore() {
        let previous = model.prefs.terminal
        model.prefs.terminal = TerminalPalette()
        let undo = NSApp.keyWindow?.undoManager
        undo?.registerUndo(withTarget: model.prefs) { prefs in prefs.terminal = previous }
        undo?.setActionName("Restaurar Cores")
    }
}
