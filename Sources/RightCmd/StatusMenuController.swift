import AppKit
import RightCmdCore

/// The menu bar item. All state is pulled fresh in `menuNeedsUpdate`, so the menu is
/// always accurate without observers.
final class StatusMenuController: NSObject, NSMenuDelegate {
    struct Status {
        var accessibilityGranted: Bool
        var tapRunning: Bool
        var enabled: Bool
        var error: String?
    }

    var statusProvider: () -> Status = { Status(accessibilityGranted: false, tapRunning: false, enabled: true, error: nil) }
    var onToggleEnabled: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let settingsStore: SettingsStore
    private let item: NSStatusItem
    private let menu = NSMenu()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "RightCmd")
            button.image?.isTemplate = true
            button.toolTip = "RightCmd — hold right ⌘ and type an app’s name"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = statusProvider()
        let settings = settingsStore.settings

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(disabled("RightCmd \(version)"))

        let statusText: String
        if !status.accessibilityGranted {
            statusText = "Waiting for Accessibility permission…"
        } else if let error = status.error {
            statusText = "Error: \(error)"
        } else if !status.enabled {
            statusText = "Paused"
        } else if status.tapRunning {
            statusText = "Active — hold right ⌘ and type"
        } else {
            statusText = "Starting…"
        }
        menu.addItem(disabled(statusText))

        if !status.accessibilityGranted {
            menu.addItem(action("Open Accessibility Settings…", #selector(openAccessibility)))
        }
        menu.addItem(.separator())

        let enabledItem = action("Enabled", #selector(toggleEnabled))
        enabledItem.state = status.enabled ? .on : .off
        menu.addItem(enabledItem)

        let modeMenu = NSMenu()
        for mode in SwitchMode.allCases {
            let modeItem = action(Self.title(for: mode), #selector(selectMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = settings.switchMode == mode ? .on : .off
            modeMenu.addItem(modeItem)
        }
        let modeParent = NSMenuItem(title: "Switch Mode", action: nil, keyEquivalent: "")
        modeParent.submenu = modeMenu
        menu.addItem(modeParent)

        let overlayItem = action("Show Overlay", #selector(toggleOverlay))
        overlayItem.state = settings.showOverlay ? .on : .off
        menu.addItem(overlayItem)

        let loginItem = action("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        loginItem.isEnabled = LaunchAtLogin.isSupported
        if !LaunchAtLogin.isSupported {
            loginItem.toolTip = "Available when running from RightCmd.app"
        }
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let settingsItem = action("Settings…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = action("Quit RightCmd", #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        onToggleEnabled?()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = SwitchMode(rawValue: raw) else { return }
        settingsStore.update { $0.switchMode = mode }
    }

    @objc private func toggleOverlay() {
        settingsStore.update { $0.showOverlay.toggle() }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            Log.app.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        onQuit?()
    }

    // MARK: Helpers

    static func title(for mode: SwitchMode) -> String {
        switch mode {
        case .live: return "As You Type"
        case .onRelease: return "When Right ⌘ Is Released"
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }
}
