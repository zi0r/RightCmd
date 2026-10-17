import AppKit
import ApplicationServices

/// Accessibility trust is required to create an active (event-modifying) event tap.
enum AccessibilityPermission {
    /// Returns whether this process is trusted. With `prompt: true`, macOS shows its
    /// standard "would like to control this computer" dialog if it isn't.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings at Privacy & Security › Accessibility.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
