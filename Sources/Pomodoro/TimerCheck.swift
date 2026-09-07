import Foundation

/// `Pomodoro --timer-check` drives the real TimerEngine across a phase boundary
/// and counts the tones that actually reach the mixer, so a broken tick loop can
/// be told apart from a broken synthesizer.
@MainActor
enum TimerCheck {
    static func run() -> Bool {
        let suite = "pomodoro.timercheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            print("could not open a scratch defaults suite")
            return false
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        // One-minute phases, parked six seconds short of the first change: the
        // warnings land at 55/56/57 and the accent at 60.
        let store = Store(defaults: defaults)
        store.save(Saved(config: Config(sitting: 1, standing: 1, rest: 1, rounds: 1), elapsed: 54))

        let engine = TimerEngine(store: store)
        print("restored:  \(engine.readout.clock) left, paused as expected: \(engine.readout.isPaused)")

        engine.start()
        print("running:   \(engine.isRunning)")

        var onsets = 0
        var loud = false
        var peak: Float = 0
        engine.tone.probe { level in
            peak = max(peak, level)
            if level > 0.02, !loud { loud = true; onsets += 1 }
            if level < 0.005 { loud = false }
        }

        print("\nwatching for nine seconds across the 1:00 boundary...")
        var seen: [String] = []
        for _ in 0..<9 {
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            seen.append("\(engine.readout.clock) \(engine.readout.phaseTitle) tones:\(onsets)")
        }
        engine.tone.removeProbe()
        engine.pause()

        seen.forEach { print("  \($0)") }
        print("\ntones heard: \(onsets)  (expected 4: three warnings and the change)")
        print("peak level:  \(peak)")

        let ok = onsets >= 4 && engine.readout.phase == .standing
        print(ok ? "\nthe timer sounds its marks" : "\nthe timer did NOT sound its marks")
        return ok
    }
}
