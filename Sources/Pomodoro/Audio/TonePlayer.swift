import AVFoundation

enum ToneKind {
    case warn
    case accent

    var hz: Double {
        switch self {
        case .warn:   return 880
        case .accent: return 1320
        }
    }

    var seconds: Double {
        switch self {
        case .warn:   return 0.12
        case .accent: return 0.45
        }
    }

    var peak: Double {
        switch self {
        case .warn:   return 0.22
        case .accent: return 0.35
        }
    }
}

/// Tones are synthesized rather than shipped as files, so the bundle stays
/// self-contained. Every failure path here is swallowed: a missing chime must
/// never break the timer.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var warn: AVAudioPCMBuffer?
    private var accent: AVAudioPCMBuffer?
    private var ready = false

    init() {
        // Changing the output device — headphones in, Bluetooth connecting, a
        // monitor waking — stops the engine and tears the graph down. Nothing
        // reports this; play() would just quietly do nothing from then on,
        // which is exactly how an app that beeped this morning is silent by
        // the afternoon. Rebuild from scratch, since the new device can also
        // want a different sample rate than the buffers were rendered at.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    private func rebuild() {
        guard ready else { return }
        ready = false
        engine.stop()
        if node.engine != nil { engine.detach(node) }
        warn = nil
        accent = nil
        prepare()
    }

    /// Called on the first Start, mirroring the web version's rule that audio
    /// only opens on a user gesture.
    func prepare() {
        guard !ready else {
            if !engine.isRunning { try? engine.start() }
            if !node.isPlaying { node.play() }
            return
        }

        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let mix = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)
        else { return }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mix)

        warn = TonePlayer.render(.warn, format: mix)
        accent = TonePlayer.render(.accent, format: mix)

        do {
            try engine.start()
            node.play()
            ready = true
        } catch {
            ready = false
        }
    }

    func play(_ kind: ToneKind) {
        // Self-healing: a stopped engine is worth one attempt to revive rather
        // than a silent return, because the alternative is a timer that never
        // sounds again until the app is restarted.
        if !ready || !engine.isRunning { prepare() }
        guard ready, engine.isRunning else { return }
        guard let buffer = (kind == .warn ? warn : accent) else { return }
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    /// A sine under the same envelope WebAudio's exponentialRampToValueAtTime
    /// produces: a 15 ms rise to the peak, then an exponential decay to silence.
    /// Ramping rather than switching matters — an instant gain change clicks.
    static func render(_ kind: ToneKind, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * kind.seconds)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = frames

        let floor = 0.0001
        let attack = 0.015
        let peak = kind.peak
        let decay = max(0.001, kind.seconds - attack)

        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            let envelope = t < attack
                ? floor * pow(peak / floor, t / attack)
                : peak * pow(floor / peak, (t - attack) / decay)
            let sample = Float(sin(2 * .pi * kind.hz * t) * envelope)
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = sample
            }
        }
        return buffer
    }
}

extension TonePlayer {
    /// Diagnostics: hands every buffer reaching the mixer to `onBuffer`.
    func probe(_ onBuffer: @escaping (Float) -> Void) {
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            var peak: Float = 0
            for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[0][frame])) }
            onBuffer(peak)
        }
    }

    func removeProbe() { engine.mainMixerNode.removeTap(onBus: 0) }

    /// Diagnostics for `Pomodoro --audio-check`. Plays each tone through the
    /// real graph while a tap measures what actually reaches the mixer, so a
    /// silent app can be told apart from a silent speaker.
    func check() -> Bool {
        print("output format before prepare: \(engine.outputNode.outputFormat(forBus: 0))")
        prepare()
        print("ready:        \(ready)")
        print("engine running: \(engine.isRunning)")
        print("node attached:  \(node.engine != nil)")
        print("node playing:   \(node.isPlaying)")
        print("warn buffer:    \(warn.map { "\($0.frameLength) frames" } ?? "nil")")
        print("accent buffer:  \(accent.map { "\($0.frameLength) frames" } ?? "nil")")

        guard ready else {
            print("\nprepare() failed — nothing was ever going to sound")
            return false
        }

        var peak: Float = 0
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(data[0][frame]))
            }
        }

        print("\nplaying: warn, warn, warn, accent")
        for kind in [ToneKind.warn, .warn, .warn, .accent] {
            play(kind)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        mixer.removeTap(onBus: 0)

        print("peak reaching the mixer: \(peak)")
        if peak > 0.01 {
            print("\nthe graph is producing sound; if you heard nothing the")
            print("problem is downstream — output device, volume, or Focus")
            return true
        }
        print("\nsilence inside the engine — the app is at fault")
        return false
    }
}
