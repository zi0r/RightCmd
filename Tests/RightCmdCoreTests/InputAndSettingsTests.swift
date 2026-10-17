import XCTest
@testable import RightCmdCore

final class KeyClassifierTests: XCTestCase {
    func testLettersAndDigitsAreCharacters() {
        XCTAssertEqual(KeyClassifier.classify(keyCode: 1, character: "s"), .character("s"))
        XCTAssertEqual(KeyClassifier.classify(keyCode: 18, character: "1"), .character("1"))
        XCTAssertEqual(KeyClassifier.classify(keyCode: 0, character: "ä"), .character("ä"))
    }

    func testPunctuationIsTypable() {
        XCTAssertEqual(KeyClassifier.classify(keyCode: 27, character: "-"), .character("-"))
        XCTAssertEqual(KeyClassifier.classify(keyCode: 47, character: "."), .character("."))
    }

    func testSpecialKeys() {
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.delete, character: "\u{8}"), .backspace)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.forwardDelete, character: nil), .backspace)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.escape, character: "\u{1B}"), .escape)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.returnKey, character: "\r"), .confirm)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.keypadEnter, character: "\u{3}"), .confirm)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.downArrow, character: nil), .next)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.rightArrow, character: nil), .next)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.upArrow, character: nil), .previous)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.leftArrow, character: nil), .previous)
    }

    func testSpaceAndTabAreIgnored() {
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.space, character: " "), .ignored)
        XCTAssertEqual(KeyClassifier.classify(keyCode: KeyCode.tab, character: "\t"), .ignored)
    }

    func testUntranslatableKeysAreIgnored() {
        XCTAssertEqual(KeyClassifier.classify(keyCode: 122, character: nil), .ignored)   // F1
        XCTAssertEqual(KeyClassifier.classify(keyCode: 99, character: "\u{10}"), .ignored) // control char
        XCTAssertEqual(KeyClassifier.classify(keyCode: 99, character: "\n"), .ignored)
    }
}

final class ActivatorKeyTests: XCTestCase {
    private let rightCmd = KeyCode.rightCommand
    private let leftCmd = KeyCode.command

    func testRightCommandDownWithDeviceBit() {
        let flags: ModifierFlags = [.command, .rightCommandDevice]
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: flags), .pressed)
    }

    func testRightCommandUpClearsCommandFlag() {
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: []), .released)
    }

    func testRightCommandUpWhileLeftStillHeld() {
        let flags: ModifierFlags = [.command, .leftCommandDevice]
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: flags), .released)
    }

    func testBothCommandsHeldIsStillPressed() {
        let flags: ModifierFlags = [.command, .leftCommandDevice, .rightCommandDevice]
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: flags), .pressed)
    }

    func testWorksWithoutDeviceBits() {
        // Some remappers/virtual keyboards only set the generic flag.
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: [.command]), .pressed)
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: rightCmd, flags: []), .released)
    }

    func testLeftCommandIsIgnored() {
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: leftCmd, flags: [.command, .leftCommandDevice]), .none)
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: leftCmd, flags: []), .none)
    }

    func testOtherModifiersAreIgnored() {
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: 56, flags: [.shift, .leftShiftDevice]), .none) // left shift
        XCTAssertEqual(ActivatorKey.change(forFlagsChangedKeyCode: 58, flags: [.option]), .none)                   // left option
    }

    func testIsRightCommandHeld() {
        XCTAssertTrue(ActivatorKey.isRightCommandHeld([.command, .rightCommandDevice]))
        XCTAssertTrue(ActivatorKey.isRightCommandHeld([.command]))
        XCTAssertTrue(ActivatorKey.isRightCommandHeld([.command, .leftCommandDevice, .rightCommandDevice]))
        XCTAssertFalse(ActivatorKey.isRightCommandHeld([.command, .leftCommandDevice]))
        XCTAssertFalse(ActivatorKey.isRightCommandHeld([]))
        XCTAssertFalse(ActivatorKey.isRightCommandHeld([.shift, .option]))
    }

    func testShiftDoesNotBlockTyping() {
        XCTAssertFalse(ActivatorKey.blocksTyping([.command, .rightCommandDevice, .shift, .leftShiftDevice]))
        XCTAssertFalse(ActivatorKey.blocksTyping([.command, .rightCommandDevice, .capsLock]))
    }

    func testControlOptionAndLeftCommandBlockTyping() {
        XCTAssertTrue(ActivatorKey.blocksTyping([.command, .rightCommandDevice, .control]))
        XCTAssertTrue(ActivatorKey.blocksTyping([.command, .rightCommandDevice, .option]))
        XCTAssertTrue(ActivatorKey.blocksTyping([.command, .rightCommandDevice, .leftCommandDevice]))
    }
}

final class WildcardPatternTests: XCTestCase {
    func testLiteralMatchIsCaseInsensitive() {
        XCTAssertTrue(WildcardPattern("Safari").matches("safari"))
        XCTAssertTrue(WildcardPattern("safari").matches("SAFARI"))
        XCTAssertFalse(WildcardPattern("Safari").matches("Safari Technology Preview"))
    }

