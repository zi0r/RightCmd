import Foundation

/// Extra names the user wants an app matched under: `pattern` is a wildcard matched
/// against the app's names and bundle identifier (as for exclusions), `names` are the
/// aliases. E.g. `com.microsoft.rdc.macos` → ["Microsoft Remote Desktop", "RDP"].
public struct AppAlias: Codable, Equatable, Sendable {
    public var pattern: String
    public var names: [String]

    public init(pattern: String, names: [String]) {
        self.pattern = pattern
        self.names = names
    }
}

/// Resolves the aliases that apply to a candidate.
public struct AliasList: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let pattern: WildcardPattern
        let names: [String]
    }

    private let entries: [Entry]

    public init(_ aliases: [AppAlias]) {
        entries = aliases.compactMap { alias in
            let pattern = alias.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            let names = alias.names
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !pattern.isEmpty, !names.isEmpty else { return nil }
            return Entry(pattern: WildcardPattern(pattern), names: names)
        }
    }

    public static let empty = AliasList([])

    public var isEmpty: Bool { entries.isEmpty }

    /// Every alias from every entry whose pattern matches the candidate, in entry order.
    public func names(for candidate: AppCandidate) -> [String] {
        entries.filter { $0.pattern.matches(candidate) }.flatMap(\.names)
    }
}

extension WildcardPattern {
    /// Matches any of the candidate's names or its bundle identifier.
    public func matches(_ candidate: AppCandidate) -> Bool {
        if candidate.allNames.contains(where: matches) { return true }
        if let bundle = candidate.bundleIdentifier, matches(bundle) { return true }
        return false
    }
}
