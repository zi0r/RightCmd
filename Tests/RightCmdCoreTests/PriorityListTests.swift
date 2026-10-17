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
