import AppKit
import LumeKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Owns the reading WKWebView and talks to Resources/Web/reader.js.
/// The page renders Markdown with marked and DOMPurify; the window around
/// it is SwiftUI.
final class ReaderController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var model: AppModel?
    let webView: ReaderWebView
    private(set) var isReady = false
    private var queued: [String] = []
    private var renderedPath: String?
    private var renderedContent: String?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LumeSchemeHandler(), forURLScheme: "lume")
        configuration.suppressesIncrementalRendering = true
        webView = ReaderWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "lume")
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.setAccessibilityLabel("Documento")
        webView.load(URLRequest(url: URL(string: "lume://app/index.html")!))
    }

    // MARK: Calls into the page

    /// Calls Lume.<function>(...arguments), with the arguments sent as JSON.
    private func call(_ function: String, _ arguments: Any...) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "Lume.\(function)(...\(json))"
        if isReady {
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            queued.append(script)
        }
    }

    /// Shows `file`. A new document starts at its saved place; the same one
    /// re-renders in place after an edit or an outside change.
    func show(_ file: DocumentFile, ratio: Double, heading: String?) {
        let body = Frontmatter.split(file.content).body
        let directory = file.url?.deletingLastPathComponent().path(percentEncoded: false) ?? ""
        if renderedPath == file.path {
            guard renderedContent != file.content || heading != nil else { return }
            renderedContent = file.content
            if let heading {
                call("render", ["markdown": body, "docDir": directory, "heading": heading])
            } else {
                call("refresh", ["markdown": body, "docDir": directory])
            }
            return
        }
        renderedPath = file.path
        renderedContent = file.content
        call("render", ["markdown": body, "docDir": directory, "ratio": ratio, "heading": heading ?? ""])
    }

    func clear() {
        renderedPath = nil
        renderedContent = nil
        call("render", ["markdown": "", "docDir": ""])
    }

    func setAppearance(theme: ReadingTheme, width: ReadingWidth, scale: Double, terminal: TerminalPalette) {
        let colors = theme.swatch
        webView.underPageBackgroundColor = NSColor(hex: colors.background)
        call("setAppearance", [
            "theme": theme.rawValue,
            "width": width.rawValue,
            "scale": scale,
            "terminal": terminal.cssValues,
        ])
    }

    func search(_ query: String, active: Int) {
        call("search", query, active)
    }

    func scrollTo(heading: String) {
        call("scrollToHeading", heading)
    }

    func printDocument(window: NSWindow?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 48
        info.rightMargin = 48
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    // MARK: Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let name = body["name"] as? String, let model else { return }
        switch name {
        case "ready":
            isReady = true
            queued.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
            queued = []
        case "outline":
            let items = body["items"] as? [[String: Any]] ?? []
            model.outline = items.compactMap { item in
                guard let id = item["id"] as? String, let label = item["label"] as? String else { return nil }
                return OutlineItem(id: id, label: label, depth: item["depth"] as? Int ?? 1)
            }
            model.pendingHeading = nil
        case "scroll":
            let ratio = body["ratio"] as? Double ?? 0
            if let path = model.currentPath {
                model.scrollPositions[path] = ratio
                model.prefs.set(ratio, for: "restore.ratio")
            }
            let heading = body["heading"] as? String
            model.currentHeading = heading?.isEmpty == true ? nil : heading
        case "search":
            model.find.count = body["count"] as? Int ?? 0
            model.find.active = body["active"] as? Int ?? 0
        case "link":
            model.followLink(kind: body["kind"] as? String ?? "", target: body["target"] as? String ?? "")
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
        default:
            break
        }
    }

    /// Only the reader page itself loads. Links go through followLink.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.request.url?.absoluteString == "lume://app/index.html" ? .allow : .cancel
    }

    /// The page process can be reclaimed by the system; load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        renderedPath = nil
        renderedContent = nil
        webView.load(URLRequest(url: URL(string: "lume://app/index.html")!))
    }
}

/// WKUserContentController keeps its handler strongly. This breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The reader's web view: drops reach SwiftUI's drop target, and the
/// context menu keeps only what makes sense for a document.
final class ReaderWebView: WKWebView {
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        // Files dropped on the page open in the app instead of replacing the page.
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let unwanted = ["Reload", "OpenLink", "Download", "OpenImage", "OpenFrame", "Back", "Forward"]
        for item in menu.items where unwanted.contains(where: { item.identifier?.rawValue.contains($0) == true }) {
            menu.removeItem(item)
        }
        super.willOpenMenu(menu, with: event)
    }
}

/// Serves the reader page from the app bundle (lume://app/...) and images
/// next to the document from disk (lume://file/<absolute path>).
final class LumeSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp", "tif", "tiff"]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = fileURL(for: url),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: fileURL.pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let isText = type?.conforms(to: .text) == true || ["js", "css", "html"].contains(fileURL.pathExtension)
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                   textEncodingName: isText ? "utf-8" : nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func fileURL(for url: URL) -> URL? {
        let path = url.path(percentEncoded: false)
        switch url.host() {
        case "app":
            guard let web = Bundle.main.resourceURL?.appending(path: "Web").standardizedFileURL else { return nil }
            let file = web.appending(path: path).standardizedFileURL
            return file.path.hasPrefix(web.path + "/") ? file : nil
        case "file":
            let file = URL(fileURLWithPath: path).standardizedFileURL
            return Self.imageTypes.contains(file.pathExtension.lowercased()) ? file : nil
        default:
            return nil
        }
    }
}

/// The web view in SwiftUI. The controller keeps it alive between documents.
struct ReaderPane: NSViewRepresentable {
    let controller: ReaderController

    func makeNSView(context: Context) -> ReaderWebView { controller.webView }
    func updateNSView(_ view: ReaderWebView, context: Context) {}
}
