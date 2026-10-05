import MacGamesCore
import SwiftUI

extension Color {
    /// `hex` is "RRGGBB".
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension GameProfile {
    var accent: Color { Color(hex: presentation.accentHex) ?? Color(red: 0.55, green: 0.62, blue: 0.75) }
    /// Text color that stays readable on the accent (WCAG relative luminance).
    var onAccent: Color {
        guard let hex = presentation.accentHex, let v = UInt32(hex, radix: 16) else { return .white }
        func linear(_ c: UInt32) -> Double { let s = Double(c) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * linear((v >> 16) & 0xFF) + 0.7152 * linear((v >> 8) & 0xFF) + 0.0722 * linear(v & 0xFF)
        return l > 0.4 ? .black.opacity(0.85) : .white
    }
    var heroFocus: UnitPoint { UnitPoint(x: presentation.heroFocus.x, y: presentation.heroFocus.y) }
}

extension GameState {
    /// One line for the game page.
    var summary: String {
        switch self {
        case .notSetUp: "This game needs its own Windows environment and Steam. Setup takes about a minute."
        case .needsSteam: "Windows is ready. Steam is not installed yet."
        case .needsGame: "Install the game in Steam and keep the default folder. Sign in first if Steam asks."
        case .installing: "Steam is downloading the game."
        case .ready: "Ready to play."
        case .running: "Playing now."
        }
    }

    /// A few words for the sidebar.
    var shortSummary: String {
        switch self {
        case .notSetUp: "Not set up"
        case .needsSteam: "Needs Steam"
        case .needsGame: "Not installed"
        case .installing: "Downloading"
        case .ready: "Ready"
        case .running: "Playing"
        }
    }

    var actionTitle: String {
        switch self {
        case .notSetUp: "Set up"
        case .needsSteam: "Install Steam"
        case .needsGame: "Install in Steam"
        case .installing: "Show download"
        case .ready: "Play"
        case .running: "Stop"
        }
    }

    var actionSymbol: String {
        switch self {
        case .notSetUp: "wand.and.sparkles"
        case .needsSteam: "arrow.down.circle.fill"
        case .needsGame: "arrow.down.to.line"
        case .installing: "arrow.down.circle.dotted"
        case .ready: "play.fill"
        case .running: "stop.fill"
        }
    }
}

/// One spacing scale for the whole app.
enum Space {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    /// Left edge of the game page: the logo, the buttons and the sections all start here.
    static let page: CGFloat = 40
    static let sidebarInset: CGFloat = 12
}

/// Shared motion values, so every transition in the app feels the same.
enum Motion {
    static let switchGame = Animation.spring(duration: 0.55, bounce: 0.18)
    static let morph = Animation.spring(duration: 0.4, bounce: 0.25)
    static let reveal = Animation.easeOut(duration: 0.45)
}
