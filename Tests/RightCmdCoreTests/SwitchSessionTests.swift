import XCTest
@testable import RightCmdCore

final class SwitchSessionTests: XCTestCase {
    private var contextCalls = 0
    private var frontmost: AppCandidate? = Fixtures.finder
    private var secureInput = false
    private var candidates: [AppCandidate] = Fixtures.all

    /// Sessions under test default to `commitOnUniqueMatch = false` so each behaviour can be
    /// exercised in isolation; `CommitOnUniqueMatchTests` covers the auto-commit path.
    private func makeSession(_ configure: (inout Settings) -> Void = { _ in }) -> SwitchSession {
        var settings = Settings()
        settings.commitOnUniqueMatch = false
        configure(&settings)
        return SwitchSession(settings: settings) { [unowned self] in
            self.contextCalls += 1
            return SessionContext(candidates: self.candidates, frontmost: self.frontmost, secureInputActive: self.secureInput)
        }
    }

    private func type(_ text: String, into session: SwitchSession, log: inout ActionLog) {
        for ch in text {
            log.record(session.handle(.key(.character(ch))))
        }
    }

    // MARK: Live mode (default)

    func testLiveModeSwitchesAsYouType() {
        let session = makeSession()
        var log = ActionLog()

        log.record(session.handle(.activatorPressed))
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(log.actions, [], "nothing is shown until the first letter")
        XCTAssertEqual(contextCalls, 1, "candidates are snapshotted once per session")

        type("s", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.safari])
        XCTAssertEqual(log.overlays.last?.query, "s")
        XCTAssertEqual(log.overlays.last?.selected, Fixtures.safari)
        XCTAssertEqual(log.overlays.last?.matches.first, Fixtures.safari)