    func testStarMatchesAnySequence() {
        XCTAssertTrue(WildcardPattern("com.apple.*").matches("com.apple.Safari"))
        XCTAssertTrue(WildcardPattern("com.apple.*").matches("com.apple."))
        XCTAssertFalse(WildcardPattern("com.apple.*").matches("com.google.Chrome"))
        XCTAssertTrue(WildcardPattern("*Preview").matches("Safari Technology Preview"))
        XCTAssertTrue(WildcardPattern("*Tech*").matches("Safari Technology Preview"))
        XCTAssertTrue(WildcardPattern("*").matches(""))
        XCTAssertTrue(WildcardPattern("**").matches("anything"))
    }

    func testQuestionMarkMatchesExactlyOne() {
        XCTAssertTrue(WildcardPattern("S?ack").matches("Slack"))
        XCTAssertFalse(WildcardPattern("S?ack").matches("Sack"))
        XCTAssertFalse(WildcardPattern("S?ack").matches("Sllack"))
    }

    func testBacktracking() {
        XCTAssertTrue(WildcardPattern("a*b*c").matches("aXXbYYbZZc"))
        XCTAssertFalse(WildcardPattern("a*b*c").matches("aXXbYY"))
    }

    func testEmptyPatternOnlyMatchesEmpty() {
        XCTAssertTrue(WildcardPattern("").matches(""))
        XCTAssertFalse(WildcardPattern("").matches("x"))
    }
}

final class ExclusionListTests: XCTestCase {
    func testMatchesNameOrBundleIdentifier() {
        let list = ExclusionList(patterns: ["Slack", "com.google.*"])
        XCTAssertTrue(list.excludes(Fixtures.slack))
        XCTAssertTrue(list.excludes(Fixtures.chrome))
        XCTAssertFalse(list.excludes(Fixtures.safari))
    }

    func testBlankPatternsAreDropped() {
        let list = ExclusionList(patterns: ["", "   ", "\n"])
        XCTAssertTrue(list.patterns.isEmpty)
        XCTAssertFalse(list.excludes(Fixtures.safari))
    }

    func testPatternsAreTrimmed() {
        let list = ExclusionList(patterns: ["  Safari  "])
        XCTAssertTrue(list.excludes(Fixtures.safari))
    }

    func testFilter() {
        let list = ExclusionList(patterns: ["com.apple.*"])
        let kept = list.filter(Fixtures.all).map(\.name)
        XCTAssertFalse(kept.contains("Safari"))
        XCTAssertFalse(kept.contains("Finder"))
        XCTAssertTrue(kept.contains("Slack"))
    }

    func testCandidateWithoutBundleIdentifier() {
        let list = ExclusionList(patterns: ["com.*"])
        XCTAssertFalse(list.excludes(AppCandidate(id: 1, name: "Loose Binary", bundleIdentifier: nil)))
    }
}

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.switchMode, .live)
        XCTAssertTrue(s.matchWordPrefixes)
        XCTAssertTrue(s.matchInitials)
        XCTAssertFalse(s.skipFrontmostApp)
        XCTAssertTrue(s.commitOnUniqueMatch)
        XCTAssertTrue(s.showOverlay)
        XCTAssertEqual(s.overlayPosition, .center)
        XCTAssertEqual(s.excludedPatterns, [])
    }

    func testRoundTrip() throws {
        var s = Settings()
        s.switchMode = .onRelease
        s.matchInitials = false
        s.commitOnUniqueMatch = false
        s.overlayPosition = .top
        s.excludedPatterns = ["com.apple.*", "Slack"]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let json = #"{"switchMode":"onRelease"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.switchMode, .onRelease)
        XCTAssertTrue(decoded.showOverlay)
        XCTAssertEqual(decoded.overlayPosition, .center)
    }

    func testUnknownEnumValueFallsBackToDefaultForThatKeyOnly() throws {
        let json = #"{"switchMode":"teleport","showOverlay":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.switchMode, .live)
        XCTAssertFalse(decoded.showOverlay)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(decoded, .default)
    }

    func testMatchOptionsReflectSettings() {
        var s = Settings()
        s.matchWordPrefixes = false
        XCTAssertEqual(s.matchOptions, MatchOptions(wordPrefixes: false, initials: true))
    }
}

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RightCmdTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreHasDefaults() {
        let store = SettingsStore(defaults: defaults, key: "test")
        XCTAssertEqual(store.settings, .default)
    }

    func testUpdatePersistsAndNotifies() {
        let store = SettingsStore(defaults: defaults, key: "test")
        var notified: [Settings] = []
        store.onChange = { notified.append($0) }

        store.update { $0.switchMode = .onRelease }

        XCTAssertEqual(store.settings.switchMode, .onRelease)
        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(notified.first?.switchMode, .onRelease)

        let reloaded = SettingsStore(defaults: defaults, key: "test")
        XCTAssertEqual(reloaded.settings.switchMode, .onRelease)
    }

    func testNoOpUpdateDoesNotNotify() {
        let store = SettingsStore(defaults: defaults, key: "test")
        var count = 0
        store.onChange = { _ in count += 1 }
        store.update { _ in }
        XCTAssertEqual(count, 0)
    }

    func testCorruptDataFallsBackToDefaults() {
        defaults.set("not json".data(using: .utf8), forKey: "test")
        let store = SettingsStore(defaults: defaults, key: "test")
        XCTAssertEqual(store.settings, .default)
    }

    func testResetToDefaults() {
        let store = SettingsStore(defaults: defaults, key: "test")
        store.update { $0.showOverlay = false }
        store.resetToDefaults()
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(SettingsStore(defaults: defaults, key: "test").settings, .default)
    }
}
