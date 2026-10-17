import Foundation

/// An ordered list of apps that should rank ahead of all other matches, in the user's
/// preferred order. Entries are wildcard patterns matched against the app name or bundle
/// identifier, like `ExclusionList`.
///
/// A prioritised app still has to match the typed letters; priority only decides the
/// order among apps that match. Apps matched by the same pattern share its rank and fall
/// back to the usual tier/alphabetical ordering among themselves.
public struct PriorityList: Equatable, Sendable {
    public let patterns: [WildcardPattern]

    public init(patterns: [String]) {
        self.patterns = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(WildcardPattern.init)
    }

    public static let empty = PriorityList(patterns: [])

    public var isEmpty: Bool { patterns.isEmpty }

    /// The position of the first pattern that matches the candidate (0 = highest priority),
    /// or nil if the candidate is not prioritised.
    public func rank(of candidate: AppCandidate) -> Int? {
        patterns.firstIndex { pattern in
            pattern.matches(candidate.name)
                || (candidate.bundleIdentifier.map(pattern.matches) ?? false)
        }
    }
}
