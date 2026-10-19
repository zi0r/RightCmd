import Foundation

/// A running application that can be switched to.
///
/// This is a platform-neutral value type so the matching and session logic can be
/// unit tested without AppKit. The app layer builds these from `NSRunningApplication`.
public struct AppCandidate: Hashable, Identifiable, Sendable {
    /// The process identifier. Unique among running processes.
    public let id: Int32
    /// The user-visible application name, e.g. "Safari" or "Visual Studio Code".
    public let name: String
    /// The bundle identifier, when known, e.g. "com.apple.Safari".
    public let bundleIdentifier: String?
    /// Other names macOS has for the app (bundle file name, `CFBundleName`,
    /// `CFBundleDisplayName`) when they differ from `name`. Matched like `name`.
    public let alternateNames: [String]

    public init(id: Int32, name: String, bundleIdentifier: String? = nil, alternateNames: [String] = []) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.alternateNames = Self.dedupe(alternateNames, excluding: name)
    }

    /// `name` first, then the alternates. Never contains case-insensitive duplicates.
    public var allNames: [String] { [name] + alternateNames }

    static func dedupe(_ names: [String], excluding primary: String) -> [String] {
        var seen: Set<String> = [StringNormalization.fold(primary)]
        var result: [String] = []
        for raw in names {
            let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            let key = StringNormalization.fold(candidate)
            if seen.insert(key).inserted {
                result.append(candidate)
            }
        }
        return result
    }
}
