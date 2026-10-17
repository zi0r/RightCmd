import XCTest
@testable import RightCmdCore

final class PriorityListTests: XCTestCase {
    func testRankIsListPosition() {
        let list = PriorityList(patterns: ["Slack", "com.google.*", "Xcode"])
        XCTAssertEqual(list.rank(of: Fixtures.slack), 0)
        XCTAssertEqual(list.rank(of: Fixtures.chrome), 1)
        XCTAssertEqual(list.rank(of: Fixtures.xcode), 2)
        XCTAssertNil(list.rank(of: Fixtures.safari))
    }

    func testFirstMatchingPatternWins() {
        let list = PriorityList(patterns: ["com.apple.*", "Safari"])
        XCTAssertEqual(list.rank(of: Fixtures.safari), 0, "the broader pattern comes first in the list")
    }

    func testBlankEntriesAreDroppedWithoutShiftingRanks() {
        let list = PriorityList(patterns: ["", "Slack", "  ", "Xcode"])
        XCTAssertEqual(list.patterns.count, 2)
        XCTAssertEqual(list.rank(of: Fixtures.slack), 0)
        XCTAssertEqual(list.rank(of: Fixtures.xcode), 1)
    }

    func testEmpty() {
        XCTAssertTrue(PriorityList.empty.isEmpty)
        XCTAssertNil(PriorityList.empty.rank(of: Fixtures.slack))
    }
}

final class AppMatcherPriorityTests: XCTestCase {
    private func names(_ query: String, priority: [String], in apps: [AppCandidate] = Fixtures.all) -> [String] {
        let options = MatchOptions(priority: PriorityList(patterns: priority))
        return AppMatcher.matches(for: query, in: apps, options: options).map(\.name)
    }

    func testPrioritisedAppMovesToTheFront() {
        XCTAssertEqual(names("s", priority: []).first, "Safari")
        XCTAssertEqual(names("s", priority: ["Slack"]).first, "Slack")
        XCTAssertEqual(names("s", priority: ["Slack"]), ["Slack", "Safari", "Sequel Ace", "System Settings", "Visual Studio Code"])
    }

    func testPriorityOrderIsTheListOrder() {
        XCTAssertEqual(names("s", priority: ["System Settings", "Slack"]).prefix(2), ["System Settings", "Slack"])
        XCTAssertEqual(names("s", priority: ["Slack", "System Settings"]).prefix(2), ["Slack", "System Settings"])
    }

    func testPriorityOutranksMatchTier() {
        // Chrome only matches "ch" by word prefix; Cheese matches by name prefix.
        let cheese = AppCandidate(id: 900, name: "Cheese")
        let apps = Fixtures.all + [cheese]
        XCTAssertEqual(names("ch", priority: [], in: apps), ["Cheese", "Google Chrome"])
        XCTAssertEqual(names("ch", priority: ["Google Chrome"], in: apps), ["Google Chrome", "Cheese"])
    }

    func testPriorityNeverAddsNonMatchingApps() {
        XCTAssertEqual(names("x", priority: ["Slack", "Google Chrome"]), ["Xcode"])
        XCTAssertEqual(names("zz", priority: ["Slack"]), [])
    }

    func testWildcardPatternSharesRankThenFallsBackToNormalOrder() {
        // "com.apple.*" matches Safari and System Settings; among them normal order applies.
        XCTAssertEqual(names("s", priority: ["com.apple.*"]).prefix(2), ["Safari", "System Settings"])
    }

    func testUnprioritisedAppsKeepTheirOrder() {
        let withPriority = names("s", priority: ["Slack"]).dropFirst()
        let without = names("s", priority: []).filter { $0 != "Slack" }
        XCTAssertEqual(Array(withPriority), without)
    }

    func testRankedMatchReportsPriority() {
        let options = MatchOptions(priority: PriorityList(patterns: ["Slack"]))
        let ranked = AppMatcher.rankedMatches(for: "s", in: Fixtures.all, options: options)
        XCTAssertEqual(ranked.first?.priorityRank, 0)
        XCTAssertNil(ranked.last?.priorityRank)
    }

    func testBundleIdentifierPatterns() {
        XCTAssertEqual(names("s", priority: ["com.tinyspeck.slackmacgap"]).first, "Slack")
    }
}

final class SwitchSessionPriorityTests: XCTestCase {
    private func makeSession(priority: [String], mode: SwitchMode = .live) -> SwitchSession {
        var settings = Settings()
        settings.commitOnUniqueMatch = false
        settings.priorityPatterns = priority
        settings.switchMode = mode
        return SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all, frontmost: Fixtures.finder)
        }
    }

    func testSessionUsesPriorityFromSettings() {
        let session = makeSession(priority: ["Slack"])
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        log.record(session.handle(.key(.character("s"))))
        XCTAssertEqual(log.activations, [Fixtures.slack])
        XCTAssertEqual(log.overlays.last?.matches.first, Fixtures.slack)
    }

    func testOverlayMarksPrioritisedMatches() {
        let session = makeSession(priority: ["Slack", "Safari"], mode: .onRelease)
        _ = session.handle(.activatorPressed)
        let actions = session.handle(.key(.character("s")))
        guard case .showOverlay(let state)? = actions.first else { return XCTFail("expected overlay") }
        XCTAssertEqual(state.prioritizedIDs, [Fixtures.slack.id, Fixtures.safari.id])
        XCTAssertEqual(state.matches.prefix(2), [Fixtures.slack, Fixtures.safari])
    }

    func testPriorityCombinesWithSkipFrontmost() {
        var settings = Settings()
        settings.commitOnUniqueMatch = false
        settings.skipFrontmostApp = true
        settings.priorityPatterns = ["Slack"]
        let session = SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all, frontmost: Fixtures.slack)
        }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        log.record(session.handle(.key(.character("s"))))
        XCTAssertEqual(log.activations, [Fixtures.safari], "Slack is top but already in front, so the next match wins")
    }
}

