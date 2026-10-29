// Renders myPaste's built-in sound pack to Resources/Sounds/*.wav (48 kHz, 24-bit, mono).
// Everything is synthesized here, so there are no third-party assets or licences involved.
// Usage: swift scripts/make-sounds.swift Resources/Sounds
import AVFoundation
import Foundation

let rate = 48_000.0
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Sounds")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: Building blocks

struct Noise {
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> Double {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Double(seed % 2_000_001) / 1_000_000 - 1
    }
}

/// State-variable filter (Chamberlin): low/band/high outputs, cutoff in Hz, resonance q (0.5 = gentle).
struct SVF {
    var low = 0.0, band = 0.0
    mutating func process(_ x: Double, cutoff: Double, q: Double) -> (low: Double, band: Double, high: Double) {
        let f = 2 * sin(.pi * min(cutoff, rate / 6) / rate)
        let damp = 1 / max(q, 0.5)
        low += f * band
        let high = x - low - damp * band
        band += f * high
        return (low, band, high)
    }
}

/// Sum of exponentially decaying sine partials: how struck wood, glass and metal actually ring.
func modal(_ t: Double, _ partials: [(freq: Double, amp: Double, decay: Double)]) -> Double {
    partials.reduce(0) { $0 + sin(2 * .pi * $1.freq * t) * $1.amp * exp(-t * $1.decay) }
}

/// Small Schroeder reverb (4 combs + 2 allpasses) for a sense of space without wash.
func reverb(_ dry: [Double], mix: Double, size: Double = 1) -> [Double] {
    let combs = [1557, 1617, 1491, 1422].map { Int(Double($0) * size * rate / 44_100) }
    let allpasses = [225, 556].map { Int(Double($0) * rate / 44_100) }
    var wet = [Double](repeating: 0, count: dry.count)
    for len in combs {
        var buf = [Double](repeating: 0, count: len), i = 0, lp = 0.0
        for n in 0..<dry.count {
            let y = buf[i]
            lp = y * 0.6 + lp * 0.4
            buf[i] = dry[n] + lp * 0.78
            wet[n] += y / Double(combs.count)
            i = (i + 1) % len
        }
    }
    for len in allpasses {
        var buf = [Double](repeating: 0, count: len), i = 0
        for n in 0..<wet.count {
            let b = buf[i]
            let y = -wet[n] + b
            buf[i] = wet[n] + b * 0.5
            wet[n] = y
            i = (i + 1) % len
        }
    }
    return zip(dry, wet).map { $0 * (1 - mix) + $1 * mix }
}

func render(_ seconds: Double, _ sample: (Double, Int, inout Noise) -> Double) -> [Double] {
    var noise = Noise()
    return (0..<Int(seconds * rate)).map { i in sample(Double(i) / rate, i, &noise) }
}

/// Loudness-match every sound to about -20 dBFS RMS (so switching options doesn't jump in volume),
/// never letting the peak exceed `peakDB`; then a 1.5 ms fade-in (no click) and a 10 ms fade-out.
func finish(_ x: [Double], peakDB: Double = -1.5) -> [Double] {
    let peak = x.map(abs).max() ?? 1
    let rms = sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(max(x.count, 1)))
    let gain = min(pow(10, -20 / 20) / max(rms, 1e-9), pow(10, peakDB / 20) / max(peak, 1e-9))
    let fadeIn = Int(0.0015 * rate), fadeOut = Int(0.010 * rate)
    return x.enumerated().map { i, v in
        var g = gain
        if i < fadeIn { g *= Double(i) / Double(fadeIn) }
        if i > x.count - fadeOut { g *= Double(x.count - i) / Double(fadeOut) }
        return v * g
    }
}

func write(_ name: String, _ samples: [Double]) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: outDir.appendingPathComponent("\(name).wav"), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (i, v) in samples.enumerated() { buffer.floatChannelData![0][i] = Float(v) }
    try file.write(from: buffer)
    print(String(format: "%-14@ %4.0f ms", name as NSString, Double(samples.count) / rate * 1000))
}

// MARK: Copy sounds (short, light, frequent: must never get tiring)

// Soft knock on a wooden desk: low inharmonic wood modes + a muffled contact click.
try write("wood-knock", finish(reverb(render(0.12) { t, _, n in
    var lp = 0.0
    let click = n.next() * exp(-t * 1400)
    lp = click * 0.5 + lp * 0.5
    return modal(t, [(612, 1, 95), (1530, 0.45, 140), (2470, 0.2, 210), (3890, 0.08, 320)]) + lp * 0.35
}, mix: 0.12, size: 0.6)))

// Glass tick: bright, short, airy partials like tapping a glass with a fingernail.
try write("glass-tick", finish(reverb(render(0.16) { t, _, n in
    modal(t, [(2637, 1, 60), (5274 * 1.013, 0.35, 90), (7350, 0.18, 140), (11_200, 0.06, 260)]) + n.next() * exp(-t * 2500) * 0.15
}, mix: 0.18)))

// Bubble: a sine whose pitch rises fast, like a drop of air surfacing.
try write("bubble", finish(reverb({
    var phase = 0.0
    return render(0.09) { t, _, _ in
        let f = 380 + 900 * (1 - exp(-t * 55))
        phase += 2 * .pi * f / rate
        return sin(phase) * sin(.pi * min(1, t / 0.09)) * exp(-t * 18)
    }
}(), mix: 0.1)))

