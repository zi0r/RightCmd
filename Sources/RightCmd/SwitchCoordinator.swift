import AppKit
import RightCmdCore

/// Owns the event tap and routes its events through the core `SwitchSession`, carrying
/// out the resulting actions (overlay updates, app activation). Main thread only.
final class SwitchCoordinator {
    /// Called whenever the menu bar icon should change. The Bool is `linger`: whether a
    /// return to `.idle` may stay on the previous colour briefly (see `StatusMenuController.show`).
    var onIconState: ((IconState, Bool) -> Void)?

    private let settingsStore: SettingsStore
    private let overlay: OverlayPresenting
    private let activator: AppActivating
    private let appProvider: AppProviding
    private let translator: KeyCharacterTranslating

    private var session: SwitchSession!
    private var tap: KeyboardEventTap?
    /// True from the right ⌘ press we handled until its release. While true every key
    /// event is swallowed so letters never reach the frontmost app (⌘S must not save).
    private var activatorHeld = false
    /// Verifies against the live HID modifier state that right ⌘ is really still down,
    /// so a missed release can never leave the keyboard swallowed.
    private var heldWatchdog: Timer?

    private(set) var lastError: Error?

    var isRunning: Bool { tap?.isRunning ?? false }

    init(
        settingsStore: SettingsStore,
        overlay: OverlayPresenting,
        activator: AppActivating = AccessibilityAppActivator(),
        appProvider: AppProviding = WorkspaceAppProvider(),
        translator: KeyCharacterTranslating = KeyboardLayoutTranslator()
    ) {
        self.settingsStore = settingsStore
        self.overlay = overlay
        self.activator = activator
        self.appProvider = appProvider
        self.translator = translator

        self.session = SwitchSession(settings: settingsStore.settings) { [weak self] in
            self?.makeContext() ?? SessionContext(candidates: [])
        }
        overlay.position = settingsStore.settings.overlayPosition
    }

    // MARK: Lifecycle

    func start() throws {
        guard tap == nil else { return }
        let tap = KeyboardEventTap { [weak self] event in
            self?.handle(event) ?? false
        }
        do {
            try tap.start()
            lastError = nil
        } catch {
            lastError = error
            throw error
        }
        self.tap = tap
    }

    func stop() {
        cancelSession()
        tap?.stop()
        tap = nil
    }

    /// Abandons any in-progress session (sleep, lock, permission change). The tap stays up.
    func cancelSession() {
        stopWatchdog()
        activatorHeld = false
        perform(session.handle(.interrupted))
        reportIconState(.idle, linger: false)
    }

    /// Apply new settings. The core session reads them live, so this also affects a
    /// session that is in progress.
    func apply(_ settings: Settings) {
        session.settings = settings
        overlay.position = settings.overlayPosition
    }

    // MARK: Event handling

    private func makeContext() -> SessionContext {
        let settings = settingsStore.settings
        return SessionContext(
            candidates: appProvider.candidates(excluding: settings.exclusionList),
            frontmost: appProvider.frontmost(),
            secureInputActive: SecureInput.isEnabled
        )
    }