final class AppMatcherDeprioritizeTests: XCTestCase {
    private func names(_ query: String, priority: [String] = [], deprioritized: [String], in apps: [AppCandidate] = Fixtures.all) -> [String] {
        let options = MatchOptions(
            priority: PriorityList(patterns: priority),
            deprioritized: PriorityList(patterns: deprioritized)
        )
        return AppMatcher.matches(for: query, in: apps, options: options).map(\.name)
    }

    func testDeprioritisedAppMovesToTheEnd() {
        XCTAssertEqual(names("s", deprioritized: []).first, "Safari")
        XCTAssertEqual(names("s", deprioritized: ["Safari"]).last, "Safari")
        XCTAssertEqual(names("s", deprioritized: ["Safari"]), ["Sequel Ace", "Slack", "System Settings", "Visual Studio Code", "Safari"])
    }

    func testDeprioritisedAppIsStillAMatch() {
        XCTAssertEqual(names("saf", deprioritized: ["Safari"]), ["Safari"], "alone, it still wins: it is switchable")
        XCTAssertEqual(names("x", deprioritized: ["Xcode"]), ["Xcode"])
    }

    func testDeprioritisedOrderIsTheListOrder() {
        XCTAssertEqual(names("s", deprioritized: ["Slack", "Safari"]).suffix(2), ["Slack", "Safari"])
        XCTAssertEqual(names("s", deprioritized: ["Safari", "Slack"]).suffix(2), ["Safari", "Slack"])
    }

    func testDeprioritisationOutranksMatchTier() {
        // Cheese is a better textual match for "ch" than Chrome, but is deprioritised.
        let cheese = AppCandidate(id: 900, name: "Cheese")
        let apps = Fixtures.all + [cheese]
        XCTAssertEqual(names("ch", deprioritized: [], in: apps), ["Cheese", "Google Chrome"])
        XCTAssertEqual(names("ch", deprioritized: ["Cheese"], in: apps), ["Google Chrome", "Cheese"])
    }

    func testPriorityWinsWhenOnBothLists() {
        XCTAssertEqual(names("s", priority: ["Slack"], deprioritized: ["Slack"]).first, "Slack")
    }

    func testAllThreeGroupsOrderCorrectly() {
        let result = names("s", priority: ["System Settings"], deprioritized: ["Safari"])
        XCTAssertEqual(result.first, "System Settings")
        XCTAssertEqual(result.last, "Safari")
        XCTAssertEqual(result, ["System Settings", "Sequel Ace", "Slack", "Visual Studio Code", "Safari"])
    }

    func testWildcardDeprioritisation() {
        // Everything from Apple goes last; among them, normal order.
        let result = names("s", deprioritized: ["com.apple.*"])
        XCTAssertEqual(result.suffix(2), ["Safari", "System Settings"])
        XCTAssertEqual(result.prefix(3), ["Sequel Ace", "Slack", "Visual Studio Code"])
    }

    func testRankedMatchReportsPlacement() {
        let options = MatchOptions(priority: PriorityList(patterns: ["Slack"]), deprioritized: PriorityList(patterns: ["Safari"]))
        let ranked = AppMatcher.rankedMatches(for: "s", in: Fixtures.all, options: options)
        XCTAssertEqual(ranked.first?.placement, .prioritized(rank: 0))
        XCTAssertEqual(ranked.first?.priorityRank, 0)
        XCTAssertNil(ranked.first?.deprioritizedRank)
        XCTAssertEqual(ranked.last?.placement, .deprioritized(rank: 0))
        XCTAssertEqual(ranked.last?.deprioritizedRank, 0)
        XCTAssertNil(ranked.last?.priorityRank)
        XCTAssertEqual(ranked[1].placement, .normal)
    }
}

final class SwitchSessionDeprioritizeTests: XCTestCase {
    private func makeSession(deprioritized: [String], commit: Bool = false) -> SwitchSession {
        var settings = Settings()
        settings.commitOnUniqueMatch = commit
        settings.deprioritizedPatterns = deprioritized
        return SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all, frontmost: Fixtures.finder)
        }
    }

    func testSessionUsesDeprioritisationFromSettings() {
        let session = makeSession(deprioritized: ["Safari"])
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        log.record(session.handle(.key(.character("s"))))
        XCTAssertEqual(log.activations, [Fixtures.sequel], "Safari no longer wins \"s\"")
        XCTAssertEqual(log.overlays.last?.matches.last, Fixtures.safari)
    }

    func testDeprioritisedUniqueMatchStillCommits() {
        let session = makeSession(deprioritized: ["Xcode"], commit: true)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        log.record(session.handle(.key(.character("x"))))
        XCTAssertEqual(log.activations, [Fixtures.xcode])
    }

    func testOverlayMarksDeprioritisedMatches() {
        let session = makeSession(deprioritized: ["Safari", "Slack"])
        _ = session.handle(.activatorPressed)
        let actions = session.handle(.key(.character("s")))
        guard case .showOverlay(let state)? = actions.first else { return XCTFail("expected overlay") }
        XCTAssertEqual(state.deprioritizedIDs, [Fixtures.safari.id, Fixtures.slack.id])
        XCTAssertEqual(state.prioritizedIDs, [])
        XCTAssertEqual(state.matches.suffix(2), [Fixtures.safari, Fixtures.slack])
    }
}
