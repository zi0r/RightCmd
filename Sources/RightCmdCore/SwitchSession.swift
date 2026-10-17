import Foundation

/// What the overlay should display.
public struct OverlayState: Equatable, Sendable {
    /// The letters typed so far.
    public var query: String
    /// Matching apps, best first.
    public var matches: [AppCandidate]
    /// Index into `matches` of the app that will be (or has been) activated.
    public var selectedIndex: Int?
    /// True when macOS secure input is on (e.g. a password field is focused), which stops
    /// the event tap from seeing key presses. Shown so the user knows why typing does nothing.
    public var secureInputActive: Bool

    public init(query: String, matches: [AppCandidate], selectedIndex: Int?, secureInputActive: Bool) {
        self.query = query
        self.matches = matches
        self.selectedIndex = selectedIndex
        self.secureInputActive = secureInputActive
    }

    public var selected: AppCandidate? {
        guard let index = selectedIndex, matches.indices.contains(index) else { return nil }
        return matches[index]
    }
}

/// Input to the session.
public enum SessionEvent: Equatable, Sendable {
    /// Right ⌘ went down.
    case activatorPressed
    /// Right ⌘ went up.
    case activatorReleased
    /// A key was pressed while right ⌘ was held.
    case key(KeyInput)
    /// The event tap was disabled or permissions were lost; abandon the session.
    case interrupted
}

/// Output of the session for the app layer to carry out, in order.
public enum SessionAction: Equatable, Sendable {
    case showOverlay(OverlayState)
    case hideOverlay
    case activate(AppCandidate)
}

/// A snapshot of the environment taken when a session starts.
public struct SessionContext: Equatable, Sendable {
    /// Switchable apps (already filtered by the exclusion list).
    public var candidates: [AppCandidate]
    /// The app that was in front when right ⌘ was pressed.
    public var frontmost: AppCandidate?
    public var secureInputActive: Bool

    public init(candidates: [AppCandidate], frontmost: AppCandidate? = nil, secureInputActive: Bool = false) {
        self.candidates = candidates
        self.frontmost = frontmost
        self.secureInputActive = secureInputActive
    }
}

/// Models one "hold right ⌘, type, release" interaction.
///
/// The session is pure: it owns no system resources and performs no side effects. It
/// returns `SessionAction`s that the app layer executes. That makes the whole interaction
/// testable, including edge cases such as Escape, cycling, repeated letters, and the tap
/// being disabled mid-session.
public final class SwitchSession {
    private enum Phase {
        /// Right ⌘ is not held.
        case idle
        /// Right ⌘ is held and keys are being interpreted.
        case typing
        /// The session was ended by Escape or Return but right ⌘ is still held;
        /// further keys are ignored until it is released.
        case finished
    }

    public var settings: Settings
    private let contextProvider: () -> SessionContext

    private var phase: Phase = .idle
    private var context = SessionContext(candidates: [])
    private var query = ""
    private var matches: [AppCandidate] = []
    private var selectedIndex: Int?
    private var overlayVisible = false
    /// The app most recently activated in this session, to avoid re-activating it.
    private var lastActivated: AppCandidate?

    public init(settings: Settings, contextProvider: @escaping () -> SessionContext) {
        self.settings = settings
        self.contextProvider = contextProvider
    }

    /// True while right ⌘ is held (typing or finished).
    public var isActive: Bool {
        phase != .idle
    }

    /// The current query, for diagnostics.
    public var currentQuery: String { query }

    public func handle(_ event: SessionEvent) -> [SessionAction] {
        switch event {
        case .activatorPressed:
            return begin()
        case .activatorReleased:
            return end()
        case .key(let input):
            guard phase == .typing else { return [] }
            return handleKey(input)
        case .interrupted:
            return reset()
        }
    }

    // MARK: - Lifecycle

    private func begin() -> [SessionAction] {
        guard phase == .idle else { return [] }
        phase = .typing
        context = contextProvider()
        query = ""
        matches = []
        selectedIndex = nil
        lastActivated = nil
        overlayVisible = false
        // Normally nothing is shown until the first letter. If secure input is on, show the
        // overlay at once so the user learns why their letters aren't registering.
        if context.secureInputActive {
            return overlayUpdate()
        }
        return []
    }

