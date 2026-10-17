import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService`. Only works when running from a real .app bundle;
/// a bare `swift run` binary has no bundle identifier and reports `isSupported == false`.
enum LaunchAtLogin {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isSupported else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        Log.app.info("Launch at login \(enabled ? "enabled" : "disabled")")
    }
}
