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

    /// Called on the first Start, mirroring the web version's rule that audio
    /// only opens on a user gesture.
    func prepare() {
        guard !ready else {
            if !engine.isRunning { try? engine.start() }
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
