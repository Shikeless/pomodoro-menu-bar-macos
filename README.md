# Pomodoro — menu bar app

A native SwiftUI port of the single-file web version in `../pomodoro`. Same
timer: three phases per round (sitting → standing → break), a configurable
number of rounds, three warning tones at 5/4/3 seconds before each phase ends
and a longer one at the change itself.

The countdown lives in the menu bar, so the panel only has to be open to change
something.

## Build and run

```sh
./build.sh          # produces Pomodoro.app next to this file
open Pomodoro.app
```

`build.sh` compiles with SwiftPM and wraps the executable in an app bundle —
the bundle is what carries `LSUIElement`, which keeps the app out of the Dock
and the app switcher. The signature is ad-hoc, which is enough to run here;
handing the app to someone else needs a Developer ID certificate and
notarization.

To have it start with the Mac: System Settings → General → Login Items → add
`Pomodoro.app`.

Requires macOS 13 or newer (`MenuBarExtra`). Command Line Tools are enough —
Xcode is not needed. `open Package.swift` if you do have Xcode and want to work
in it.

## Checks

```sh
swift build && ./.build/debug/Pomodoro --self-check
```

Walks the timing math: mark offsets and ordering, the phase the fill edge sits
in at each boundary, round counting, clock formatting, clamping, the restore
rules, the tone envelope and the stored shape. XCTest and swift-testing ship
with Xcode, so with Command Line Tools alone this is the test suite.

## Layout

| File | What is in it |
| --- | --- |
| `Model/Config.swift` | the four numbers, their limits and clamping |
| `Model/Phase.swift` | the three phases, their colours and SF Symbol glyphs |
| `Model/Session.swift` | one run: precomputed marks, elapsed math, and `Readout`, which resolves everything the UI draws |
| `Model/TimerEngine.swift` | the tick loop, controls, persistence, sleep and App Nap |
| `Model/Store.swift` | the `UserDefaults` record |
| `Audio/TonePlayer.swift` | the synthesized tones |
| `Views/PanelView.swift` | the panel behind the menu bar item |
| `Views/ProgressBarView.swift` | the segmented bar |
| `PomodoroApp.swift` | entry point, `MenuBarExtra`, the menu bar label |

## Notes on the port

Decisions carried over from the web version, and the macOS-specific ones:

- **The clock counts down the round, not the phase.** `25:00 / 5:00 / 15:00`
  with 4 rounds starts at `45:00`, exactly as the web version does — the clock
  and the bar deliberately share one span, so the fill edge and the number
  always agree. Counting down the current phase instead is a two-line change in
  `Readout.make`.
- **The engine is owned by the `App`, not by a view.** With
  `menuBarExtraStyle(.window)` the panel's views do not exist while the panel is
  closed, so a timer driven from a view would stop the moment you click away.
- **The tick timer runs in `.common` run loop mode.** While a menu or the panel
  is tracking events the run loop leaves the default mode, and a plain
  `Timer.scheduledTimer` would simply stop firing.
- **Elapsed time is re-derived from the wall clock**, never accumulated, so a
  stretch where nothing fired resumes at the right position instead of drifting.
- **Sleep pauses the run.** No timer fires while the Mac is asleep, so a run
  left going would come back having swallowed every phase change that
  "happened" in the dark. `NSWorkspace.willSleepNotification` parks it on the
  way down; resume it yourself on wake, as after any pause.
- **Marks older than two seconds are retired silently.** This covers the sleep
  that never announced itself — a forced one, a dead battery. On wake
  `NSWorkspace.didWakeNotification` snaps the bar to the wall clock and the
  passed marks are dropped rather than replayed in a burst.
- **App Nap is held off with `.userInitiatedAllowingIdleSystemSleep`**, not
  `.userInitiated` — the latter also disables idle system sleep, which a
  pomodoro has no business doing.
- **A run is always restored paused.** While the app was gone nothing could
  sound a cue, so resuming as if it had been running would swallow every phase
  change that "happened" in the interim.
- **Only the config and one elapsed offset are stored.** Phase, round, marks and
  progress are all derived from those two, so there is no second copy of the
  truth to fall out of sync.

## Not carried over

- The full-screen bar. The panel has the same segmented bar at panel size.
- Notifications on a phase change, and a global hotkey. Both are small
  additions; notifications want a real signing identity to behave.

## License

MIT — see [LICENSE](LICENSE).

The app references SF Symbols by name (`figure.stand` and friends); no Apple
artwork is redistributed here. Apple's own terms govern the glyphs themselves,
and they permit this use in an app for Apple platforms.
