import Foundation

/// Controls which match strategies `AppMatcher` applies beyond the plain name prefix.
public struct MatchOptions: Equatable, Sendable {
    /// Also match the query against the start of any later word in the name,
    /// so "c" finds "Google Chrome" and "s" finds "System Settings".
    public var wordPrefixes: Bool
    /// Also match the query against the initials of multi-word names,
    /// so "vsc" finds "Visual Studio Code".
    public var initials: Bool

    public init(wordPrefixes: Bool = true, initials: Bool = true) {
        self.wordPrefixes = wordPrefixes
        self.initials = initials
    }
}

/// How a candidate matched. Lower tiers rank first.
public enum MatchTier: Int, Comparable, Sendable {
    /// The app name starts with the query ("sa" → "Safari").
    case namePrefix = 0
    /// A later word of the app name starts with the query ("ch" → "Google Chrome").
    case wordPrefix = 1
    /// The initials of the app name start with the query ("vs" → "Visual Studio Code").
    case initials = 2

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A candidate together with the reason it matched.
public struct RankedMatch: Equatable, Sendable {
    public let candidate: AppCandidate
    public let tier: MatchTier
}

/// Ranks running applications against the letters typed while the activator key is held.
///
/// Ranking is deterministic so that a given query always lands on the same app:
/// better tier first, then case-insensitive alphabetical by name, then by process id.
/// This is what makes "rcmd-S always goes to the same S app" learnable; the user types
/// more letters to disambiguate.
public enum AppMatcher {
    /// Returns every candidate that matches `query`, best first.
    public static func rankedMatches(
        for query: String,
        in candidates: [AppCandidate],
        options: MatchOptions = MatchOptions()
    ) -> [RankedMatch] {
        let foldedQuery = StringNormalization.fold(query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foldedQuery.isEmpty else { return [] }

        struct Scored {
            let candidate: AppCandidate
            let tier: MatchTier
            let foldedName: String
        }

        var scored: [Scored] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            let foldedName = StringNormalization.fold(candidate.name)
            guard let tier = tier(forFoldedName: foldedName, query: foldedQuery, options: options) else {
                continue
            }
            scored.append(Scored(candidate: candidate, tier: tier, foldedName: foldedName))
        }

        scored.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.foldedName != rhs.foldedName { return lhs.foldedName < rhs.foldedName }
            if lhs.candidate.name != rhs.candidate.name { return lhs.candidate.name < rhs.candidate.name }
            return lhs.candidate.id < rhs.candidate.id
        }

        return scored.map { RankedMatch(candidate: $0.candidate, tier: $0.tier) }
    }

    /// Convenience: the matching candidates only, best first.
    public static func matches(
        for query: String,
        in candidates: [AppCandidate],
        options: MatchOptions = MatchOptions()
    ) -> [AppCandidate] {
        rankedMatches(for: query, in: candidates, options: options).map(\.candidate)
    }

    /// The best tier at which an already-folded name matches an already-folded query.
    static func tier(forFoldedName name: String, query: String, options: MatchOptions) -> MatchTier? {
        if name.hasPrefix(query) {
            return .namePrefix
        }
        let words = StringNormalization.words(name)
        if options.wordPrefixes, words.dropFirst().contains(where: { $0.hasPrefix(query) }) {
            return .wordPrefix
        }
        if options.initials, words.count > 1 {
            let initials = String(words.compactMap { $0.first })
            if initials.hasPrefix(query) {
                return .initials
            }
        }
        return nil
    }
}
