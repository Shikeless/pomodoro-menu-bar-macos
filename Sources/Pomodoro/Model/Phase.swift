import AppKit
import SwiftUI

/// The three legs of one round, in the order they run.
enum Phase: String, CaseIterable, Codable, Identifiable {
    case sitting
    case standing
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sitting:  return "Sitting"
        case .standing: return "Standing"
        case .rest:     return "Break"
        }
    }

    /// Same palette as the web version (Tokyo Night).
    var color: Color {
        switch self {
        case .sitting:  return Color(red: 0.969, green: 0.463, blue: 0.557)   // #f7768e
        case .standing: return Color(red: 0.620, green: 0.808, blue: 0.416)   // #9ece6a
        case .rest:     return Color(red: 0.478, green: 0.635, blue: 0.968)   // #7aa2f7
        }
    }

    /// The menu bar renders its label as a template image, so the phase reads
    /// as a glyph rather than a colour once it is up there.
    var symbol: String {
        switch self {
        case .sitting:  return SymbolName.resolve("figure.seated.side", fallback: "person.fill")
        case .standing: return SymbolName.resolve("figure.stand", fallback: "person.fill")
        case .rest:     return SymbolName.resolve("cup.and.saucer.fill", fallback: "moon.fill")
        }
    }
}

/// SF Symbols come and go between OS releases; an unknown name renders as a
/// blank status item, which would look like a crash. Ask AppKit first.
enum SymbolName {
    static func resolve(_ name: String, fallback: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
    }

    static let done = resolve("checkmark.circle.fill", fallback: "circle.fill")
    static let rounds = resolve("repeat", fallback: "arrow.clockwise")
}
