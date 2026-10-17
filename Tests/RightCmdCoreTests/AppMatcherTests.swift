import XCTest
@testable import RightCmdCore

final class StringNormalizationTests: XCTestCase {
    func testFoldLowercases() {
        XCTAssertEqual(StringNormalization.fold("SAFARI"), "safari")
    }

    func testFoldStripsDiacritics() {
        XCTAssertEqual(StringNormalization.fold("Éclair"), "eclair")
        XCTAssertEqual(StringNormalization.fold("Ĺubomír"), "lubomir")
        XCTAssertEqual(StringNormalization.fold("naïve café"), "naive cafe")
    }

    func testFoldHandlesPrecomposedAndDecomposedForms() {
        let precomposed = "\u{00E9}"          // é
        let decomposed = "e\u{0301}"          // e + combining acute
        XCTAssertEqual(StringNormalization.fold(precomposed), "e")
        XCTAssertEqual(StringNormalization.fold(decomposed), "e")
    }

    func testFoldLeavesPlainASCIIAlone() {
        XCTAssertEqual(StringNormalization.fold("1password"), "1password")
    }

    func testWordsSplitOnNonAlphanumerics() {
        XCTAssertEqual(StringNormalization.words("visual studio code"), ["visual", "studio", "code"])
        XCTAssertEqual(StringNormalization.words("sequel-ace"), ["sequel", "ace"])
        XCTAssertEqual(StringNormalization.words("iterm2"), ["iterm2"])
        XCTAssertEqual(StringNormalization.words("  spaced   out  "), ["spaced", "out"])
        XCTAssertEqual(StringNormalization.words(""), [])
    }

    func testInitials() {
        XCTAssertEqual(StringNormalization.initials("visual studio code"), "vsc")
        XCTAssertEqual(StringNormalization.initials("safari"), "s")
    }
}

final class AppMatcherTests: XCTestCase {
    private func names(_ query: String, options: MatchOptions = MatchOptions(), in apps: [AppCandidate] = Fixtures.all) -> [String] {
        AppMatcher.matches(for: query, in: apps, options: options).map(\.name)
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertEqual(names(""), [])
        XCTAssertEqual(names("   "), [])
    }

    func testNoCandidatesMatchesNothing() {
        XCTAssertEqual(names("s", in: []), [])
    }

    func testSingleLetterPrefixReturnsAlphabeticalOrder() {
        // "first S-named application": alphabetical among name-prefix matches first,
        // then word-prefix matches ("Visual Studio Code" via "Studio").
        XCTAssertEqual(names("s"), ["Safari", "Sequel Ace", "Slack", "System Settings", "Visual Studio Code"])
        XCTAssertEqual(names("s").first, "Safari")
    }

    func testTwoLetterPrefixNarrowsTheMatch() {
        // "Sequel Ace" by name prefix, "System Settings" by word prefix ("Settings").
        XCTAssertEqual(names("se"), ["Sequel Ace", "System Settings"])
        XCTAssertEqual(names("seq"), ["Sequel Ace"])
        XCTAssertEqual(names("sl"), ["Slack"])
        XCTAssertEqual(names("sy"), ["System Settings"])
    }

    func testMatchingIsCaseInsensitive() {
        // "Sequel Ace" trails via its initials.
        XCTAssertEqual(names("SA"), ["Safari", "Sequel Ace"])
        XCTAssertEqual(names("SAF"), ["Safari"])
        XCTAssertEqual(names("saf"), ["Safari"])
    }

    func testMatchingIsDiacriticInsensitive() {
        XCTAssertEqual(names("ec"), ["Éclair"])
        XCTAssertEqual(names("éc"), ["Éclair"])
    }

    func testDigitsMatch() {
        XCTAssertEqual(names("1p"), ["1Password"])
    }

    func testNamePrefixRanksAboveWordPrefix() {
        // "c" is a name prefix for nothing here, so Chrome (word prefix) and VS Code (word
        // prefix) tie at tier 1 and sort alphabetically.
        XCTAssertEqual(names("c"), ["Google Chrome", "Visual Studio Code"])
        // "x" → Xcode (name prefix) only.
        XCTAssertEqual(names("x"), ["Xcode"])
    }

    func testWordPrefixTierIsBelowNamePrefixTier() {
        // Add an app whose *name* starts with "ch" so it must outrank Chrome's word match.
        let cheese = AppCandidate(id: 900, name: "Cheese", bundleIdentifier: nil)
        XCTAssertEqual(names("ch", in: Fixtures.all + [cheese]), ["Cheese", "Google Chrome"])
    }

    func testInitialsMatchMultiWordNames() {
        XCTAssertEqual(names("vsc"), ["Visual Studio Code"])
        XCTAssertEqual(names("ss"), ["System Settings"])
        XCTAssertEqual(names("gc"), ["Google Chrome"])
    }

    func testInitialsDoNotApplyToSingleWordNames() {
        // "s" initials of "Safari" would be "s" but that's already a name prefix; make
        // sure a single-word name never matches via initials alone.
        let apps = [AppCandidate(id: 1, name: "Finder")]
        XCTAssertEqual(names("f", options: MatchOptions(wordPrefixes: false, initials: true), in: apps), ["Finder"])
        XCTAssertEqual(names("fi", options: MatchOptions(wordPrefixes: false, initials: true), in: apps), ["Finder"])
        XCTAssertEqual(names("fx", options: MatchOptions(wordPrefixes: false, initials: true), in: apps), [])
    }

    func testWordPrefixCanBeDisabled() {
        let options = MatchOptions(wordPrefixes: false, initials: true)
        XCTAssertEqual(names("ch", options: options), [])
    }

    func testInitialsCanBeDisabled() {
        let options = MatchOptions(wordPrefixes: true, initials: false)
        XCTAssertEqual(names("vsc", options: options), [])
    }

    func testTiersAreReported() {
        let ranked = AppMatcher.rankedMatches(for: "c", in: Fixtures.all)
        XCTAssertEqual(ranked.map(\.tier), [.wordPrefix, .wordPrefix])
        let ranked2 = AppMatcher.rankedMatches(for: "gc", in: Fixtures.all)
        XCTAssertEqual(ranked2.map(\.tier), [.initials])
        let ranked3 = AppMatcher.rankedMatches(for: "xc", in: Fixtures.all)
        XCTAssertEqual(ranked3.map(\.tier), [.namePrefix])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertEqual(names("zzz"), [])
        XCTAssertEqual(names("safarix"), [])
    }

    func testOrderingIsStableForIdenticalNames() {
        // Two instances of the same app (e.g. two copies of a tool) order by pid, so the
        // result is deterministic across invocations regardless of input order.
        let a = AppCandidate(id: 5, name: "Terminal")
        let b = AppCandidate(id: 3, name: "Terminal")
        XCTAssertEqual(AppMatcher.matches(for: "t", in: [a, b]).map(\.id), [3, 5])
        XCTAssertEqual(AppMatcher.matches(for: "t", in: [b, a]).map(\.id), [3, 5])
    }

    func testInputOrderDoesNotAffectRanking() {
        let forward = names("s")
        let backward = names("s", in: Fixtures.all.reversed())
        XCTAssertEqual(forward, backward)
    }

    func testQueryWithLeadingWhitespaceIsTrimmed() {
        XCTAssertEqual(names(" saf"), ["Safari"])
    }
}