    private func end() -> [SessionAction] {
        guard phase != .idle else { return [] }
        var actions: [SessionAction] = []
        if phase == .typing, settings.switchMode == .onRelease, let target = selectedCandidate {
            actions.append(contentsOf: activate(target))
        }
        actions.append(contentsOf: hideOverlayIfNeeded())
        phase = .idle
        return actions
    }

    private func reset() -> [SessionAction] {
        let actions = hideOverlayIfNeeded()
        phase = .idle
        query = ""
        matches = []
        selectedIndex = nil
        lastActivated = nil
        return actions
    }

    // MARK: - Keys

    private func handleKey(_ input: KeyInput) -> [SessionAction] {
        switch input {
        case .character(let character):
            query.append(character)
            recomputeMatches()
            if let unique = uniqueMatchToCommit() {
                return commit(unique)
            }
            return overlayUpdate() + liveActivateIfNeeded()

        case .backspace:
            guard !query.isEmpty else { return [] }
            query.removeLast()
            recomputeMatches()
            if query.isEmpty {
                return hideOverlayIfNeeded()
            }
            if let unique = uniqueMatchToCommit() {
                return commit(unique)
            }
            return overlayUpdate() + liveActivateIfNeeded()

        case .escape:
            phase = .finished
            var actions = hideOverlayIfNeeded()
            // In live mode we may already have switched away; put the user back.
            if settings.switchMode == .live, lastActivated != nil, let original = context.frontmost {
                actions.append(contentsOf: activate(original))
            }
            return actions

        case .confirm:
            phase = .finished
            var actions: [SessionAction] = []
            if settings.switchMode == .onRelease, let target = selectedCandidate {
                actions.append(contentsOf: activate(target))
            }
            actions.append(contentsOf: hideOverlayIfNeeded())
            return actions

        case .next:
            return cycle(by: 1)

        case .previous:
            return cycle(by: -1)

        case .ignored:
            return []
        }
    }

    /// The single remaining match when `commitOnUniqueMatch` is on, otherwise nil.
    private func uniqueMatchToCommit() -> AppCandidate? {
        guard settings.commitOnUniqueMatch, matches.count == 1 else { return nil }
        return matches[0]
    }

    /// Switch to `candidate` now and stop interpreting keys until right ⌘ is released.
    /// The overlay is taken down rather than updated: the decision is already made, and a
    /// one-frame flash of the result would only be noise.
    private func commit(_ candidate: AppCandidate) -> [SessionAction] {
        phase = .finished
        return activate(candidate) + hideOverlayIfNeeded()
    }

    private func cycle(by delta: Int) -> [SessionAction] {
        guard matches.count > 1, let index = selectedIndex else { return [] }
        let count = matches.count
        selectedIndex = ((index + delta) % count + count) % count
        return overlayUpdate() + liveActivateIfNeeded()
    }

    // MARK: - Matching

    private func recomputeMatches() {
        matches = AppMatcher.matches(for: query, in: context.candidates, options: settings.matchOptions)
        guard !matches.isEmpty else {
            selectedIndex = nil
            return
        }
        if settings.skipFrontmostApp,
           let frontmost = context.frontmost,
           matches.count > 1,
           let alternative = matches.firstIndex(where: { $0.id != frontmost.id }) {
            selectedIndex = alternative
        } else {
            selectedIndex = 0
        }
    }

    private var selectedCandidate: AppCandidate? {
        guard let index = selectedIndex, matches.indices.contains(index) else { return nil }
        return matches[index]
    }

    // MARK: - Actions

    private func liveActivateIfNeeded() -> [SessionAction] {
        guard settings.switchMode == .live, let target = selectedCandidate else { return [] }
        return activate(target)
    }

    private func activate(_ candidate: AppCandidate) -> [SessionAction] {
        guard candidate != lastActivated else { return [] }
        lastActivated = candidate
        return [.activate(candidate)]
    }

    private func overlayUpdate() -> [SessionAction] {
        guard settings.showOverlay else { return [] }
        overlayVisible = true
        let state = OverlayState(
            query: query,
            matches: matches,
            selectedIndex: selectedIndex,
            secureInputActive: context.secureInputActive
        )
        return [.showOverlay(state)]
    }

    private func hideOverlayIfNeeded() -> [SessionAction] {
        guard overlayVisible else { return [] }
        overlayVisible = false
        return [.hideOverlay]
    }
}
