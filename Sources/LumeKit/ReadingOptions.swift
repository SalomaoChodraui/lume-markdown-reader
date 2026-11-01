import Foundation

/// The reading palettes. `automatic` follows the Mac: Papel in light mode, Noite in dark.
public enum ReadingTheme: String, CaseIterable, Identifiable, Sendable {
    case automatic, paper, sepia, eink, night, midnight, terminal

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: "Automático"
        case .paper: "Papel"
        case .sepia: "Sépia"
        case .eink: "E-ink"
        case .night: "Noite"
        case .midnight: "Meia-noite"
        case .terminal: "Terminal"
        }
    }

    public var summary: String {
        switch self {
        case .automatic: "Papel no modo claro, Noite no escuro."
        case .paper: "Claro, editorial e neutro."
        case .sepia: "Calor suave dos leitores de e-book."
        case .eink: "Cinza de papel e contraste confortável."
        case .night: "Azul profundo para leitura noturna."
        case .midnight: "Carvão escuro com acentos âmbar."
        case .terminal: "Mono verde, com cores ajustáveis."
        }
    }

    /// The palette to draw, given the Mac's current mode.
    public func resolved(dark: Bool) -> ReadingTheme {
        self == .automatic ? (dark ? .night : .paper) : self
    }

    /// Background, text, and accent, for the swatch in Settings.
    public var swatch: (background: UInt32, text: UInt32, accent: UInt32) {
        switch self {
        case .automatic, .paper: (0xFBFAF6, 0x252521, 0xB84B2C)
        case .sepia: (0xF3EAD9, 0x3F3328, 0x9A6037)
        case .eink: (0xEEEEEA, 0x20211F, 0x476457)
        case .night: (0x121620, 0xE8EAF2, 0x8EA5FF)
        case .midnight: (0x101217, 0xE6E1D8, 0xD5A35E)
        case .terminal: (0x0B0F0C, 0xD9F2DE, 0x63D483)
        }
    }
}

/// How wide the reading column may grow.
public enum ReadingWidth: String, CaseIterable, Identifiable, Sendable {
    case auto, compact, comfortable, wide, full

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "Automática"
        case .compact: "Compacta"
        case .comfortable: "Confortável"
        case .wide: "Ampla"
        case .full: "Janela inteira"
        }
    }

    public var summary: String {
        switch self {
        case .auto: "Cresce junto com o texto"
        case .compact: "Linhas curtas, foco"
        case .comfortable: "Equilíbrio para leitura"
        case .wide: "Mais espaço para tabelas"
        case .full: "Toda a largura disponível"
        }
    }
}

/// Text size as a factor of the base size.
public enum ReaderScale {
    public static let minimum = 0.8
    public static let maximum = 1.6
    public static let step = 0.05

    public static func clamp(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }

    /// One step up (+1) or down (-1), rounded to two decimals.
    public static func step(_ value: Double, by direction: Int) -> Double {
        (clamp(value + step * Double(direction)) * 100).rounded() / 100
    }
}

/// The Terminal palette, as hex strings the reader's CSS reads.
public struct TerminalPalette: Codable, Equatable, Sendable {
    public var background = "#0b0f0c"
    public var surface = "#111812"
    public var text = "#d9f2de"
    public var muted = "#7f9f87"
    public var accent = "#63d483"
    public var heading1 = "#f2f7d7"
    public var heading2 = "#7ee787"
    public var heading3 = "#79c0ff"

    public init() {}

    public static var fields: [(key: WritableKeyPath<TerminalPalette, String>, name: String, label: String)] { [
        (\.background, "background", "Fundo"),
        (\.surface, "surface", "Blocos de código"),
        (\.text, "text", "Texto"),
        (\.muted, "muted", "Texto secundário"),
        (\.accent, "accent", "Destaque"),
        (\.heading1, "heading1", "Título 1"),
        (\.heading2, "heading2", "Título 2"),
        (\.heading3, "heading3", "Título 3"),
    ] }

    /// CSS variable names (without the prefix) and values.
    public var cssValues: [String: String] {
        Dictionary(uniqueKeysWithValues: Self.fields.map { ($0.name, Self.valid(self[keyPath: $0.key]) ?? TerminalPalette()[keyPath: $0.key]) })
    }

    /// "#a1b2c3" when the value is a 6-digit hex color, else nil.
    public static func valid(_ value: String) -> String? {
        value.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) == nil ? nil : value.lowercased()
    }
}

/// Recently opened files and folders, newest first.
public struct RecentItem: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var isFolder: Bool
    public var opened: Date

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, isFolder: Bool, opened: Date = .now) {
        self.path = path
        self.isFolder = isFolder
        self.opened = opened
    }

    /// Puts `item` first, drops an older entry for the same path, keeps `limit`.
    public static func adding(_ item: RecentItem, to list: [RecentItem], limit: Int = 10) -> [RecentItem] {
        Array(([item] + list.filter { $0.path != item.path }).prefix(limit))
    }
}
