import AppKit
import SwiftUI

/// The Markdown editor: a plain NSTextView with Undo, the system find bar,
/// and an optional line-number ruler. NSTextView instead of TextEditor,
/// because TextEditor has no ruler and no find bar.
struct MarkdownEditor: NSViewRepresentable {
    let file: DocumentFile
    var showLineNumbers: Bool
    var scale: Double
    var onAttach: (NSTextView?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(file: file) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        // TextKit 1, so the ruler can ask the layout manager where lines are.
        let text = NSTextView(usingTextLayoutManager: false)
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 20, height: 20)
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.smartInsertDeleteEnabled = false
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.textColor = .textColor
        text.insertionPointColor = .controlAccentColor
        text.font = Self.font(scale)
        text.string = file.content
        text.delegate = context.coordinator
        text.setAccessibilityLabel("Markdown de \(file.name)")
        scroll.documentView = text

        let ruler = LineNumberRuler(scrollView: scroll, textView: text)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = showLineNumbers
        context.coordinator.textView = text
        onAttach(text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        scroll.rulersVisible = showLineNumbers
        let font = Self.font(scale)
        if text.font != font {
            text.font = font
            scroll.verticalRulerView?.needsDisplay = true
        }
        // An outside change (another app saved the file) replaces the text.
        if text.string != file.content, !context.coordinator.isTyping {
            text.string = file.content
            text.undoManager?.removeAllActions(withTarget: text.textStorage as Any)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let text = coordinator.textView {
            text.undoManager?.removeAllActions(withTarget: text.textStorage as Any)
            text.undoManager?.removeAllActions(withTarget: text)
        }
    }

    static func font(_ scale: Double) -> NSFont {
        .monospacedSystemFont(ofSize: (13 * scale).rounded(), weight: .regular)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let file: DocumentFile
        weak var textView: NSTextView?
        var isTyping = false

        init(file: DocumentFile) {
            self.file = file
        }

        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            isTyping = true
            file.content = text.string
            isTyping = false
            text.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        /// Tab inserts two spaces, the indent Markdown lists expect.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertTab(_:)) else { return false }
            textView.insertText("  ", replacementRange: textView.selectedRange())
            return true
        }
    }
}

/// Line numbers beside the editor, in the tertiary label color.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func redraw() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let text = textView.string as NSString
        let size = max(10, ((textView.font?.pointSize ?? 13) * 0.85).rounded())
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let digits = max(2, String(max(1, text.components(separatedBy: "\n").count)).count)
        let width = CGFloat(digits) * size * 0.62 + 20
        if abs(ruleThickness - width) > 1 { ruleThickness = width }

        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        text.substring(to: characters.location).forEach { if $0 == "\n" { line += 1 } }
        let origin = textView.textContainerOrigin.y

        func draw(_ number: Int, at y: CGFloat, height: CGFloat) {
            let label = NSAttributedString(string: "\(number)", attributes: attributes)
            let point = convert(NSPoint(x: 0, y: y + origin), from: textView)
            let labelSize = label.size()
            label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 8,
                                   y: point.y + (height - labelSize.height) / 2))
        }

        var index = characters.location
        while index < NSMaxRange(characters) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line, at: fragment.minY, height: fragment.height)
            line += 1
            index = NSMaxRange(lineRange)
        }
        // The empty last line after a final newline, or an empty document.
        let extra = layout.extraLineFragmentRect
        if !extra.isEmpty, extra.intersects(visible) || text.length == 0 {
            draw(line, at: extra.minY, height: extra.height)
        }
    }
}
