import Foundation

/// When the selected app is brought to the front.
public enum SwitchMode: String, Codable, CaseIterable, Sendable {
    /// Switch immediately as each letter is typed (like the reference implementation).
    case live
    /// Only switch when right ⌘ is released or Return is pressed.
    case onRelease
}

/// Where the overlay appears on the screen.
public enum OverlayPosition: String, Codable, CaseIterable, Sendable {
    case center
    case top
    case bottom
}

public struct Settings: Codable, Equatable, Sendable {
    public var switchMode: SwitchMode = .live
    public var matchWordPrefixes: Bool = true
    public var matchInitials: Bool = true
    /// When the best match is the app that was already in front when right ⌘ was pressed,
    /// prefer the next match instead. Off by default so that the same keys always land on
    /// the same app.
    public var skipFrontmostApp: Bool = false
    /// As soon as the typed letters match exactly one app, switch to it and stop
    /// interpreting keys until right ⌘ is released. Applies in both switch modes.
    public var commitOnUniqueMatch: Bool = true
    /// When a hold ends with a switch, move the pointer to the center of that app's window
    /// (unless it is already inside it). Off by default: it moves the user's hardware.
    public var movePointerToWindow: Bool = false
    /// When the target app's window is on another Space, jump there without the slide
    /// animation (the InstantSpaceSwitcher technique). Off by default: it relies on
    /// private window-server APIs.
    public var instantSpaceSwitching: Bool = false
    /// Let ← and → pass through to the system while right ⌘ is held, for people who bind
    /// ⌘← / ⌘→ to Mission Control's "move left/right a Space". ↑ and ↓ keep cycling matches.
    public var passThroughLeftRightArrows: Bool = false
    /// Let Space pass through to the system while right ⌘ is held, so ⌘Space launchers
    /// (Spotlight, Raycast, Alfred) can be bound to the right key as well.
    public var passThroughSpace: Bool = false
    /// Let any key pressed together with Shift, Option, Control or the left ⌘ pass through
    /// to the frontmost app while right ⌘ is held, so shortcuts such as ⌘⇧P keep working.
    /// While on, app names must be typed with right ⌘ alone.
    public var passThroughModifiedKeys: Bool = false
    /// Deliver the right ⌘ press and release themselves to apps instead of swallowing
    /// them. Needed only by apps that react to the modifier going down (⌘-hover link
    /// underlining, temporary tool modes, menu alternates); off by default because a bare
    /// ⌘ press also trips "double-tap ⌘" launchers.
    public var passThroughActivatorModifier: Bool = false
    public var showOverlay: Bool = true
    public var overlayPosition: OverlayPosition = .center
    /// Tint the menu bar icon while right ⌘ is held: `iconColors.listening` until something
    /// is typed, then `matched` or `noMatch`. A glanceable confirmation that doesn't need
    /// the overlay.
    public var tintMenuBarIcon: Bool = true
    public var iconColors: IconColors = .default
    /// Wildcard patterns matched against app names and bundle identifiers.
    public var excludedPatterns: [String] = []
    /// Apps that outrank all other matches, highest priority first. Same pattern syntax.
    public var priorityPatterns: [String] = []
    /// Finder is always running and always wins "F", so it is left out unless asked for.
    /// Kept separate from `excludedPatterns` so the default can change without migrating
    /// user data and so re-enabling it is a single switch.
    public var includeFinder: Bool = false

    public init() {}

    public static let `default` = Settings()

    public var matchOptions: MatchOptions {
        MatchOptions(wordPrefixes: matchWordPrefixes, initials: matchInitials, priority: priorityList)
    }

    public var priorityList: PriorityList {
        PriorityList(patterns: priorityPatterns)
    }

    /// Bundle identifiers excluded unless the matching `include…` setting is on.
    public static let finderBundleIdentifier = "com.apple.finder"

    /// The user's patterns plus any built-in exclusions that are currently in force.
    public var exclusionList: ExclusionList {
        var patterns = excludedPatterns
        if !includeFinder {
            patterns.append(Self.finderBundleIdentifier)
        }
        return ExclusionList(patterns: patterns)
    }

    // MARK: Codable
    //
    // Every key is optional on decode so settings saved by an older version keep working
    // after new fields are added, and a corrupt single value doesn't discard everything.

