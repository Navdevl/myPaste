import AppKit
import KeyboardShortcuts
import SwiftUI

/// First-run walkthrough; also reachable from Settings → About.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var step = 0
    @State private var trusted = Paster.isTrusted
    @State private var conflicts = ShortcutConflicts.current()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcome
                case 1: accessibility
                case 2: shortcuts
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)

            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i == step ? Color.accentColor : Color.primary.opacity(0.18))
                            .frame(width: i == step ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 && step < steps - 1 { Button("Back") { go(step - 1) } }
                Button(step == steps - 1 ? "Start Using myPaste" : "Continue") {
                    step == steps - 1 ? onFinish() : go(step + 1)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 460)
        .background(
            LinearGradient(colors: [Color.indigo.opacity(0.18), Color.purple.opacity(0.06), Color(nsColor: .windowBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
        )
        .onReceive(timer) { _ in
            trusted = Paster.isTrusted
            if step == 2 { conflicts = ShortcutConflicts.current() }
        }
    }

    private func go(_ s: Int) { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = s } }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).shadow(radius: 8, y: 4)
            Text("Welcome to myPaste").font(.system(size: 28, weight: .bold))
            Text("Everything you copy, one keystroke away. Local only: nothing leaves this Mac.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 22) {
                feature("rectangle.stack.fill", .indigo, "History", "Text, links, images, files")
                feature("pin.fill", .pink, "Pinboards", "Keep what matters")
                feature("lock.shield.fill", .orange, "Private", "Secrets & IDs masked")
                feature("wand.and.stars", .green, "Actions", "⌘K transforms")
            }
            .padding(.top, 6)
        }
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Tile(symbol: symbol, tint: tint, size: 40)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 112)
    }

    private var accessibility: some View {
        VStack(spacing: 16) {
            Tile(symbol: trusted ? "checkmark.seal.fill" : "hand.raised.fill", tint: trusted ? .green : .blue, size: 64)
            Text("Allow pasting into apps").font(.system(size: 24, weight: .bold))
            Text("myPaste types ⌘V for you after you pick an item, and Paste Stack listens for ⌘V. macOS calls this Accessibility access. myPaste never reads your screen or keystrokes otherwise.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            } else {
                Button { Paster.requestTrust(); Paster.openAccessibilitySettings() } label: {
                    Label("Open Accessibility Settings", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
                Text("Turn on myPaste in the list, then come back. This page updates by itself.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 16) {
            Tile(symbol: "command", tint: .indigo, size: 64)
            Text("Your shortcuts").font(.system(size: 24, weight: .bold))
            VStack(spacing: 10) {
                HStack { Text("Open myPaste").frame(width: 140, alignment: .leading); ShortcutRecorder(name: .openPanel) }
                if Preferences.shared.pasteStackEnabled {
                    HStack { Text("Paste Stack").frame(width: 140, alignment: .leading); ShortcutRecorder(name: .pasteStack) }
                }
            }
            ForEach(conflicts) { c in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(c.name) is running and may grab \"\(ShortcutConflicts.label(c.shortcut))\".").font(.callout)
                    Button("Quit \(c.name)") { c.app.terminate() }
                }
            }
            if conflicts.isEmpty {
                Label("No conflicts with other clipboard apps", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Tile(symbol: "sparkles", tint: .purple, size: 64)
            Text("You're set").font(.system(size: 24, weight: .bold))
            Text("Copy anything, then press \(KeyboardShortcuts.getShortcut(for: .openPanel)?.description ?? "⇧⌘V").")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                tip("hold ⌘", "shows every shortcut and lets you delete cards")
                tip("hold ⇧", "pastes without formatting")
                tip("⌘K", "formats JSON, cleans URLs, converts timestamps…")
                tip("/img @slack #tag", "filter while you search")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        }
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(keys).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
                .frame(width: 130, alignment: .leading)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
