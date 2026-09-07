// swift-tools-version: 5.9
import PackageDescription

// The product is a menu bar app, so it has to run from a bundle with
// LSUIElement set. `swift build` produces only the executable; ./build.sh
// wraps that executable in Pomodoro.app. See README.md.
let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v13)],   // MenuBarExtra is macOS 13+
    targets: [
        .executableTarget(name: "Pomodoro", path: "Sources/Pomodoro")
    ]
)
