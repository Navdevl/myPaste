import AppKit
// Stand-in for a clashing clipboard manager (bundle id org.p0deje.Maccy) so the conflict UI can be
// tested without touching the real Maccy. Does nothing but stay alive until quit.
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
