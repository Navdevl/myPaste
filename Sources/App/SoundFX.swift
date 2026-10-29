import AVFoundation

/// Subtle, synthesized UI sounds: no audio assets, generated once into PCM buffers.
/// The engine starts on demand and stops after a few idle seconds so it costs nothing in the background.
final class SoundFX {
    static let shared = SoundFX()

    enum Effect: String, CaseIterable {
        case copy, paste, delete

        var label: String {
            switch self {
            case .copy: return "Copy captured"
            case .paste: return "Paste"
            case .delete: return "Delete"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var idleTimer: Timer?
    private let prefs = Preferences.shared

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for e in Effect.allCases { buffers[e] = render(e) }
    }

    /// Plays if sounds and this effect are enabled. `force` is for the Settings "Play" buttons.
    func play(_ effect: Effect, force: Bool = false) {
        guard force || (prefs.soundsEnabled && isEnabled(effect)), let buffer = buffers[effect] else { return }
        DispatchQueue.main.async { [self] in
            do {
                if !engine.isRunning { try engine.start() }
            } catch {
                AppLog.error("Audio engine failed to start", error)
                return
            }
            engine.mainMixerNode.outputVolume = Float(prefs.soundVolume)
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            if !player.isPlaying { player.play() }
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.player.stop()
                self?.engine.stop()
            }
        }
    }

    private func isEnabled(_ e: Effect) -> Bool {
        switch e {
        case .copy: return prefs.soundCopy
        case .paste: return prefs.soundPaste
        case .delete: return prefs.soundDelete
        }
    }

    // MARK: Synthesis

    private func render(_ e: Effect) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let duration: Double
        switch e {
        case .copy: duration = 0.03
        case .paste: duration = 0.09
        case .delete: duration = 0.22
        }
        let frames = AVAudioFrameCount(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        var phase = 0.0
        var noiseLP = 0.0
        var seed: UInt32 = 0x9E37_79B9
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Double(seed) / Double(UInt32.max) * 2 - 1
        }
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let p = t / duration
            var s = 0.0
            switch e {
            case .copy:
                // Crisp tick: a 3.2 kHz ping with a very fast decay plus a tiny noise transient.
                phase += 2 * .pi * 3200 / rate
                s = sin(phase) * exp(-t * 180) * 0.55 + noise() * exp(-t * 900) * 0.25
            case .paste:
                // Soft pop: sine sweeping 820 → 380 Hz, gentle attack, rounded decay.
                let f = 820 - 440 * min(1, p * 1.6)
                phase += 2 * .pi * f / rate
                let attack = min(1, t / 0.004)
                s = sin(phase) * attack * exp(-t * 38) * 0.6
            case .delete:
                // Airy whoosh: low-passed noise under a rise-and-fall envelope, with a faint falling tone.
                noiseLP += (noise() - noiseLP) * (0.08 + 0.12 * (1 - p))
                let env = sin(.pi * min(1, p * 1.15)) * (1 - p * 0.4)
                phase += 2 * .pi * (420 - 260 * p) / rate
                s = (noiseLP * 1.6 + sin(phase) * 0.12) * env * 0.5
            }
            // Short fade at the end so nothing clicks when the buffer stops.
            let tail = min(1, (1 - p) / 0.08)
            out[i] = Float(max(-1, min(1, s * tail)))
        }
        return buffer
    }
}
