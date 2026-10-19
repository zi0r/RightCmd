import AppKit
import RightCmdCore

/// What the menu bar icon reflects while right ⌘ is held.
enum IconState: Equatable {
    /// Right ⌘ is not held: the plain template icon.
    case idle
    /// Right ⌘ is held, nothing typed yet.
    case listening
    /// The typed letters match at least one app (or an app was just switched to).
    case matched
    /// The typed letters match nothing.
    case noMatch
    /// Keys are being handed on rather than interpreted (a pass-through key is down, or a
    /// modifier combination the pass-through settings cover is held).
    case passingThrough
}

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

    private static let idleSymbol = "command.square"
    private static let activeSymbol = "command.square.fill"
    /// How long a match/no-match colour stays visible after right ⌘ is released, so the
    /// outcome of a quick switch is still readable.
    private static let lingerDuration: TimeInterval = 0.45
    private var iconState: IconState = .idle
    /// Incremented per transition so a pending linger from an earlier release can't clobber
    /// a newer state.
    private var iconGeneration = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = Self.symbol(Self.idleSymbol)
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

        let tintItem = action("Tint Icon While Switching", #selector(toggleTint))
        tintItem.state = settings.tintMenuBarIcon ? .on : .off
        menu.addItem(tintItem)

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

    // MARK: Icon state

    /// Sets the icon's state. Going back to `.idle` from a match/no-match state is delayed
    /// by `lingerDuration` when `linger` is true, so a quick press-type-release still shows
    /// its outcome; pass `linger: false` to drop to idle at once (cancel, Escape, sleep).
    func show(_ state: IconState, linger: Bool = true) {
        iconGeneration += 1
        let generation = iconGeneration

        if state == .idle, linger, iconState == .matched || iconState == .noMatch {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerDuration) { [weak self] in
                guard let self, self.iconGeneration == generation else { return }
                self.apply(.idle)
            }
            return
        }
        apply(state)
    }

    private func apply(_ state: IconState) {
        iconState = state
        item.button?.image = image(for: state)
    }

    private func image(for state: IconState) -> NSImage? {
        let colors = settingsStore.settings.iconColors
        switch state {
        case .idle:
            return Self.symbol(Self.idleSymbol)
        case .listening:
            return Self.tintedSymbol(Self.activeSymbol, color: NSColor(colors.listening))
        case .matched:
            return Self.tintedSymbol(Self.activeSymbol, color: NSColor(colors.matched))
        case .noMatch:
            return Self.tintedSymbol(Self.activeSymbol, color: NSColor(colors.noMatch))
        case .passingThrough:
            return Self.tintedSymbol(Self.activeSymbol, color: NSColor(colors.passThrough))
        }
    }

    /// The plain template icon, which the menu bar renders in its own monochrome style.
    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "RightCmd")
        image?.isTemplate = true
        return image
    }

    /// A coloured, non-template copy of a symbol. The colour is baked into the bitmap:
    /// `NSStatusBarButton.contentTintColor` is not honoured by the macOS 26 menu bar (it
    /// substitutes the accent colour), so tinting has to be done by hand.
    private static func tintedSymbol(_ name: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "RightCmd") else {
            return nil
        }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "RightCmd"
        return image
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

    @objc private func toggleTint() {
        settingsStore.update { $0.tintMenuBarIcon.toggle() }
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