        type("l", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.safari, Fixtures.slack])
        XCTAssertEqual(log.overlays.last?.query, "sl")

        log.record(session.handle(.activatorReleased))
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(log.actions.last, .hideOverlay)
        XCTAssertEqual(log.hideCount, 1)
        XCTAssertEqual(log.activations.count, 2, "release doesn't activate again in live mode")
    }

    func testTwoLetterPrefixSelectsSecondLetterApp() {
        // The requirement: rcmd-S → first S app, rcmd-SE → an app starting with "SE".
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("se", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.safari, Fixtures.sequel])
        log.record(session.handle(.activatorReleased))
    }

    func testSameSelectionIsNotReactivated() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("saf", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.safari], "s, sa, saf all resolve to Safari; activate once")
        XCTAssertEqual(log.overlays.count, 3, "but the overlay still updates each keystroke")
    }

    func testBackspaceRevisesSelection() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.backspace)))
        XCTAssertEqual(log.activations, [Fixtures.safari, Fixtures.slack, Fixtures.safari])
        XCTAssertEqual(log.overlays.last?.query, "s")
    }

    func testBackspaceToEmptyHidesOverlay() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.key(.backspace)))
        XCTAssertEqual(log.actions.last, .hideOverlay)
        // Releasing afterwards must not hide a second time.
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.hideCount, 1)
    }

    func testBackspaceOnEmptyQueryDoesNothing() {
        let session = makeSession()
        _ = session.handle(.activatorPressed)
        XCTAssertEqual(session.handle(.key(.backspace)), [])
    }

    func testNoMatchShowsOverlayWithoutActivating() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        XCTAssertEqual(log.activations, [])
        XCTAssertEqual(log.overlays.last?.matches, [])
        XCTAssertNil(log.overlays.last?.selectedIndex)
        XCTAssertEqual(log.overlays.last?.query, "zq")
    }

    func testEscapeInLiveModeRestoresOriginalApp() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.escape)))
        XCTAssertEqual(log.activations.last, Fixtures.finder)
        XCTAssertEqual(log.hideCount, 1)
        XCTAssertTrue(session.isActive, "right ⌘ is still held")

        // Keys after Escape are ignored until release.
        XCTAssertEqual(session.handle(.key(.character("x"))), [])
        XCTAssertEqual(session.handle(.activatorReleased), [])
        XCTAssertFalse(session.isActive)
    }

    func testEscapeWithoutAnySwitchDoesNotActivate() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        log.record(session.handle(.key(.escape)))
        XCTAssertEqual(log.activations, [])
    }

    func testEscapeWhenOriginalAppIsTheMatchDoesNotReactivate() {
        frontmost = Fixtures.safari
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.key(.escape)))
        XCTAssertEqual(log.activations, [Fixtures.safari])
    }

    func testConfirmInLiveModeEndsSessionWithoutExtraActivation() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.key(.confirm)))
        XCTAssertEqual(log.activations, [Fixtures.safari])
        XCTAssertEqual(log.actions.last, .hideOverlay)
        XCTAssertEqual(session.handle(.key(.character("l"))), [])
        _ = session.handle(.activatorReleased)
    }

    func testCyclingWithNextAndPrevious() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        // Matches: Safari, Sequel Ace, Slack, System Settings, Visual Studio Code
        log.record(session.handle(.key(.next)))
        XCTAssertEqual(log.activations.last, Fixtures.sequel)
        XCTAssertEqual(log.overlays.last?.selectedIndex, 1)
        log.record(session.handle(.key(.next)))
        XCTAssertEqual(log.activations.last, Fixtures.slack)
        log.record(session.handle(.key(.previous)))
        XCTAssertEqual(log.activations.last, Fixtures.sequel)
        log.record(session.handle(.key(.previous)))
        log.record(session.handle(.key(.previous)))
        XCTAssertEqual(log.activations.last, Fixtures.vscode, "previous wraps around")
        XCTAssertEqual(log.overlays.last?.selectedIndex, 4)
    }

    func testCyclingWithSingleMatchDoesNothing() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(session.handle(.key(.next)), [])
        XCTAssertEqual(session.handle(.key(.previous)), [])
    }

    func testCyclingWithNoMatchDoesNothing() {
        let session = makeSession()
        _ = session.handle(.activatorPressed)
        _ = session.handle(.key(.character("z")))
        XCTAssertEqual(session.handle(.key(.next)), [])
    }

    func testTypingAfterCyclingResetsSelectionToBest() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.key(.next)))        // Sequel Ace
        type("l", into: session, log: &log)             // "sl" → Slack
        XCTAssertEqual(log.activations.last, Fixtures.slack)
        XCTAssertEqual(log.overlays.last?.selectedIndex, 0)
    }

    func testIgnoredKeysProduceNoActions() {
        let session = makeSession()
        _ = session.handle(.activatorPressed)
        XCTAssertEqual(session.handle(.key(.ignored)), [])
    }

    // MARK: On-release mode

    func testOnReleaseModeActivatesOnlyWhenReleased() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("se", into: session, log: &log)
        XCTAssertEqual(log.activations, [], "no switching while typing")
        XCTAssertEqual(log.overlays.map(\.query), ["s", "se"])

        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.sequel])
        XCTAssertEqual(log.actions.last, .hideOverlay)
        XCTAssertEqual(log.actions.dropLast().last, .activate(Fixtures.sequel), "activate before hiding")
    }

    func testOnReleaseModeConfirmActivatesImmediately() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.confirm)))
        XCTAssertEqual(log.activations, [Fixtures.slack])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.slack], "release after confirm must not activate twice")
        XCTAssertEqual(log.hideCount, 1)
    }

    func testOnReleaseModeEscapeCancels() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.escape)))
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [])
        XCTAssertEqual(log.hideCount, 1)
    }

    func testOnReleaseModeReleaseWithNoMatchActivatesNothing() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [])
    }

    func testOnReleaseModeCyclingUpdatesSelectionOnly() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.key(.next)))
        XCTAssertEqual(log.activations, [])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.sequel])
    }

    // MARK: Options

    func testSkipFrontmostAppPrefersAnotherMatch() {
        frontmost = Fixtures.safari
        let session = makeSession { $0.skipFrontmostApp = true }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.sequel])
        XCTAssertEqual(log.overlays.last?.selectedIndex, 1)
    }

    func testSkipFrontmostAppFallsBackWhenItIsTheOnlyMatch() {
        frontmost = Fixtures.xcode
        let session = makeSession { $0.skipFrontmostApp = true }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.xcode])
    }

    func testSkipFrontmostDisabledByDefaultActivatesFrontmost() {
        frontmost = Fixtures.safari
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.safari])
    }

    func testOverlayCanBeDisabled() {
        let session = makeSession { $0.showOverlay = false }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.overlays, [])
        XCTAssertEqual(log.hideCount, 0)
        XCTAssertEqual(log.activations, [Fixtures.safari, Fixtures.slack])
    }

    func testMatchOptionsFromSettingsAreUsed() {
        let session = makeSession { $0.matchWordPrefixes = false; $0.matchInitials = false }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("c", into: session, log: &log)
        XCTAssertEqual(log.activations, [], "Chrome only matches by word prefix")
    }

    func testSettingsCanBeReplacedBetweenSessions() {
        let session = makeSession()
        session.settings.switchMode = .onRelease
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(log.activations, [])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.safari])
    }

    // MARK: Robustness

    func testSecureInputShowsOverlayImmediately() {
        secureInput = true
        let session = makeSession()
        let actions = session.handle(.activatorPressed)
        XCTAssertEqual(actions.count, 1)
        guard case .showOverlay(let state)? = actions.first else {
            return XCTFail("expected overlay")
        }
        XCTAssertTrue(state.secureInputActive)
        XCTAssertEqual(state.query, "")
        XCTAssertEqual(session.handle(.activatorReleased), [.hideOverlay])
    }

    func testKeysWhileIdleAreIgnored() {
        let session = makeSession()
        XCTAssertEqual(session.handle(.key(.character("s"))), [])
        XCTAssertEqual(session.handle(.key(.escape)), [])
        XCTAssertEqual(session.handle(.activatorReleased), [])
        XCTAssertEqual(contextCalls, 0)
    }

    func testRepeatedPressWhileActiveIsIgnored() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(session.handle(.activatorPressed), [])
        XCTAssertEqual(contextCalls, 1)
        XCTAssertEqual(session.currentQuery, "s", "the query survives a spurious press")
    }

    func testInterruptedResetsEverything() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(session.handle(.interrupted), [.hideOverlay])
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.currentQuery, "")
        XCTAssertEqual(session.handle(.activatorReleased), [], "a stray release after interruption is harmless")
    }

    func testInterruptedWhileIdleIsHarmless() {
        let session = makeSession()
        XCTAssertEqual(session.handle(.interrupted), [])
    }

    func testCandidatesAreSnapshottedPerSession() {
        let session = makeSession()
        _ = session.handle(.activatorPressed)
        candidates = []  // an app quits mid-session; the snapshot is unaffected
        let actions = session.handle(.key(.character("x")))
        XCTAssertTrue(actions.contains(.activate(Fixtures.xcode)))
        _ = session.handle(.activatorReleased)

        _ = session.handle(.activatorPressed)
        XCTAssertEqual(session.handle(.key(.character("x"))).contains(.activate(Fixtures.xcode)), false)
        XCTAssertEqual(contextCalls, 2)
    }

    func testCurrentMatchesAndAcceptingKeysReflectState() {
        let session = makeSession()
        XCTAssertFalse(session.isAcceptingKeys)
        XCTAssertEqual(session.currentMatches, [])

        _ = session.handle(.activatorPressed)
        XCTAssertTrue(session.isAcceptingKeys)
        _ = session.handle(.key(.character("s")))
        XCTAssertEqual(session.currentMatches.first, Fixtures.safari)
        _ = session.handle(.key(.character("z")))
        XCTAssertEqual(session.currentMatches, [], "no match is observable even with the overlay off")

        _ = session.handle(.key(.escape))
        XCTAssertFalse(session.isAcceptingKeys, "finished: keys are no longer interpreted")

        _ = session.handle(.activatorReleased)
        XCTAssertFalse(session.isAcceptingKeys)
        XCTAssertEqual(session.currentMatches, [], "state is cleared on release")
        XCTAssertEqual(session.currentQuery, "")
    }

    func testOverlayStateSelectedHelper() {
        let state = OverlayState(query: "s", matches: [Fixtures.safari, Fixtures.slack], selectedIndex: 1, secureInputActive: false)
        XCTAssertEqual(state.selected, Fixtures.slack)
        XCTAssertNil(OverlayState(query: "", matches: [], selectedIndex: nil, secureInputActive: false).selected)
        XCTAssertNil(OverlayState(query: "s", matches: [Fixtures.safari], selectedIndex: 5, secureInputActive: false).selected)
    }
}

