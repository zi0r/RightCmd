import Foundation

/// A simple, case-insensitive glob: `*` matches any run of characters and `?` matches
/// exactly one. Used for excluding apps by name or bundle identifier, e.g. `com.apple.*`.
public struct WildcardPattern: Equatable, Sendable {
    public let pattern: String
    private let folded: [Character]

    public init(_ pattern: String) {
        self.pattern = pattern
        self.folded = Array(StringNormalization.fold(pattern))
    }

    public func matches(_ string: String) -> Bool {
        let text = Array(StringNormalization.fold(string))
        return Self.match(pattern: folded, text: text)
    }

    /// Classic iterative wildcard matcher with backtracking to the last `*`.
    private static func match(pattern: [Character], text: [Character]) -> Bool {
        var p = 0
        var t = 0
        var starIndex: Int? = nil
        var starMatch = 0

        while t < text.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1
                t += 1
            } else if p < pattern.count, pattern[p] == "*" {
                starIndex = p
                starMatch = t
                p += 1
            } else if let star = starIndex {
                p = star + 1
                starMatch += 1
                t = starMatch
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" {
            p += 1
        }
        return p == pattern.count
    }
}

/// Decides which running applications are never offered as switch targets.
public struct ExclusionList: Equatable, Sendable {
    public let patterns: [WildcardPattern]

    public init(patterns: [String]) {
        self.patterns = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(WildcardPattern.init)
    }

    public static let empty = ExclusionList(patterns: [])

    /// True if any of the candidate's names or its bundle identifier matches any pattern.
    public func excludes(_ candidate: AppCandidate) -> Bool {
        patterns.contains { $0.matches(candidate) }
    }

    public func filter(_ candidates: [AppCandidate]) -> [AppCandidate] {
        candidates.filter { !excludes($0) }
    }
}
