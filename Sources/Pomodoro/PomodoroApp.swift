import AppKit
import SwiftUI

/// An explicit entry point so `--self-check` can run and exit before any of
/// AppKit's machinery starts.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            exit(SelfCheck.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--timer-check") {
            exit(MainActor.assumeIsolated { TimerCheck.run() } ? 0 : 1)
        }
        if CommandLine.arguments.contains("--audio-check") {
            exit(TonePlayer().check() ? 0 : 1)
        }
        PomodoroApp.main()
    }
}

struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = TimerEngine()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(engine)
        } label: {
            MenuBarLabel(readout: engine.readout)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The label is the one part of the app that stays on screen while the panel is
/// closed, so it carries the whole readout: a glyph for the phase and the time
/// left in the round.
struct MenuBarLabel: View {
    let readout: Readout

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: readout.symbol)
            // Without tabular digits the label changes width every second and
            // shoves everything to its left around the menu bar.
            Text(readout.clock).monospacedDigit()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist carries LSUIElement for the bundled app; this covers the
        // case of running the bare executable straight out of `swift build`.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
