import AppKit

// Entry point. A plain `main.swift` (rather than `@main`) keeps the launch sequence
// explicit and works identically whether run via `swift run` or from the .app bundle.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar utility: no Dock icon, no app menu. Info.plist also sets LSUIElement for the bundle.
app.setActivationPolicy(.accessory)
app.run()
