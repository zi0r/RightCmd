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
    /// True from the activator press we handled until its release. While true every key
    /// event is swallowed so letters never reach the frontmost app (⌘S must not save).
    private var activatorHeld = false
    /// Verifies against the live HID modifier state that the activator is really still
    /// down, so a missed release can never leave the keyboard swallowed.
    private var heldWatchdog: Timer?
    /// Whether the activator key's *press* was delivered to apps. Decided once per hold so the
    /// release is handled the same way even if the setting changes mid-hold; apps must
    /// never see an unbalanced modifier sequence.
    private var activatorEventDelivered = false

    /// The icon state the session itself asked for (listening / matched / no match). A
    /// pass-through is shown *over* this and the session state is restored when it ends.
    private var sessionIconState: IconState = .idle
    /// A modifier combination the modified-key pass-through setting hands on is held.
    private var modifierPassThroughActive = false
    /// Pass-through keys currently down, so their key-ups are passed on too and the icon
    /// returns to the session state only when the last one is released.
    private var heldPassThroughKeys: Set<Int64> = []
    private var isPassingThrough: Bool { modifierPassThroughActive || !heldPassThroughKeys.isEmpty }

    private(set) var lastError: Error?

    var isRunning: Bool { tap?.isRunning ?? false }

    init(
        settingsStore: SettingsStore,
        overlay: OverlayPresenting,
        activator: AppActivating? = nil,
        appProvider: AppProviding = WorkspaceAppProvider(),
        translator: KeyCharacterTranslating = KeyboardLayoutTranslator()
    ) {
        self.settingsStore = settingsStore
        self.overlay = overlay
        // The default activator jumps Spaces instantly when the setting asks for it, then
        // hands over to the Accessibility-based activation.
        self.activator = activator ?? SpaceAwareActivator(
            base: AccessibilityAppActivator(),
            isEnabled: { [settingsStore] in settingsStore.settings.instantSpaceSwitching }
        )
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

    /// The configured key (right ⌘/⌥/⌃). Distinct from `activator`, the app-activation
    /// strategy.
    private var activatorKey: ActivatorModifier { settingsStore.settings.activator }

    /// Returns true if the event should be swallowed.
    private func handle(_ event: TapEvent) -> Bool {
        switch event {
        case .flagsChanged(let keyCode, let flags):
            switch ActivatorKey.change(forFlagsChangedKeyCode: keyCode, flags: flags, activator: activatorKey) {
            case .pressed:
                guard !activatorHeld else { return !activatorEventDelivered }
                activatorEventDelivered = settingsStore.settings.passThroughActivatorModifier
                pressActivator(flags: flags)
                return !activatorEventDelivered
            case .released:
                guard activatorHeld else { return false }
                releaseActivator(reason: "key up")
                return !activatorEventDelivered
            case .none:
                // Another modifier changed. If the activator is no longer reported at all, the release
                // we were waiting for has been lost; let go now and pass this event on.
                if activatorHeld, !ActivatorKey.isHeld(flags, activator: activatorKey) {
                    releaseActivator(reason: "flags no longer include \(activatorKey.symbol)")
                } else if activatorHeld {
                    updateModifierPassThrough(flags: flags)
                }
                return false
            }

        case .keyDown(let keyCode, let flags, let isRepeat):
            guard activatorHeld else { return false }
            guard ActivatorKey.isHeld(flags, activator: activatorKey) else {
                // Same self-heal as above: a key arrived without the activator, so it isn't ours.
                releaseActivator(reason: "key down without \(activatorKey.symbol)")
                return false
            }
            if KeyPassThrough.passes(keyCode: keyCode, flags: flags, settings: settingsStore.settings) {
                // Hand the key on (e.g. ⌘← bound to "move left a Space", or ⌘⇧P for a
                // private window) and keep the session going; checked before the repeat
                // filter so a held key repeats for the receiver as usual.
                if !isRepeat, heldPassThroughKeys.insert(keyCode).inserted {
                    refreshIcon()
                }
                return false
            }
            if isRepeat || ActivatorKey.blocksTyping(flags, activator: activatorKey) {
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

        case .keyUp(let keyCode, let flags):
            guard activatorHeld else { return false }
            if heldPassThroughKeys.remove(keyCode) != nil {
                // The key went down as a pass-through, so its key up goes on too, even if
                // the modifier that qualified it (⇧ in ⌘⇧P) was released first.
                refreshIcon()
                return false
            }
            if KeyPassThrough.passes(keyCode: keyCode, flags: flags, settings: settingsStore.settings) {
                return false
            }
            return ActivatorKey.isHeld(flags, activator: activatorKey)

        case .tapDisabled:
            cancelSession()
            return false
        }
    }

    private func pressActivator(flags: ModifierFlags) {
        activatorHeld = true
        heldPassThroughKeys = []
        modifierPassThroughActive = false
        Log.session.debug("\(self.activatorKey.name, privacy: .public) down")
        perform(session.handle(.activatorPressed))
        reportIconState(.listening)
        // ⇧ may already be down when the activator arrives.
        updateModifierPassThrough(flags: flags)
        startWatchdog()
    }

    private func releaseActivator(reason: String) {
        stopWatchdog()
        activatorHeld = false
        Log.session.debug("\(self.activatorKey.name, privacy: .public) up (\(reason, privacy: .public))")
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
        if !ActivatorKey.isHeld(live, activator: activatorKey) {
            releaseActivator(reason: "watchdog: HID state shows \(activatorKey.symbol) up")
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
        sessionIconState = state
        if state == .idle {
            modifierPassThroughActive = false
            heldPassThroughKeys = []
        }
        onIconState?(isPassingThrough ? .passingThrough : state, linger)
    }

    /// Re-shows the icon after a pass-through started or ended, without touching the
    /// session's own state.
    private func refreshIcon() {
        guard activatorHeld, settingsStore.settings.tintMenuBarIcon else { return }
        onIconState?(isPassingThrough ? .passingThrough : sessionIconState, false)
    }

    private func updateModifierPassThrough(flags: ModifierFlags) {
        let active = settingsStore.settings.passThroughModifiedKeys && KeyPassThrough.hasExtraModifier(flags, activator: activatorKey)
        guard active != modifierPassThroughActive else { return }
        modifierPassThroughActive = active
        refreshIcon()
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
