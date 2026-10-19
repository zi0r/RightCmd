import XCTest
@testable import RightCmdCore

final class AppCandidateNamesTests: XCTestCase {
    func testAlternateNamesAreDedupedAgainstThePrimaryName() {
        let app = AppCandidate(id: 1, name: "Windows App", bundleIdentifier: "com.microsoft.rdc.macos",
                               alternateNames: ["windows app", " Microsoft Remote Desktop ", "", "Microsoft Remote Desktop"])
        XCTAssertEqual(app.alternateNames, ["Microsoft Remote Desktop"])
        XCTAssertEqual(app.allNames, ["Windows App", "Microsoft Remote Desktop"])
    }

    func testNoAlternates() {
        XCTAssertEqual(Fixtures.safari.allNames, ["Safari"])
    }
}

final class AliasListTests: XCTestCase {
    private let windowsApp = AppCandidate(id: 500, name: "Windows App", bundleIdentifier: "com.microsoft.rdc.macos")

    func testAliasesByBundleIdentifier() {
        let list = AliasList([AppAlias(pattern: "com.microsoft.rdc.macos", names: ["Microsoft Remote Desktop", "RDP"])])
        XCTAssertEqual(list.names(for: windowsApp), ["Microsoft Remote Desktop", "RDP"])
        XCTAssertEqual(list.names(for: Fixtures.safari), [])
    }

    func testAliasesByNameAndWildcard() {
        let list = AliasList([
            AppAlias(pattern: "Windows App", names: ["Remote Desktop"]),
            AppAlias(pattern: "com.microsoft.*", names: ["MS"]),
        ])
        XCTAssertEqual(list.names(for: windowsApp), ["Remote Desktop", "MS"], "all matching entries apply, in order")
    }

    func testBlankEntriesAreDropped() {
        let list = AliasList([
            AppAlias(pattern: "", names: ["x"]),
            AppAlias(pattern: "Safari", names: ["", "  "]),
            AppAlias(pattern: "Safari", names: [" Browser "]),
        ])
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.names(for: Fixtures.safari), ["Browser"])
    }

    func testPatternsAlsoMatchAlternateNames() {
        let app = AppCandidate(id: 1, name: "Windows App", alternateNames: ["Microsoft Remote Desktop"])
        XCTAssertTrue(WildcardPattern("Microsoft*").matches(app))
        XCTAssertTrue(ExclusionList(patterns: ["Microsoft Remote Desktop"]).excludes(app))
        XCTAssertEqual(PriorityList(patterns: ["Microsoft Remote*"]).rank(of: app), 0)
    }
}

final class AppMatcherAliasTests: XCTestCase {
    private let windowsApp = AppCandidate(id: 500, name: "Windows App", bundleIdentifier: "com.microsoft.rdc.macos")
    private var apps: [AppCandidate] { Fixtures.all + [windowsApp] }

    private func ranked(_ query: String, aliases: [AppAlias] = [], in candidates: [AppCandidate]? = nil) -> [RankedMatch] {
        AppMatcher.rankedMatches(for: query, in: candidates ?? apps, options: MatchOptions(aliases: AliasList(aliases)))
    }

    func testWithoutAliasTheOldNameFindsNothing() {
        XCTAssertEqual(ranked("mic").map(\.candidate.name), [])
        XCTAssertEqual(ranked("win").map(\.candidate.name), ["Windows App"])
    }

    func testAliasMakesTheAppMatch() {
        let alias = AppAlias(pattern: "com.microsoft.rdc.macos", names: ["Microsoft Remote Desktop"])
        let result = ranked("mic", aliases: [alias])
        XCTAssertEqual(result.map(\.candidate.name), ["Windows App"])
        XCTAssertEqual(result.first?.matchedName, "Microsoft Remote Desktop")
        XCTAssertTrue(result.first?.matchedViaAlias ?? false)
        XCTAssertEqual(result.first?.tier, .namePrefix)
    }

