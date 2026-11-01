import AppKit
import SwiftUI

extension View {
    /// Opens the window with nothing focused: no focus ring and no text
    /// cursor until the person clicks or presses Tab. Use it on every window
    /// and sheet, except one whose only job is typing (a search or quick-add
    /// panel focuses its field on purpose).
    func noInitialFocus() -> some View {
        background(WindowHook())
    }

    /// Sizes a Form, List, or ScrollView to its content, up to `max` points.
    /// A Settings page or sheet then grows to fit, and scrolls only when its
    /// content is taller than `max`.
    func fitsContent(max: CGFloat = 640) -> some View {
        modifier(FitsContent(max: max))
    }
}

private struct FitsContent: ViewModifier {
    var max: CGFloat
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                // Only the content's own height: the insets change as the window
                // resizes, which would start a resize loop.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height.rounded(.up)
                } action: { _, new in
                    if abs(new - (height ?? 0)) >= 1 { height = new }
                }
                .frame(height: height.map { min($0, max) })
                .scrollBounceBehavior(.basedOnSize)
        } else {
            // macOS 14 cannot read the scroll content height: keep the form's own size.
            content
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A zero-size view that reaches the NSWindow it sits in.
private struct WindowHook: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        private var reopened = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NotificationCenter.default.removeObserver(self)
            clear(window)
            // A closed window keeps its views. Clear again when it opens next time.
            NotificationCenter.default.addObserver(self, selector: #selector(willClose),
                                                   name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKey),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
        }

        @objc private func willClose(_ note: Notification) {
            reopened = true
        }

        @objc private func didBecomeKey(_ note: Notification) {
            guard reopened, let window else { return }
            reopened = false
            clear(window)
        }

        /// AppKit picks a first control right after the window shows. Clear it after that.
        private func clear(_ window: NSWindow) {
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
        }
    }
}

/// Hands the hosting NSWindow to SwiftUI code, and guards its close button:
/// a window with unsaved edits asks first (Save, Don't Save, Cancel).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onWindow = onWindow
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        private var guardian: CloseGuard?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow?(window)
            if guardian == nil || window.delegate !== guardian {
                let guardian = CloseGuard(window: window)
                self.guardian = guardian
            }
        }
    }
}

/// Sits in front of SwiftUI's window delegate and forwards everything,
/// except that it asks about unsaved changes before the window closes.
final class CloseGuard: NSObject, NSWindowDelegate {
    // Strong: the window holds its delegate weakly, and SwiftUI's must stay alive.
    // Read from responds(to:) and forwardingTarget(for:), which AppKit calls on the main thread.
    nonisolated(unsafe) private var original: NSWindowDelegate?
    private var closing = false

    init(window: NSWindow) {
        original = window.delegate
        super.init()
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return original?.windowShouldClose?(sender) ?? true }
        let model = AppModel.shared
        guard model.hasUnsaved else { return original?.windowShouldClose?(sender) ?? true }
        Task {
            if await model.resolveUnsaved(action: "fechar a janela") {
                closing = true
                sender.performClose(nil)
                closing = false
            }
        }
        return false
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
