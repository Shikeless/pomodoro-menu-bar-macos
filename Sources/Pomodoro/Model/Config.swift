import Foundation

enum Limits {
    static let minutes = 1...60
    static let rounds  = 1...10
}

func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
    min(range.upperBound, max(range.lowerBound, value))
}

/// Phase lengths in minutes plus the round count. Everything else the app
/// shows is derived from these four numbers.
struct Config: Codable, Equatable {
    var sitting  = 25
    var standing = 5
    var rest     = 15
    var rounds   = 4

    // "break" is a Swift keyword, so the stored key and the property differ.
    enum CodingKeys: String, CodingKey {
        case sitting, standing, rounds
        case rest = "break"
    }

    subscript(phase: Phase) -> Int {
        switch phase {
        case .sitting:  return sitting
        case .standing: return standing
        case .rest:     return rest
        }
    }

    static func keyPath(for phase: Phase) -> WritableKeyPath<Config, Int> {
        switch phase {
        case .sitting:  return \.sitting
        case .standing: return \.standing
        case .rest:     return \.rest
        }
    }

    /// One full pass through all three phases.
    var cycle: TimeInterval {
        TimeInterval(Phase.allCases.reduce(0) { $0 + self[$1] }) * 60
    }

    var clamped: Config {
        Config(
            sitting:  clamp(sitting,  to: Limits.minutes),
            standing: clamp(standing, to: Limits.minutes),
            rest:     clamp(rest,     to: Limits.minutes),
            rounds:   clamp(rounds,   to: Limits.rounds)
        )
    }
}