    private enum CodingKeys: String, CodingKey {
        case switchMode, matchWordPrefixes, matchInitials, skipFrontmostApp
        case commitOnUniqueMatch, movePointerToWindow, instantSpaceSwitching
        case passThroughLeftRightArrows, passThroughSpace, passThroughModifiedKeys, passThroughActivatorModifier
        case showOverlay, overlayPosition, tintMenuBarIcon, iconColors
        case excludedPatterns, includeFinder, priorityPatterns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        switchMode = (try? c.decodeIfPresent(SwitchMode.self, forKey: .switchMode)) ?? defaults.switchMode
        matchWordPrefixes = (try? c.decodeIfPresent(Bool.self, forKey: .matchWordPrefixes)) ?? defaults.matchWordPrefixes
        matchInitials = (try? c.decodeIfPresent(Bool.self, forKey: .matchInitials)) ?? defaults.matchInitials
        skipFrontmostApp = (try? c.decodeIfPresent(Bool.self, forKey: .skipFrontmostApp)) ?? defaults.skipFrontmostApp
        commitOnUniqueMatch = (try? c.decodeIfPresent(Bool.self, forKey: .commitOnUniqueMatch)) ?? defaults.commitOnUniqueMatch
        movePointerToWindow = (try? c.decodeIfPresent(Bool.self, forKey: .movePointerToWindow)) ?? defaults.movePointerToWindow
        instantSpaceSwitching = (try? c.decodeIfPresent(Bool.self, forKey: .instantSpaceSwitching)) ?? defaults.instantSpaceSwitching
        passThroughLeftRightArrows = (try? c.decodeIfPresent(Bool.self, forKey: .passThroughLeftRightArrows)) ?? defaults.passThroughLeftRightArrows
        passThroughSpace = (try? c.decodeIfPresent(Bool.self, forKey: .passThroughSpace)) ?? defaults.passThroughSpace
        passThroughModifiedKeys = (try? c.decodeIfPresent(Bool.self, forKey: .passThroughModifiedKeys)) ?? defaults.passThroughModifiedKeys
        passThroughActivatorModifier = (try? c.decodeIfPresent(Bool.self, forKey: .passThroughActivatorModifier)) ?? defaults.passThroughActivatorModifier
        showOverlay = (try? c.decodeIfPresent(Bool.self, forKey: .showOverlay)) ?? defaults.showOverlay
        overlayPosition = (try? c.decodeIfPresent(OverlayPosition.self, forKey: .overlayPosition)) ?? defaults.overlayPosition
        tintMenuBarIcon = (try? c.decodeIfPresent(Bool.self, forKey: .tintMenuBarIcon)) ?? defaults.tintMenuBarIcon
        iconColors = (try? c.decodeIfPresent(IconColors.self, forKey: .iconColors)) ?? defaults.iconColors
        excludedPatterns = (try? c.decodeIfPresent([String].self, forKey: .excludedPatterns)) ?? defaults.excludedPatterns
        includeFinder = (try? c.decodeIfPresent(Bool.self, forKey: .includeFinder)) ?? defaults.includeFinder
        priorityPatterns = (try? c.decodeIfPresent([String].self, forKey: .priorityPatterns)) ?? defaults.priorityPatterns
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(switchMode, forKey: .switchMode)
        try c.encode(matchWordPrefixes, forKey: .matchWordPrefixes)
        try c.encode(matchInitials, forKey: .matchInitials)
        try c.encode(skipFrontmostApp, forKey: .skipFrontmostApp)
        try c.encode(commitOnUniqueMatch, forKey: .commitOnUniqueMatch)
        try c.encode(movePointerToWindow, forKey: .movePointerToWindow)
        try c.encode(instantSpaceSwitching, forKey: .instantSpaceSwitching)
        try c.encode(passThroughLeftRightArrows, forKey: .passThroughLeftRightArrows)
        try c.encode(passThroughSpace, forKey: .passThroughSpace)
        try c.encode(passThroughModifiedKeys, forKey: .passThroughModifiedKeys)
        try c.encode(passThroughActivatorModifier, forKey: .passThroughActivatorModifier)
        try c.encode(showOverlay, forKey: .showOverlay)
        try c.encode(overlayPosition, forKey: .overlayPosition)
        try c.encode(tintMenuBarIcon, forKey: .tintMenuBarIcon)
        try c.encode(iconColors, forKey: .iconColors)
        try c.encode(excludedPatterns, forKey: .excludedPatterns)
        try c.encode(includeFinder, forKey: .includeFinder)
        try c.encode(priorityPatterns, forKey: .priorityPatterns)
    }
}

/// Persists `Settings` as JSON in `UserDefaults` and notifies observers of changes.
///
/// Not thread-safe by design: use it from the main thread only.
public final class SettingsStore {
    public static let defaultKey = "RightCmd.settings"

    private let defaults: UserDefaults
    private let key: String

    public private(set) var settings: Settings
    /// Called after every successful change, on the caller's thread.
    public var onChange: ((Settings) -> Void)?

    public init(defaults: UserDefaults = .standard, key: String = SettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
        self.settings = Self.load(from: defaults, key: key)
    }

    /// Mutate the settings in place; the result is saved and observers are notified.
    public func update(_ transform: (inout Settings) -> Void) {
        var copy = settings
        transform(&copy)
        replace(copy)
    }

    public func replace(_ newSettings: Settings) {
        guard newSettings != settings else { return }
        settings = newSettings
        save()
        onChange?(newSettings)
    }

    public func resetToDefaults() {
        replace(.default)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            // Encoding a plain Codable struct cannot realistically fail; keep the in-memory
            // value regardless so the running app behaves as the user asked.
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> Settings {
        guard let data = defaults.data(forKey: key) else { return .default }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? .default
    }
}