final class CommitOnUniqueMatchTests: XCTestCase {
    private var candidates = Fixtures.all
    private var frontmost: AppCandidate? = Fixtures.finder

    private func makeSession(_ configure: (inout Settings) -> Void = { _ in }) -> SwitchSession {
        var settings = Settings()
        settings.commitOnUniqueMatch = true
        configure(&settings)
        return SwitchSession(settings: settings) { [unowned self] in
            SessionContext(candidates: self.candidates, frontmost: self.frontmost)
        }
    }

    private func type(_ text: String, into session: SwitchSession, log: inout ActionLog) {
        for ch in text {
            log.record(session.handle(.key(.character(ch))))
        }
    }

    func testUniqueFirstLetterCommitsImmediatelyInLiveMode() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(log.actions, [.activate(Fixtures.xcode)], "no overlay: the decision is made on the first key")
        XCTAssertTrue(session.isActive, "right ⌘ is still held")

        // Further keys are ignored; a release is quiet.
        XCTAssertEqual(session.handle(.key(.character("c"))), [])
        XCTAssertEqual(session.handle(.key(.backspace)), [])
        XCTAssertEqual(session.handle(.activatorReleased), [])
        XCTAssertFalse(session.isActive)
    }

    func testUniqueMatchCommitsImmediatelyInOnReleaseMode() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        XCTAssertEqual(log.overlays.map(\.query), ["s"], "the overlay shows while ambiguous")
        XCTAssertEqual(Array(log.actions.suffix(2)), [.activate(Fixtures.slack), .hideOverlay])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.slack], "release must not activate a second time")
        XCTAssertEqual(log.hideCount, 1)
    }

    func testAmbiguousQueryKeepsMatching() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        XCTAssertEqual(log.activations, [])
        XCTAssertEqual(log.overlays.last?.matches.count, 5)
        type("y", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.systemSettings])
    }

    func testNoMatchDoesNotCommit() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        XCTAssertEqual(log.activations, [])
        XCTAssertEqual(log.overlays.last?.matches, [])
    }

    func testBackspaceAfterNoMatchResumesMatching() {
        let session = makeSession { $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("se", into: session, log: &log)             // Sequel Ace, System Settings
        type("x", into: session, log: &log)              // no match
        XCTAssertEqual(log.activations, [])
        log.record(session.handle(.key(.backspace)))     // back to "se": still 2
        XCTAssertEqual(log.activations, [])
        type("q", into: session, log: &log)              // "seq" → unique
        XCTAssertEqual(log.activations, [Fixtures.sequel])
    }

    func testCommitRespectsSkipFrontmostAppOnlyWhenAmbiguous() {
        // A unique match is committed even if it's the frontmost app: there is nothing
        // else to prefer.
        frontmost = Fixtures.xcode
        let session = makeSession { $0.skipFrontmostApp = true }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(log.activations, [Fixtures.xcode])
    }

    func testEscapeAfterCommitIsIgnored() {
        // The session is finished; Escape cannot "undo" a committed switch because the
        // user already got what they typed for.
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(session.handle(.key(.escape)), [])
        XCTAssertEqual(log.activations, [Fixtures.xcode])
    }

    func testDisabledSettingKeepsOldBehaviour() {
        let session = makeSession { $0.commitOnUniqueMatch = false; $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        XCTAssertEqual(log.activations, [], "waits for release")
        XCTAssertEqual(log.overlays.last?.matches, [Fixtures.xcode])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.xcode])
    }

    func testOverlayDisabledStillCommits() {
        let session = makeSession { $0.showOverlay = false; $0.switchMode = .onRelease }
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        XCTAssertEqual(log.actions, [.activate(Fixtures.slack)])
    }
}

