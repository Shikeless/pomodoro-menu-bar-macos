import AppKit
import Combine
import Foundation
import SwiftUI

/// Owns the run and everything derived from it.
///
/// This deliberately lives on the App rather than in a view: with
/// `menuBarExtraStyle(.window)` the panel's views do not exist while the panel
/// is closed, so a timer driven from a view would stop the moment the user
/// clicks away.
@MainActor
final class TimerEngine: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var readout: Readout

    private var session: Session?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var lastSave = Date.distantPast

    let tone = TonePlayer()
    private let store: Store

    /// A mark older than this is retired without sounding. The tones are a
    /// countdown, and a countdown fired late is worse than one not fired.
    private static let staleAfter: TimeInterval = 2
    /// Fine enough that a mark lands within a tenth of a second of its offset,
    /// coarse enough to be free. Only alive while a run is.
    private static let tickInterval: TimeInterval = 0.1
    private static let saveEvery: TimeInterval = 1

    init(store: Store = Store()) {
        self.store = store
        self.config = .init()
        self.readout = .init()
        restore()
        render()
        observeLifecycle()
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        tone.prepare()
        if session == nil || session!.isComplete() { session = Session(config: config) }
        session!.startedAt = Date()
        persist()
        beginActivity()
        startTimer()
        tick()
    }

    func pause() {
        guard isRunning, var current = session else { return }
        current.rested = current.elapsed()
        current.startedAt = nil
        session = current
        stopTimer()
        endActivity()
        persist()
        render()
    }

    func reset() {
        stopTimer()
        endActivity()
        session = nil
        persist()
        render()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Fields are locked while a run is in flight, so this only ever arrives
    /// from an idle or finished state.
    func update(_ change: (inout Config) -> Void) {
        var next = config
        change(&next)
        next = next.clamped
        guard next != config else { return }
        config = next
        persist()
        render()
    }

    func binding(for keyPath: WritableKeyPath<Config, Int>) -> Binding<Int> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }

    var isRunning: Bool { session?.isRunning ?? false }

    // MARK: - Clock

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common, not the default mode: while a menu or the panel is tracking
        // events the run loop leaves the default mode and a scheduled timer
        // would simply stop firing.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard session != nil else { return }
        render()
        sound()
        if Date().timeIntervalSince(lastSave) >= Self.saveEvery { persist() }
        if session!.isComplete() { finish() }
    }

    /// Consume every mark the clock has passed. A run that was asleep can pass
    /// a great many at once; those are retired silently.
    private func sound() {
        guard var current = session else { return }
        let now = current.elapsed()
        while current.nextMark < current.marks.count, current.marks[current.nextMark].at <= now {
            let mark = current.marks[current.nextMark]
            current.nextMark += 1
            if now - mark.at <= Self.staleAfter { tone.play(mark.kind) }
        }
        session = current
    }

    private func finish() {
        guard var current = session else { return }
        current.rested = current.total
        current.startedAt = nil
        session = current
        stopTimer()
        endActivity()
        persist()
        render()
    }

    private func render() {
        readout = Readout.make(config: config, session: session)
    }

    // MARK: - Sleep and App Nap

    private func observeLifecycle() {
        // Quit is the one exit that is not preceded by a pause, and the last
        // periodic save can be a second stale.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        }

        // No timer fires while the machine is asleep, so a run left going would
        // come back having silently swallowed every phase change that
        // "happened" in the dark. Park it on the way down instead — the same
        // rule the restore path follows. The notification arrives before the
        // machine actually sleeps, so the banked time is accurate.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }

        // Belt and braces: a sleep that never delivered willSleep (a forced one,
        // a dead battery) leaves the run going. Ticking on wake snaps the bar to
        // where the wall clock says it is, and `sound` retires the marks that
        // passed unheard rather than replaying them in a burst.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Keeps App Nap off a running timer without also keeping the Mac awake —
    /// `.userInitiated` would disable idle system sleep, which a pomodoro has
    /// no business doing.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Pomodoro timer is running"
        )
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    // MARK: - Persistence

    func persist() {
        lastSave = Date()
        store.save(Saved(config: config, elapsed: session?.elapsed()))
    }

    /// A run is always restored paused. While the app was gone nothing could
    /// sound a cue or repaint, so resuming as if it had been running would
    /// silently swallow every phase change that "happened" in the interim.
    private func restore() {
        guard let saved = store.load() else { return }
        config = saved.config.clamped

        guard let at = saved.elapsed, at > 0 else { return }
        var restored = Session(config: config)
        restored.rested = min(at, restored.total)

        // Marks the restored clock has already passed are spent, not pending.
        let pending = restored.marks.firstIndex { $0.at > restored.rested }
        restored.nextMark = pending ?? restored.marks.count
        session = restored
    }
}