    func testAliasWordPrefixAndInitialsApply() {
        let alias = AppAlias(pattern: "Windows App", names: ["Microsoft Remote Desktop"])
        XCTAssertEqual(ranked("rem", aliases: [alias]).first?.tier, .wordPrefix)
        XCTAssertEqual(ranked("mrd", aliases: [alias]).first?.tier, .initials)
    }

    func testOwnNameWinsTiesForMatchedName() {
        // "w" matches both "Windows App" (own) and alias "Workstation" at name-prefix tier.
        let alias = AppAlias(pattern: "Windows App", names: ["Workstation"])
        let result = ranked("w", aliases: [alias])
        XCTAssertEqual(result.first?.matchedName, "Windows App")
        XCTAssertFalse(result.first?.matchedViaAlias ?? true)
    }

    func testAliasCanImproveTheTier() {
        // "app" matches "Windows App" only by word prefix; alias "Apps Everywhere" by name prefix.
        let alias = AppAlias(pattern: "Windows App", names: ["Apps Everywhere"])
        XCTAssertEqual(ranked("app").first?.tier, .wordPrefix)
        XCTAssertEqual(ranked("app", aliases: [alias]).first?.tier, .namePrefix)
        XCTAssertEqual(ranked("app", aliases: [alias]).first?.matchedName, "Apps Everywhere")
    }

    func testAlternateNamesMatchLikeAliases() {
        let localized = AppCandidate(id: 600, name: "Réglages Système", bundleIdentifier: "com.apple.systempreferences", alternateNames: ["System Settings"])
        let result = ranked("sys", in: [localized])
        XCTAssertEqual(result.map(\.candidate.id), [600])
        XCTAssertEqual(result.first?.matchedName, "System Settings")
    }

    func testAliasesNeverAddNonMatchingApps() {
        let alias = AppAlias(pattern: "com.microsoft.rdc.macos", names: ["Microsoft Remote Desktop"])
        XCTAssertEqual(ranked("zq", aliases: [alias]), [])
        XCTAssertEqual(ranked("saf", aliases: [alias]).map(\.candidate.name), ["Safari"])
    }

    func testAliasMatchesSortWithEverythingElse() {
        // Alias "Slim" puts Windows App among the S matches, alphabetised by its own name.
        let alias = AppAlias(pattern: "Windows App", names: ["Slim"])
        let names = ranked("s", aliases: [alias]).map(\.candidate.name)
        XCTAssertEqual(names, ["Safari", "Sequel Ace", "Slack", "System Settings", "Windows App", "Visual Studio Code"])
    }
}

final class SwitchSessionAliasTests: XCTestCase {
    func testOverlayReportsTheMatchedAlias() {
        var settings = Settings()
        settings.commitOnUniqueMatch = false
        settings.appAliases = [AppAlias(pattern: "com.microsoft.rdc.macos", names: ["Microsoft Remote Desktop"])]
        let windowsApp = AppCandidate(id: 500, name: "Windows App", bundleIdentifier: "com.microsoft.rdc.macos")
        let session = SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all + [windowsApp], frontmost: Fixtures.finder)
        }
        _ = session.handle(.activatorPressed)
        let actions = session.handle(.key(.character("m")))
        guard case .showOverlay(let state)? = actions.first else { return XCTFail("expected overlay") }
        XCTAssertEqual(state.matches.map(\.id), [500])
        XCTAssertEqual(state.matchedAliases, [500: "Microsoft Remote Desktop"])
        XCTAssertTrue(actions.contains(.activate(windowsApp)))
    }

    func testOverlayHasNoAliasEntryForOrdinaryMatches() {
        var settings = Settings()
        settings.commitOnUniqueMatch = false
        let session = SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all, frontmost: Fixtures.finder)
        }
        _ = session.handle(.activatorPressed)
        let actions = session.handle(.key(.character("s")))
        guard case .showOverlay(let state)? = actions.first else { return XCTFail("expected overlay") }
        XCTAssertEqual(state.matchedAliases, [:])
    }
}
