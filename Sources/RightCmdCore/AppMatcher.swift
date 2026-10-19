import Foundation

/// Controls which match strategies `AppMatcher` applies beyond the plain name prefix.
public struct MatchOptions: Equatable, Sendable {
    /// Also match the query against the start of any later word in the name,
    /// so "c" finds "Google Chrome" and "s" finds "System Settings".
    public var wordPrefixes: Bool
    /// Also match the query against the initials of multi-word names,
    /// so "vsc" finds "Visual Studio Code".
    public var initials: Bool
    /// Apps that outrank all other matches, in order. See `PriorityList`.
    public var priority: PriorityList
    /// Apps that rank after all other matches (still switchable), in order. An app on both
    /// lists is treated as prioritised.
    public var deprioritized: PriorityList
    /// Extra names to match apps under. See `AliasList`.
    public var aliases: AliasList

    public init(
        wordPrefixes: Bool = true,
        initials: Bool = true,
        priority: PriorityList = .empty,
        deprioritized: PriorityList = .empty,
        aliases: AliasList = .empty
    ) {
        self.wordPrefixes = wordPrefixes
        self.initials = initials
        self.priority = priority
        self.deprioritized = deprioritized
        self.aliases = aliases
    }
}

/// Where a match sits relative to the user's priority and deprioritized lists.
public enum MatchPlacement: Equatable, Sendable {
    /// On the priority list, at this position (0 = first).
    case prioritized(rank: Int)
    /// On neither list.
    case normal
    /// On the deprioritized list, at this position (0 = first among the deprioritized).
    case deprioritized(rank: Int)

    /// Sort key: prioritised first, then normal, then deprioritised; ranks within a group.
    var order: (Int, Int) {
        switch self {
        case .prioritized(let rank): return (0, rank)
        case .normal: return (1, 0)
        case .deprioritized(let rank): return (2, rank)
        }
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
    public let placement: MatchPlacement
    /// The name the match was made on: the app's own name, an alternate name macOS
    /// has for it, or a user alias. Equal to `candidate.name` for an ordinary match.
    public let matchedName: String

    /// True when the match came through an alternate name or alias rather than the
    /// app's own name.
    public var matchedViaAlias: Bool { matchedName != candidate.name }

    /// Position in the user's priority list, or nil if not prioritised.
    public var priorityRank: Int? {
        if case .prioritized(let rank) = placement { return rank }
        return nil
    }

    /// Position in the user's deprioritized list, or nil if not deprioritised.
    public var deprioritizedRank: Int? {
        if case .deprioritized(let rank) = placement { return rank }
        return nil
    }
}

/// Ranks running applications against the letters typed while the activator key is held.
///
/// Ranking is deterministic so that a given query always lands on the same app. Matches
/// are grouped — the user's priority list first (in list order), then everything else,
/// then the deprioritized list (in list order) — and within a group ordered by better
/// tier, then case-insensitive alphabetical by the app's own name, then by process id.
/// Each app is matched under its own name, its alternate names and any user aliases, and
/// takes the best tier any of them achieves. This is what makes "S always goes to the
/// same app" learnable; the user types more letters to disambiguate.
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
            let placement: MatchPlacement
            let matchedName: String
            let foldedName: String
        }

        var scored: [Scored] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard let best = bestMatch(for: candidate, query: foldedQuery, options: options) else {
                continue
            }
            scored.append(Scored(
                candidate: candidate,
                tier: best.tier,
                placement: placement(of: candidate, options: options),
                matchedName: best.name,
                foldedName: StringNormalization.fold(candidate.name)
            ))
        }

        scored.sort { lhs, rhs in
            let (lGroup, lRank) = lhs.placement.order
            let (rGroup, rRank) = rhs.placement.order
            if lGroup != rGroup { return lGroup < rGroup }
            if lRank != rRank { return lRank < rRank }
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.foldedName != rhs.foldedName { return lhs.foldedName < rhs.foldedName }
            if lhs.candidate.name != rhs.candidate.name { return lhs.candidate.name < rhs.candidate.name }
            return lhs.candidate.id < rhs.candidate.id
        }

        return scored.map {
            RankedMatch(candidate: $0.candidate, tier: $0.tier, placement: $0.placement, matchedName: $0.matchedName)
        }
    }

    /// Convenience: the matching candidates only, best first.
    public static func matches(
        for query: String,
        in candidates: [AppCandidate],
        options: MatchOptions = MatchOptions()
    ) -> [AppCandidate] {
        rankedMatches(for: query, in: candidates, options: options).map(\.candidate)
    }

    /// The best tier across the app's own name, its alternate names and any user aliases,
    /// with the name that achieved it. Ties go to the earliest name, so the app's own name
    /// wins whenever it matches as well as an alias does.
    static func bestMatch(for candidate: AppCandidate, query: String, options: MatchOptions) -> (tier: MatchTier, name: String)? {
        var best: (tier: MatchTier, name: String)?
        for name in candidate.allNames + options.aliases.names(for: candidate) {
            guard let tier = tier(forFoldedName: StringNormalization.fold(name), query: query, options: options) else {
                continue
            }
            if let current = best, tier >= current.tier {
                continue
            }
            best = (tier, name)
            if tier == .namePrefix {
                break   // can't do better
            }
        }
        return best
    }

    /// Priority wins over deprioritisation when an app is on both lists.
    static func placement(of candidate: AppCandidate, options: MatchOptions) -> MatchPlacement {
        if let rank = options.priority.rank(of: candidate) { return .prioritized(rank: rank) }
        if let rank = options.deprioritized.rank(of: candidate) { return .deprioritized(rank: rank) }
        return .normal
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
