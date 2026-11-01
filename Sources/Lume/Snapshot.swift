import AppKit
import IOKit.pwr_mgt
import LumeKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/Lume-test APP_SNAPSHOT=/tmp/Lume-shots ~/Applications/Lume.app/Contents/MacOS/Lume
/// writes <page>-light.png and <page>-dark.png for every surface, and
/// settings-<tab>-light.png and -dark.png for every Settings tab, then quits.
/// APP_SNAPSHOT_PAGES=reader,settings limits the pages.
enum Snapshot {
    static var requested: Bool {
        !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty
    }

    /// The surfaces, in order. Each sets the window up before the capture.
    enum Page: String, CaseIterable {
        case empty, reader, find, editor, search, sepia, terminal, narrow
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a path in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
            let frame = main?.frame
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in Page.allCases where only?.contains(page.rawValue) ?? true {
                    await prepare(page, model: model, window: main, frame: frame)
                    try? await Task.sleep(for: .seconds(1.2))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if let frame { main?.setFrame(frame, display: true) }
            if only == nil || only?.contains("settings") == true {
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        NotificationCenter.default.post(name: SettingsTab.select, object: tab)
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.canBecomeKey }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    private static func prepare(_ page: Page, model: AppModel, window: NSWindow?, frame: NSRect?) async {
        model.editing = false
        model.closeFind()
        model.fileQuery = ""
        model.prefs.theme = .automatic
        if let frame { window?.setFrame(frame, display: true) }
        switch page {
        case .empty:
            break
        case .reader, .sepia, .terminal, .narrow:
            if model.kind != .guide { await model.openGuide() }
            model.navigate(to: "Boas-vindas.md")
            if page == .sepia { model.prefs.theme = .sepia }
            if page == .terminal { model.prefs.theme = .terminal }
            if page == .narrow, let frame {
                window?.setFrame(NSRect(x: frame.minX, y: frame.minY, width: 900, height: frame.height), display: true)
            }
        case .find:
            model.navigate(to: "Boas-vindas.md")
            model.startFind()
            model.find.query = "leitura"
            model.reader.search("leitura", active: 0)
        case .editor:
            model.navigate(to: "Atalhos.md")
            model.editing = true
        case .search:
            model.fileQuery = "tema"
            model.focusFileSearch()
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one.
    private static func capture(to path: String, window: NSWindow? = nil) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        print("SNAPSHOT failed \(path)")
    }
}
