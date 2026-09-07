import Foundation

/// A sound to fire at a fixed offset from the moment Start was first pressed.
struct Mark {
    let at: TimeInterval
    let kind: ToneKind
}

/// A run snapshots its config at Start, so editing the fields mid-run can never
/// resize the segments out from under a moving fill.
struct Session {
    let config: Config
    let cycle: TimeInterval
    let total: TimeInterval
    let marks: [Mark]

    /// Time banked from previous runs; excludes the stretch currently running.
    var rested: TimeInterval = 0
    /// Wall clock at the last resume; nil while paused.
    var startedAt: Date?
    /// Marks below this index are spent, so pausing cannot replay them.
    var nextMark = 0

    /// Seconds before a phase ends at which the short warning tones fire.
    static let warnLeads: [TimeInterval] = [5, 4, 3]

    init(config: Config) {
        self.config = config
        self.cycle = config.cycle
        self.total = cycle * TimeInterval(config.rounds)
        self.marks = Session.buildMarks(config: config, cycle: cycle)
    }

    var isRunning: Bool { startedAt != nil }

    /// Re-derived from the wall clock rather than accumulated, so a stretch
    /// where no timer fired (system sleep, a stalled run loop) resumes at the
    /// correct position instead of drifting behind by however long it lasted.
    func elapsed(now: Date = Date()) -> TimeInterval {
        let live = startedAt.map { now.timeIntervalSince($0) } ?? 0
        return min(total, max(0, rested + live))
    }

    func isComplete(now: Date = Date()) -> Bool { elapsed(now: now) >= total }

    /// Every sound the session will ever make, as absolute offsets from Start.
    /// Precomputing them makes firing a walk down a list — no per-tick window
    /// arithmetic, and no way to sound a mark twice.
    private static func buildMarks(config: Config, cycle: TimeInterval) -> [Mark] {
        var marks: [Mark] = []
        for round in 0..<config.rounds {
            var at = TimeInterval(round) * cycle
            for phase in Phase.allCases {
                at += TimeInterval(config[phase]) * 60   // the instant this phase ends
                for lead in warnLeads { marks.append(Mark(at: at - lead, kind: .warn)) }
                marks.append(Mark(at: at, kind: .accent))
            }
        }
        return marks   // already ascending: leads precede their accent, rounds are sequential
    }
}

/// Everything the UI draws, resolved in one place so the bar, the clock and the
/// menu bar title can never disagree about where the run is.
struct Readout: Equatable {
    var phase: Phase = .sitting
    var round: Int = 1
    var rounds: Int = 4
    /// Time left in the current round — clock and bar share that one span.
    var remaining: TimeInterval = 0
    /// How far the fill edge has crossed the current round, 0...1.
    var progress: Double = 0
    var isComplete = false
    var isRunning = false
    var isIdle = true

    /// Start doubles as Resume once a run is parked mid-way.
    var isPaused: Bool { !isIdle && !isRunning && !isComplete }
    /// The fields lock for the duration of a run, as in the web version.
    var fieldsEnabled: Bool { isIdle || isComplete }

    var phaseTitle: String { isComplete ? "Done" : phase.title }
    var symbol: String { isComplete ? SymbolName.done : phase.symbol }
    var clock: String { Readout.format(remaining) }

    /// A round can reach three hours (60 min x 3 phases), so the hours field
    /// appears only once it is needed and mm:ss stays the common case.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let hours = total / 3600
        let rest = String(format: "%02d:%02d", (total % 3600) / 60, total % 60)
        return hours > 0 ? "\(hours):\(rest)" : rest
    }

    /// The fill edge sits inside exactly one phase; that phase names the display.
    static func make(config: Config, session: Session?, now: Date = Date()) -> Readout {
        let cfg = session?.config ?? config
        let cycle = session?.cycle ?? cfg.cycle
        let done = session?.elapsed(now: now) ?? 0
        let complete = session?.isComplete(now: now) ?? false

        // Rounds are read off the total rather than counted, so any number of
        // them can elapse unobserved and the display still lands right.
        let round = complete ? cfg.rounds : Int(done / cycle) + 1
        let intoCycle = complete ? cycle : done.truncatingRemainder(dividingBy: cycle)

        var offset = intoCycle
        var active = Phase.allCases[0]
        for phase in Phase.allCases {
            active = phase
            if offset < TimeInterval(cfg[phase]) * 60 { break }
            offset -= TimeInterval(cfg[phase]) * 60
        }

        return Readout(
            phase: active,
            round: round,
            rounds: cfg.rounds,
            remaining: cycle - intoCycle,
            progress: cycle > 0 ? intoCycle / cycle : 0,
            isComplete: complete,
            isRunning: session?.isRunning ?? false,
            isIdle: session == nil
        )
    }
}
