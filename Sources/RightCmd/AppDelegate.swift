import AppKit
import RightCmdCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private var coordinator: SwitchCoordinator!
    private var statusMenu: StatusMenuController!
    private var settingsWindow: SettingsWindowController!

    /// User-level on/off from the menu. Persisted separately from `Settings` because it is
    /// a runtime state, not a preference that should survive by accident.
    private var isEnabled = true
    private var permissionTimer: Timer?
    private var startupError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("RightCmd launching (pid \(ProcessInfo.processInfo.processIdentifier))")

        if getuid() == 0 {
            // An event tap running as root would capture every user's keystrokes.
            let alert = NSAlert()
            alert.messageText = "RightCmd must not run as root."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        coordinator = SwitchCoordinator(settingsStore: settingsStore, overlay: OverlayPanel())
        settingsWindow = SettingsWindowController(settingsStore: settingsStore)
        statusMenu = StatusMenuController(settingsStore: settingsStore)

        settingsStore.onChange = { [weak self] settings in
            self?.coordinator.apply(settings)
        }

        statusMenu.statusProvider = { [weak self] in
            guard let self else {
                return StatusMenuController.Status(accessibilityGranted: false, tapRunning: false, enabled: false, error: nil)
            }
            return StatusMenuController.Status(
                accessibilityGranted: AccessibilityPermission.isTrusted(),
                tapRunning: self.coordinator.isRunning,
                enabled: self.isEnabled,
                error: self.startupError
            )
        }
        statusMenu.onToggleEnabled = { [weak self] in self?.toggleEnabled() }
        statusMenu.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusMenu.onQuit = { NSApp.terminate(nil) }

        // Any held-key state is meaningless once the machine sleeps or the screen locks.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(cancelSession), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(cancelSession), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(cancelSession), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        // Posted whenever the Accessibility list changes. Lets a revoke/re-grant take effect
        // without waiting for the poll (the TCC database lags the notification slightly).
        distributed.addObserver(self, selector: #selector(accessibilityPermissionChanged), name: Notification.Name("com.apple.accessibility.api"), object: nil)

        startWhenPermitted(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        coordinator?.stop()
        Log.app.info("RightCmd terminating")
    }

    // MARK: Permission & lifecycle

    /// Starts the event tap as soon as Accessibility permission is available. macOS grants
    /// it without restarting the app, so poll briefly after prompting.
    private func startWhenPermitted(prompt: Bool) {
        permissionTimer?.invalidate()
        permissionTimer = nil

        if AccessibilityPermission.isTrusted(prompt: prompt) {
            startCoordinator()
            return
        }

        Log.app.notice("Accessibility permission not granted yet; waiting")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AccessibilityPermission.isTrusted() {
                timer.invalidate()
                self.permissionTimer = nil
                Log.app.notice("Accessibility permission granted")
                self.startCoordinator()
            }
        }
    }

    private func startCoordinator() {
        guard isEnabled else { return }
        do {
            try coordinator.start()
            startupError = nil
        } catch {
            startupError = error.localizedDescription
            Log.app.error("Failed to start: \(error.localizedDescription, privacy: .public)")
            // Trust can be revoked at any time (e.g. the app was re-signed). Keep polling so
            // that re-granting it brings the tap back without a relaunch.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if (try? self.coordinator.start()) != nil {
                    timer.invalidate()
                    self.permissionTimer = nil
                    self.startupError = nil
                }
            }
        }
    }

    private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startWhenPermitted(prompt: false)
        } else {
            permissionTimer?.invalidate()
            permissionTimer = nil
            coordinator.stop()
        }
        Log.app.info("RightCmd \(self.isEnabled ? "enabled" : "paused")")
    }

    @objc private func cancelSession() {
        coordinator?.cancelSession()
    }

    @objc private func accessibilityPermissionChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isEnabled else { return }
            Log.app.notice("Accessibility permission changed; trusted = \(AccessibilityPermission.isTrusted())")
            // A revoke-and-regrant leaves an existing tap dead, so always rebuild: if trust
            // is present this starts a fresh tap, otherwise it goes back to waiting.
            self.coordinator.stop()
            self.startWhenPermitted(prompt: false)
        }
    }
}