// Paper snap: a crisp band-passed noise burst, like a page flick.
try write("paper-snap", finish({
    var f = SVF()
    return render(0.07) { t, _, n in
        let x = n.next() * (exp(-t * 90) + 0.6 * exp(-pow((t - 0.012) * 400, 2)))
        return f.process(x, cutoff: 3600 - 1500 * t / 0.07, q: 1.6).band
    }
}()))

// Marimba: a mallet on a wooden bar: fundamental + tuned 4th harmonic, soft attack.
try write("marimba", finish(reverb(render(0.25) { t, _, n in
    let mallet = n.next() * exp(-t * 3000) * 0.2
    return modal(t, [(1046.5, 1, 22), (4186, 0.25, 55), (2793, 0.08, 40)]) * (1 - exp(-t * 900)) + mallet
}, mix: 0.15)))

// Mechanical key: a deep "thock" body + bright switch click, like a good keyboard.
try write("soft-key", finish(reverb({
    var f = SVF()
    return render(0.09) { t, _, n in
        let thock = sin(2 * .pi * (190 - 60 * min(1, t / 0.02)) * t) * exp(-t * 70)
        let click = f.process(n.next() * exp(-t * 900), cutoff: 4200, q: 1.2).band
        return thock * 0.9 + click * 0.6
    }
}(), mix: 0.08, size: 0.5)))

// Classic tick (the 1.3.0 sound, kept as an option).
try write("classic-tick", finish(render(0.03) { t, _, n in
    sin(2 * .pi * 3200 * t) * exp(-t * 180) * 0.55 + n.next() * exp(-t * 900) * 0.25
}))

// MARK: Paste sounds (confirming, a touch rounder)

try write("soft-pop", finish({
    var phase = 0.0
    return render(0.09) { t, _, _ in
        phase += 2 * .pi * (820 - 440 * min(1, t / 0.056)) / rate
        return sin(phase) * min(1, t / 0.004) * exp(-t * 38)
    }
}()))

// Water drop: pitch falls then "plinks" up, the classic droplet shape.
try write("water-drop", finish(reverb({
    var phase = 0.0
    return render(0.14) { t, _, _ in
        let f = t < 0.03 ? 1400 - 900 * t / 0.03 : 500 + 1300 * (t - 0.03) / 0.11
        phase += 2 * .pi * f / rate
        return sin(phase) * exp(-t * 26) * min(1, t / 0.002)
    }
}(), mix: 0.2)))

// Two-note chime (perfect fifth), short and bright.
try write("chime", finish(reverb(render(0.45) { t, _, _ in
    let a = modal(t, [(1318.5, 1, 9), (2637, 0.2, 16)])
    let b = t > 0.06 ? modal(t - 0.06, [(1975.5, 0.9, 10), (3951, 0.15, 18)]) : 0
    return (a + b) * min(1, t / 0.003)
}, mix: 0.22)))

try write("thock", finish(reverb(render(0.11) { t, _, n in
    sin(2 * .pi * (150 - 40 * min(1, t / 0.03)) * t) * exp(-t * 45) + n.next() * exp(-t * 1200) * 0.3
}, mix: 0.1, size: 0.5)))

// MARK: Delete sounds (low, soft, clearly "gone")

try write("whoosh", finish({
    var f = SVF(), phase = 0.0
    return render(0.24) { t, _, n in
        let p = t / 0.24
        let air = f.process(n.next(), cutoff: 2600 - 2000 * p, q: 0.9).low
        phase += 2 * .pi * (420 - 260 * p) / rate
        return (air * 1.4 + sin(phase) * 0.12) * sin(.pi * min(1, p * 1.15)) * (1 - p * 0.4)
    }
}()))

// Crumple: a few grains of filtered noise, like scrunching paper.
try write("crumple", finish({
    var f = SVF()
    let grains: [(at: Double, len: Double, amp: Double)] = [(0, 0.03, 1), (0.035, 0.025, 0.8), (0.07, 0.04, 0.9), (0.12, 0.03, 0.55), (0.16, 0.05, 0.4)]
    return render(0.22) { t, _, n in
        let env = grains.reduce(0.0) { acc, g in
            let x = t - g.at
            return acc + (x >= 0 && x < g.len ? g.amp * sin(.pi * x / g.len) : 0)
        }
        return f.process(n.next() * env, cutoff: 2400, q: 0.8).band
    }
}()))

// Swipe: a highpass noise sweep, quick and modern.
try write("swipe", finish({
    var f = SVF()
    return render(0.16) { t, _, n in
        let p = t / 0.16
        return f.process(n.next(), cutoff: 600 + 5400 * p, q: 1.1).band * sin(.pi * p)
    }
}()))

try write("soft-thud", finish(reverb(render(0.16) { t, _, n in
    sin(2 * .pi * (95 - 30 * min(1, t / 0.05)) * t) * exp(-t * 30) * min(1, t / 0.003) + n.next() * exp(-t * 600) * 0.12
}, mix: 0.12, size: 0.7)))
