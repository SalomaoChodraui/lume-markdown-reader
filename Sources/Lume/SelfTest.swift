import AppKit
import LumeKit

/// Self-test for agents: runs the app's real functions on a folder in /tmp,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Lume-self ~/Applications/Lume.app/Contents/MacOS/Lume --selftest
/// (tools/selftest.sh does this.)
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a path in /tmp")
            finish(code: 1)
            return
        }
        Task { await run(model) }
    }

    private static func run(_ model: AppModel) async {
        let root = URL(fileURLWithPath: "/tmp/Lume-selftest-library")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root.appending(path: "notas"), withIntermediateDirectories: true)
        func write(_ path: String, _ text: String) {
            try? text.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
        }
        write("Início.md", """
        ---
        status: rascunho
        ---
        # Início

        Veja [[Ideia]] e `[[Literal]]`.

        > [!NOTE]
        > Uma nota.

        ## Segunda parte
        """)
        write("notas/Ideia.md", "# Ideia\n\n## Seção dois\n\nTexto com a palavra lume e Lume.")
        write("notas/Outra.md", "# Outra\n")
        try? await Task.sleep(for: .seconds(0.5))

        await model.open(root, askFirst: false)
        check("a folder opens with every Markdown file", model.files.count == 3, "\(model.files.count)")
        check("folders come first in the sidebar", model.tree.first?.name == "notas")
        check("the first top-level file opens", model.currentPath == "Início.md", model.currentPath ?? "nil")
        check("front matter becomes properties", model.properties == [Property(key: "status", value: "rascunho")])
        check("the folder is a recent item", model.recents.first?.path == root.path)

        await waitUntil { model.outline.count == 2 }
        check("the outline lists the headings", model.outline.map(\.label) == ["Início", "Segunda parte"],
              model.outline.map(\.label).joined(separator: ","))
        let callout = await javaScript("document.querySelector('.callout-title')?.textContent")
        check("> [!NOTE] renders as a callout", callout == "Nota", callout ?? "nil")
        let code = await javaScript("document.querySelector('p code')?.textContent")
        check("wiki syntax inside code stays literal", code == "[[Literal]]", code ?? "nil")
        let link = await javaScript("document.querySelector('a.wikilink')?.textContent")
        check("wiki links render as links", link == "Ideia", link ?? "nil")

        model.followLink(kind: "wiki", target: "Ideia")
        check("a wiki link opens the note", model.currentPath == "notas/Ideia.md")
        check("its folder expands in the sidebar", model.expanded.contains("notas"))
        model.goBack()
        check("Back returns to the first note", model.currentPath == "Início.md")
        check("Forward is available after Back", model.canGoForward)
        model.followLink(kind: "wiki", target: "Ideia#Seção dois")
        check("a link to a section keeps the heading", model.currentPath == "notas/Ideia.md")

        await waitUntil { model.outline.first?.label == "Ideia" }
        model.find.isVisible = true
        model.find.query = "lume"
        model.reader.search("lume", active: 0)
        await waitUntil { model.find.count == 2 }
        check("find counts matches ignoring case", model.find.count == 2, "\(model.find.count)")
        model.findNext(1)
        await waitUntil { model.find.active == 1 }
        check("find moves to the next match", model.find.active == 1)
        model.closeFind()

        model.fileQuery = "seção"
        check("file search matches content without accents", model.searchResults.map(\.path) == ["notas/Ideia.md"])
        model.fileQuery = ""

        guard let file = model.current else { return finish(code: 1) }
        file.content += "\nmais uma linha"
        check("an edit marks the document unsaved", model.hasUnsaved)
        check("Save is enabled", model.canSave)
        let saved = await model.save(file)
        let onDisk = try? String(contentsOf: root.appending(path: "notas/Ideia.md"), encoding: .utf8)
        check("Save writes the file", saved && onDisk?.hasSuffix("mais uma linha") == true)
        check("after Save nothing is unsaved", !model.hasUnsaved)

        try? await Task.sleep(for: .seconds(1.1))
        write("notas/Ideia.md", "# Ideia\n\nMudado por outro app.")
        model.checkForOutsideChanges()
        check("a change saved by another app reloads", file.content.contains("outro app"))

        file.content += "\nrascunho"
        model.unsavedAnswer = .cancel
        let cancelled = await model.resolveUnsaved(action: "teste")
        check("Cancel keeps the unsaved edit", !cancelled && model.hasUnsaved)
        if let window = model.window {
            window.performClose(nil)
            try? await Task.sleep(for: .seconds(0.5))
            check("closing the window with edits asks first", window.isVisible)
        }
        model.unsavedAnswer = .discard
        let discarded = await model.resolveUnsaved(action: "teste")
        check("Don't Save drops the edit", discarded && !model.hasUnsaved)
        model.unsavedAnswer = nil

        write("notas/Nova.md", "# Nova")
        await model.rescanFolder()
        check("a file added outside the app appears", model.files.contains { $0.path == "notas/Nova.md" })

        model.zoom(1)
        check("Bigger Text steps by 5%", model.prefs.scale == 1.05)
        model.zoom(0)
        check("Actual Size resets", model.prefs.scale == 1)

        await model.openGuide()
        check("the guide opens read only", model.kind == .guide && model.current?.isReadOnly == true)

        print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
        finish(code: failures == 0 ? 0 : 1)
    }

    private static func javaScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            AppModel.shared.reader.webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    private static func waitUntil(timeout: Double = 5, _ condition: () -> Bool) async {
        let end = Date.now.addingTimeInterval(timeout)
        while !condition(), Date.now < end {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
