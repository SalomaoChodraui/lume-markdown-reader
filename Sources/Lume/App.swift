import AppKit
import SwiftUI

// Lume, a calm Markdown reader.
//   Lume                       the app
//   APP_STORE=<file> Lume      keep settings in a separate test suite (snapshots, self-test)
//   APP_SNAPSHOT=<dir> Lume    save a PNG of every surface in light and dark mode, then quit
//   Lume --selftest            run the self-test and quit with 0 or 1 (tools/selftest.sh)
//   APP_GRID=1 Lume            draw the 8 pt grid and the layout probes over the window

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Lume", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 900, minHeight: 460)
        }
        .defaultSize(width: 1240, height: 800)
        .windowToolbarStyle(.unified)
        .commands { LumeCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Files and folders from Finder, the Dock icon, or "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.openFromSystem(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quit asks only when typed work would be lost.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.hasUnsaved, !SelfTest.requested, !Snapshot.requested else { return .terminateNow }
        Task {
            let proceed = await model.resolveUnsaved(action: "sair")
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Abrir…", action: #selector(openFromDock), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        return menu
    }

    @objc private func openFromDock() {
        NSApp.activate()
        AppModel.shared.showOpenPanel()
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
