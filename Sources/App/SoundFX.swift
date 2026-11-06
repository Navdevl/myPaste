import AppKit
import AVFoundation

/// UI sounds: the bundled pack (Resources/Sounds, rendered by scripts/make-sounds.swift) or a file the
/// user picks. Players are cached per event; AVAudioPlayer handles any format macOS can decode.
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

        var defaultSound: String {
            switch self {
            case .copy: return "paper-snap"
            case .paste: return "soft-thud"
            case .delete: return "whoosh"
            }
        }
    }

    struct BuiltIn: Identifiable, Hashable {
        let id: String
        let name: String
        /// Which event it was designed for; listed first in that event's menu.
        let suits: Effect
    }

    static let builtIns: [BuiltIn] = [
        BuiltIn(id: "paper-snap", name: "Paper Snap", suits: .copy),
        BuiltIn(id: "wood-knock", name: "Wood Knock", suits: .copy),
        BuiltIn(id: "glass-tick", name: "Glass Tick", suits: .copy),
        BuiltIn(id: "soft-thud", name: "Soft Thud", suits: .paste),
        BuiltIn(id: "soft-pop", name: "Soft Pop", suits: .paste),
        BuiltIn(id: "whoosh", name: "Whoosh", suits: .delete),
    ]

    /// Selection value meaning "the user's own file for this event".
    static let customID = "custom"

    private let prefs = Preferences.shared
    private var players: [URL: AVAudioPlayer] = [:]

    static var customDirectory: URL { AppDelegate.dataDirectory.appendingPathComponent("sounds", isDirectory: true) }

    /// Plays the chosen sound if sounds and this event are on. `force` is for the Settings Play buttons.
    func play(_ effect: Effect, force: Bool = false) {
        guard force || (prefs.soundsEnabled && isEnabled(effect)) else { return }
        play(url: url(for: effect))
    }

    func preview(_ soundID: String) {
        play(url: Bundle.main.url(forResource: soundID, withExtension: "wav", subdirectory: "Sounds"))
    }

    private func play(url: URL?) {
        guard let url else { return }
        DispatchQueue.main.async { [self] in
            let player: AVAudioPlayer
            if let cached = players[url] {
                player = cached
            } else {
                do {
                    player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    players[url] = player
                } catch {
                    AppLog.error("Can't play sound \(url.lastPathComponent)", error)
                    return
                }
            }
            player.volume = Float(prefs.soundVolume)
            player.currentTime = 0
            player.play()
        }
    }

    func url(for effect: Effect) -> URL? {
        let choice = selection(for: effect)
        if choice == Self.customID, let file = customFile(for: effect) { return file }
        let id = Self.builtIns.contains { $0.id == choice } ? choice : effect.defaultSound
        return Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "Sounds")
    }

    /// The stored choice, or the default if it names a sound that's no longer bundled (the pack was cut
    /// from 15 to 6 in 1.7.0) or a custom file that's gone.
    func selection(for effect: Effect) -> String {
        let stored: String
        switch effect {
        case .copy: stored = prefs.soundCopyChoice
        case .paste: stored = prefs.soundPasteChoice
        case .delete: stored = prefs.soundDeleteChoice
        }
        if stored == Self.customID { return customFile(for: effect) == nil ? effect.defaultSound : stored }
        return Self.builtIns.contains { $0.id == stored } ? stored : effect.defaultSound
    }

    func setSelection(_ id: String, for effect: Effect) {
        switch effect {
        case .copy: prefs.soundCopyChoice = id
        case .paste: prefs.soundPasteChoice = id
        case .delete: prefs.soundDeleteChoice = id
        }
    }

    func customFile(for effect: Effect) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.customDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "custom-\(effect.rawValue)" }
    }

    /// Copies the user's file into myPaste's data folder (so moving or deleting the original doesn't break
    /// it), checks it decodes, and selects it.
    func installCustom(_ source: URL, for effect: Effect) throws {
        _ = try AVAudioPlayer(contentsOf: source) // throws if macOS can't decode it
        let fm = FileManager.default
        try fm.createDirectory(at: Self.customDirectory, withIntermediateDirectories: true)
        if let old = customFile(for: effect) {
            players[old] = nil
            try? fm.removeItem(at: old)
        }
        let dest = Self.customDirectory.appendingPathComponent("custom-\(effect.rawValue).\(source.pathExtension.lowercased())")
        try fm.copyItem(at: source, to: dest)
        setCustomName(source.lastPathComponent, for: effect)
        setSelection(Self.customID, for: effect)
    }

    func customName(for effect: Effect) -> String? { AppDefaults.store.string(forKey: "soundCustomName.\(effect.rawValue)") }
    private func setCustomName(_ name: String, for effect: Effect) { AppDefaults.store.set(name, forKey: "soundCustomName.\(effect.rawValue)") }

    private func isEnabled(_ e: Effect) -> Bool {
        switch e {
        case .copy: return prefs.soundCopy
        case .paste: return prefs.soundPaste
        case .delete: return prefs.soundDelete
        }
    }
}
