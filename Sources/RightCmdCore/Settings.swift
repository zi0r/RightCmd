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
    public var showOverlay: Bool = true
    public var overlayPosition: OverlayPosition = .center
    /// Wildcard patterns matched against app names and bundle identifiers.
    public var excludedPatterns: [String] = []

    public init() {}

    public static let `default` = Settings()

    public var matchOptions: MatchOptions {
        MatchOptions(wordPrefixes: matchWordPrefixes, initials: matchInitials)
    }

    public var exclusionList: ExclusionList {
        ExclusionList(patterns: excludedPatterns)
    }

    // MARK: Codable
    //
    // Every key is optional on decode so settings saved by an older version keep working
    // after new fields are added, and a corrupt single value doesn't discard everything.

    private enum CodingKeys: String, CodingKey {
        case switchMode, matchWordPrefixes, matchInitials, skipFrontmostApp
        case commitOnUniqueMatch, showOverlay, overlayPosition, excludedPatterns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        switchMode = (try? c.decodeIfPresent(SwitchMode.self, forKey: .switchMode)) ?? defaults.switchMode
        matchWordPrefixes = (try? c.decodeIfPresent(Bool.self, forKey: .matchWordPrefixes)) ?? defaults.matchWordPrefixes
        matchInitials = (try? c.decodeIfPresent(Bool.self, forKey: .matchInitials)) ?? defaults.matchInitials
        skipFrontmostApp = (try? c.decodeIfPresent(Bool.self, forKey: .skipFrontmostApp)) ?? defaults.skipFrontmostApp
        commitOnUniqueMatch = (try? c.decodeIfPresent(Bool.self, forKey: .commitOnUniqueMatch)) ?? defaults.commitOnUniqueMatch
        showOverlay = (try? c.decodeIfPresent(Bool.self, forKey: .showOverlay)) ?? defaults.showOverlay
        overlayPosition = (try? c.decodeIfPresent(OverlayPosition.self, forKey: .overlayPosition)) ?? defaults.overlayPosition
        excludedPatterns = (try? c.decodeIfPresent([String].self, forKey: .excludedPatterns)) ?? defaults.excludedPatterns
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(switchMode, forKey: .switchMode)
        try c.encode(matchWordPrefixes, forKey: .matchWordPrefixes)
        try c.encode(matchInitials, forKey: .matchInitials)
        try c.encode(skipFrontmostApp, forKey: .skipFrontmostApp)
        try c.encode(commitOnUniqueMatch, forKey: .commitOnUniqueMatch)
        try c.encode(showOverlay, forKey: .showOverlay)
        try c.encode(overlayPosition, forKey: .overlayPosition)
        try c.encode(excludedPatterns, forKey: .excludedPatterns)
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
