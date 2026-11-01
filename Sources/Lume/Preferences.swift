import Foundation
import LumeKit
import Observation

/// Test runs (snapshots, self-test) set APP_STORE and keep their settings
/// in a separate, emptied suite, so they never touch the real ones.
enum Store {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static let defaults: UserDefaults = {
        guard isOverridden else { return .standard }
        let suite = "com.lume.markdown-reader.test"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }()
}

/// Reading and window preferences. Each change is saved at once.
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var theme: ReadingTheme { didSet { defaults.set(theme.rawValue, forKey: "reading.theme") } }
    var scale: Double { didSet { defaults.set(scale, forKey: "reading.scale") } }
    var width: ReadingWidth { didSet { defaults.set(width.rawValue, forKey: "reading.width") } }
    var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: "editor.lineNumbers") } }
    var reopenLast: Bool { didSet { defaults.set(reopenLast, forKey: "general.reopenLast") } }
    var terminal: TerminalPalette {
        didSet { defaults.set(try? JSONEncoder().encode(terminal), forKey: "reading.terminal") }
    }

    init(defaults: UserDefaults = Store.defaults) {
        self.defaults = defaults
        theme = ReadingTheme(rawValue: defaults.string(forKey: "reading.theme") ?? "") ?? .automatic
        let storedScale = defaults.double(forKey: "reading.scale")
        scale = storedScale == 0 ? 1 : ReaderScale.clamp(storedScale)
        width = ReadingWidth(rawValue: defaults.string(forKey: "reading.width") ?? "") ?? .auto
        showLineNumbers = defaults.object(forKey: "editor.lineNumbers") as? Bool ?? true
        reopenLast = defaults.object(forKey: "general.reopenLast") as? Bool ?? true
        terminal = (defaults.data(forKey: "reading.terminal")).flatMap { try? JSONDecoder().decode(TerminalPalette.self, from: $0) } ?? TerminalPalette()
    }

    func value<T>(_ key: String) -> T? { defaults.object(forKey: key) as? T }
    func set(_ value: Any?, for key: String) { defaults.set(value, forKey: key) }
}