final class MovePointerTests: XCTestCase {
    private func makeSession(mode: SwitchMode = .live, commit: Bool = false, on: Bool = true) -> SwitchSession {
        var settings = Settings()
        settings.switchMode = mode
        settings.commitOnUniqueMatch = commit
        settings.movePointerToWindow = on
        return SwitchSession(settings: settings) {
            SessionContext(candidates: Fixtures.all, frontmost: Fixtures.finder)
        }
    }

    private func type(_ text: String, into session: SwitchSession, log: inout ActionLog) {
        for ch in text { log.record(session.handle(.key(.character(ch)))) }
    }

    private func pointerMoves(_ log: ActionLog) -> [AppCandidate] {
        log.actions.compactMap {
            if case .movePointer(let app) = $0 { return app }
            return nil
        }
    }

    func testOffByDefaultEmitsNothing() {
        let session = makeSession(on: false)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [])
    }

    func testLiveModeMovesOnceToTheFinalAppOnRelease() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        XCTAssertEqual(pointerMoves(log), [], "not while still typing")
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [Fixtures.slack])
        XCTAssertEqual(log.actions.last, .movePointer(to: Fixtures.slack), "after the overlay is hidden")
    }

    func testOnReleaseModeMovesAfterActivating() {
        let session = makeSession(mode: .onRelease)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("x", into: session, log: &log)
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations, [Fixtures.xcode])
        XCTAssertEqual(pointerMoves(log), [Fixtures.xcode])
        let activateIndex = log.actions.firstIndex(of: .activate(Fixtures.xcode))!
        let moveIndex = log.actions.firstIndex(of: .movePointer(to: Fixtures.xcode))!
        XCTAssertLessThan(activateIndex, moveIndex)
    }

    func testUniqueCommitMovesAtTheCommitNotOnRelease() {
        for mode in SwitchMode.allCases {
            let session = makeSession(mode: mode, commit: true)
            var log = ActionLog()
            log.record(session.handle(.activatorPressed))
            type("x", into: session, log: &log)
            XCTAssertEqual(log.activations, [Fixtures.xcode], "\(mode)")
            XCTAssertEqual(pointerMoves(log), [Fixtures.xcode], "\(mode): the outcome is final at the commit")
            XCTAssertEqual(log.actions.last, .movePointer(to: Fixtures.xcode), "\(mode): after activate and hide")
            log.record(session.handle(.activatorReleased))
            XCTAssertEqual(pointerMoves(log), [Fixtures.xcode], "\(mode): release must not move again")
        }
    }

    func testReturnMovesImmediatelyInOnReleaseMode() {
        let session = makeSession(mode: .onRelease)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.confirm)))
        XCTAssertEqual(log.activations, [Fixtures.slack])
        XCTAssertEqual(pointerMoves(log), [Fixtures.slack])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [Fixtures.slack], "once only")
    }

    func testReturnMovesImmediatelyInLiveMode() {
        let session = makeSession(mode: .live)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.confirm)))
        XCTAssertEqual(pointerMoves(log), [Fixtures.slack])
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [Fixtures.slack])
    }

    func testReturnWithNoMatchDoesNotMove() {
        let session = makeSession(mode: .onRelease)
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        log.record(session.handle(.key(.confirm)))
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [])
    }

    func testEscapeSuppressesTheMove() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("sl", into: session, log: &log)
        log.record(session.handle(.key(.escape)))
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(log.activations.last, Fixtures.finder, "live mode restores the original app")
        XCTAssertEqual(pointerMoves(log), [], "but a cancelled hold never moves the pointer")
    }

    func testNoSwitchMeansNoMove() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("zq", into: session, log: &log)
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [])

        log.record(session.handle(.activatorPressed))
        log.record(session.handle(.activatorReleased))
        XCTAssertEqual(pointerMoves(log), [], "press and release with nothing typed")
    }

    func testInterruptedSessionDoesNotMove() {
        let session = makeSession()
        var log = ActionLog()
        log.record(session.handle(.activatorPressed))
        type("s", into: session, log: &log)
        log.record(session.handle(.interrupted))
        XCTAssertEqual(pointerMoves(log), [])
    }
}
