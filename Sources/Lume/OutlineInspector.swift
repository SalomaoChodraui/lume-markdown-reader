import LumeKit
import SwiftUI

/// The inspector: the document's headings and its front matter.
struct OutlineInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            if !model.outline.isEmpty {
                Section("Sumário") {
                    ForEach(model.outline) { item in
                        Text(item.label)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(item.depth - 1) * Space.md)
                            .listRowSeparator(.hidden)
                            .tag(item.id)
                    }
                }
            }
            let properties = model.properties
            if !properties.isEmpty {
                Section("Propriedades") {
                    ForEach(properties, id: \.key) { property in
                        LabeledContent(property.key) {
                            Text(property.value).textSelection(.enabled)
                        }
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .overlay {
            // Plain text, not ContentUnavailableView: its minimum width fights
            // the inspector column's and loops the window's layout at 720 pt.
            if model.current == nil || (model.outline.isEmpty && model.properties.isEmpty) {
                Text(model.current == nil ? "Abra um documento para ver os títulos dele." : "Este documento não tem títulos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(Space.lg)
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.currentHeading }, set: { id in
            guard let id else { return }
            model.currentHeading = id
            if model.editing {
                scrollEditor(to: id)
            } else {
                model.reader.scrollTo(heading: id)
            }
        })
    }

    /// In the editor, jump to the line of the heading.
    private func scrollEditor(to id: String) {
        guard let editor = model.editorView, let item = model.outline.first(where: { $0.id == id }) else { return }
        let text = editor.string as NSString
        var found: NSRange?
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { line, range, _, stop in
            if let line, line.hasPrefix("#"), line.contains(item.label) {
                found = range
                stop.pointee = true
            }
        }
        guard let found else { return }
        editor.setSelectedRange(NSRange(location: found.location, length: 0))
        editor.scrollRangeToVisible(found)
        editor.window?.makeFirstResponder(editor)
    }
}
