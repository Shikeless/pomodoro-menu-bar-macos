import AVFoundation
import Foundation

/// `Pomodoro --self-check` walks the ported timing math and exits non-zero on a
/// mismatch. It lives here rather than in a test target because XCTest and
/// swift-testing ship with Xcode, and this package builds against the Command
/// Line Tools alone.
enum SelfCheck {
    private static var failures: [String] = []

    // #fileID, not #file: the latter is an absolute path, and it would be baked
    // into the shipped binary.
    private static func expect(
        _ passed: Bool, _ what: String, file: StaticString = #fileID, line: UInt = #line
    ) {
        if passed {
            print("  ok   \(what)")
        } else {
            print("  FAIL \(what)  (\(file):\(line))")
            failures.append(what)
        }
    }

    static func run() -> Bool {
        let config = Config()   // 25 / 5 / 15, 4 rounds

        print("session shape")
        let session = Session(config: config)
        expect(session.cycle == 45 * 60, "one round is 45 minutes")
        expect(session.total == 4 * 45 * 60, "four rounds is 3 hours")

        print("marks")
        expect(session.marks.count == 4 * 3 * 4, "three warnings and an accent per phase")
        expect(zip(session.marks, session.marks.dropFirst()).allSatisfy { $0.at <= $1.at },
               "marks are ascending")
        expect(session.marks.prefix(4).map(\.at) == [1495, 1496, 1497, 1500],
               "first phase warns at 5/4/3s then sounds at 25:00")
        expect(session.marks.prefix(4).map(\.kind) == [.warn, .warn, .warn, .accent],
               "leads precede their accent")
        expect(session.marks.last?.at == session.total && session.marks.last?.kind == .accent,
               "the last mark closes the run")

        print("clock")
        expect(Readout.format(0) == "00:00", "zero")
        expect(Readout.format(59.4) == "01:00", "rounds up, as the web version does")
        expect(Readout.format(1500) == "25:00", "mm:ss")
        expect(Readout.format(3600) == "1:00:00", "hours appear only when needed")
        expect(Readout.format(-5) == "00:00", "never negative")

        print("phase follows the fill edge")
        var running = Session(config: config)
        let start = Date()
        running.startedAt = start
        func at(_ minutes: Double) -> Readout {
            Readout.make(config: config, session: running,
                         now: start.addingTimeInterval(minutes * 60))
        }
        expect(at(0).phase == .sitting, "0:00 sitting")
        expect(at(24).phase == .sitting, "24:00 sitting")
        expect(at(25).phase == .standing, "25:00 hands over to standing")
        expect(at(29).phase == .standing, "29:00 standing")
        expect(at(30).phase == .rest, "30:00 hands over to break")
        expect(at(44).phase == .rest, "44:00 break")
        expect(at(45).phase == .sitting && at(45).round == 2, "45:00 opens round 2")
        expect(at(180).round == 4, "the last round is not overcounted")

        print("clock and bar share the round span")
        expect(at(25).remaining == 20 * 60, "20 minutes left of the round at 25:00")
        expect(abs(at(25).progress - 25.0 / 45.0) < 1e-9, "the fill edge sits at 25/45")

        print("completion")
        let over = start.addingTimeInterval(running.total + 600)
        expect(running.elapsed(now: over) == running.total, "elapsed clamps to the total")
        let done = Readout.make(config: config, session: running, now: over)
        expect(done.isComplete && done.phaseTitle == "Done", "the display says Done")
        expect(done.round == 4 && done.remaining == 0, "it parks on the last round at zero")
        expect(done.fieldsEnabled, "the fields unlock again once finished")

        print("idle and paused")
        let idle = Readout.make(config: config, session: nil)
        expect(idle.isIdle && idle.clock == "45:00", "idle shows the whole round")
        expect(idle.fieldsEnabled && !idle.isPaused, "idle offers Start, not Resume")
        var parked = Session(config: config)
        parked.rested = 100
        let paused = Readout.make(config: config, session: parked)
        expect(paused.isPaused && !paused.isRunning, "a banked run offers Resume")
        expect(!paused.fieldsEnabled, "the fields stay locked mid-run")

        print("config limits")
        let clamped = Config(sitting: 999, standing: 0, rest: -4, rounds: 42).clamped
        expect(clamped == Config(sitting: 60, standing: 1, rest: 1, rounds: 10),
               "out-of-range values clamp instead of breaking the layout")

        print("restore")
        var restored = Session(config: config)
        restored.rested = 26 * 60
        restored.nextMark = restored.marks.firstIndex { $0.at > restored.rested } ?? restored.marks.count
        expect(restored.nextMark == 4, "marks already passed are spent, not pending")
        expect(restored.marks[restored.nextMark].at == 30 * 60 - 5, "the next mark is the one ahead")
        expect(!restored.isRunning, "a restored run is always paused")

        print("tone synthesis")
        if let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
           let warn = TonePlayer.render(.warn, format: format),
           let samples = warn.floatChannelData {
            let frames = Int(warn.frameLength)
            expect(frames == Int(48_000 * ToneKind.warn.seconds), "the buffer is as long as the tone")
            let peak = (0..<frames).map { abs(samples[0][$0]) }.max() ?? 0
            expect(peak <= Float(ToneKind.warn.peak) + 1e-4, "the envelope never exceeds its peak")
            expect(peak > Float(ToneKind.warn.peak) * 0.8, "the envelope actually reaches it")
            expect(abs(samples[0][0]) < 1e-3, "it opens from silence, so it cannot click")
            expect(abs(samples[0][frames - 1]) < 1e-3, "and decays back to silence")
            expect(samples[0][frames / 2] == samples[1][frames / 2], "both channels carry it")
        } else {
            expect(false, "could not render a tone buffer")
        }

        print("persistence")
        let suite = "pomodoro.selfcheck.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suite) {
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = Store(defaults: defaults)
            expect(store.load() == nil, "an empty store loads nothing")
            let saved = Config(sitting: 30, standing: 7, rest: 12, rounds: 2)
            store.save(Saved(config: saved, elapsed: 123.5))
            expect(store.load()?.config == saved, "the config round-trips")
            expect(store.load()?.elapsed == 123.5, "the elapsed offset round-trips")
            let raw = defaults.data(forKey: Store.key).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            let stored = raw["config"] as? [String: Any] ?? [:]
            expect(stored["break"] as? Int == 12, "break is stored under its web-version key")
        } else {
            expect(false, "could not open a scratch defaults suite")
        }

        print("")
        if failures.isEmpty {
            print("all checks passed")
            return true
        }
        print("\(failures.count) failed:")
        failures.forEach { print("  - \($0)") }
        return false
    }
}