    /// Returns true if the event should be swallowed.
    private func handle(_ event: TapEvent) -> Bool {
        switch event {
        case .flagsChanged(let keyCode, let flags):
            switch ActivatorKey.change(forFlagsChangedKeyCode: keyCode, flags: flags) {
            case .pressed:
                guard !activatorHeld else { return true }
                pressActivator()
                return true
            case .released:
                guard activatorHeld else { return false }
                releaseActivator(reason: "key up")
                return true
            case .none:
                // Another modifier changed. If ⌘ is no longer reported at all, the release
                // we were waiting for has been lost; let go now and pass this event on.
                if activatorHeld, !ActivatorKey.isRightCommandHeld(flags) {
                    releaseActivator(reason: "flags no longer include ⌘")
                }
                return false
            }

        case .keyDown(let keyCode, let flags, let isRepeat):
            guard activatorHeld else { return false }
            guard ActivatorKey.isRightCommandHeld(flags) else {
                // Same self-heal as above: a key arrived without ⌘, so it isn't ours.
                releaseActivator(reason: "key down without ⌘")
                return false
            }
            if isRepeat || ActivatorKey.blocksTyping(flags) {
                return true
            }
            let character = translator.character(forKeyCode: keyCode)
            let input = KeyClassifier.classify(keyCode: keyCode, character: character)
            // Sample before handling: a key that commits a unique match flips the session to
            // finished, and it should still count as a hit.
            let wasAccepting = session.isAcceptingKeys
            let actions = session.handle(.key(input))
            perform(actions)
            if wasAccepting {
                reportIconState(afterKey: input, actions: actions)
            }
            return true

        case .keyUp(_, let flags):
            guard activatorHeld else { return false }
            return ActivatorKey.isRightCommandHeld(flags)

        case .tapDisabled:
            cancelSession()
            return false
        }
    }

    private func pressActivator() {
        activatorHeld = true
        Log.session.debug("Right ⌘ down")
        perform(session.handle(.activatorPressed))
        reportIconState(.listening)
        startWatchdog()
    }

    private func releaseActivator(reason: String) {
        stopWatchdog()
        activatorHeld = false
        Log.session.debug("Right ⌘ up (\(reason, privacy: .public))")
        let actions = session.handle(.activatorReleased)
        perform(actions)
        if actions.contains(where: Self.isActivation) {
            // On-release mode: the switch happens now, so show it before fading out.
            reportIconState(.matched)
        }
        reportIconState(.idle, linger: true)
    }

    // MARK: Watchdog

    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkActivatorStillHeld()
        }
        // .common so it keeps firing while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        heldWatchdog = timer
    }

    private func stopWatchdog() {
        heldWatchdog?.invalidate()
        heldWatchdog = nil
    }

    private func checkActivatorStillHeld() {
        guard activatorHeld else {
            stopWatchdog()
            return
        }
        let live = ModifierFlags(rawValue: CGEventSource.flagsState(.hidSystemState).rawValue)
        if !ActivatorKey.isRightCommandHeld(live) {
            releaseActivator(reason: "watchdog: HID state shows ⌘ up")
        }
    }

    // MARK: Icon feedback

    private static func isActivation(_ action: SessionAction) -> Bool {
        if case .activate = action { return true }
        return false
    }

    private func reportIconState(_ state: IconState, linger: Bool = true) {
        // `.idle` always goes through so the icon can't stay tinted after the setting is
        // switched off mid-session.
        guard state == .idle || settingsStore.settings.tintMenuBarIcon else { return }
        onIconState?(state, linger)
    }

    private func reportIconState(afterKey input: KeyInput, actions: [SessionAction]) {
        if actions.contains(where: Self.isActivation) {
            // Live switch or unique-match commit: a hit, whatever the key was.
            reportIconState(.matched)
            return
        }
        guard session.isAcceptingKeys else {
            // Escape, or Return with nothing to switch to: the session is over.
            reportIconState(.idle, linger: false)
            return
        }
        if session.currentQuery.isEmpty {
            reportIconState(.listening)
        } else {
            reportIconState(session.currentMatches.isEmpty ? .noMatch : .matched)
        }
    }

    // MARK: Actions

    private func perform(_ actions: [SessionAction]) {
        for action in actions {
            switch action {
            case .showOverlay(let state):
                overlay.show(state)
            case .hideOverlay:
                overlay.hide()
            case .activate(let candidate):
                // Return from the tap callback promptly; macOS disables slow taps.
                let activator = self.activator
                DispatchQueue.main.async {
                    activator.activate(candidate)
                }
            case .movePointer(let candidate):
                // Queued behind the activation above on the same queue, so it runs right
                // after it. The window frame comes from the target app's own AX tree, which
                // doesn't depend on the activation having landed yet.
                DispatchQueue.main.async {
                    PointerMover.centerPointer(inWindowOf: candidate)
                }
            }
        }
    }
}
