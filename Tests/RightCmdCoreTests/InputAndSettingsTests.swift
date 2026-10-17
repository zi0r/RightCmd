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

final class KeyPassThroughTests: XCTestCase {
    private let rightCmd: ModifierFlags = [.command, .rightCommandDevice]
    private let keyP: Int64 = 35

    func testOffByDefaultPassesNothing() {
        let settings = Settings()
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.leftArrow, flags: rightCmd, settings: settings))
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.rightArrow, flags: rightCmd, settings: settings))
        XCTAssertFalse(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.shift, .leftShiftDevice]), settings: settings))
    }

    func testOnlyLeftAndRightPassWhenArrowSettingIsOn() {
        var settings = Settings()
        settings.passThroughLeftRightArrows = true
        XCTAssertTrue(KeyPassThrough.passes(keyCode: KeyCode.leftArrow, flags: rightCmd, settings: settings))
        XCTAssertTrue(KeyPassThrough.passes(keyCode: KeyCode.rightArrow, flags: rightCmd, settings: settings))
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.upArrow, flags: rightCmd, settings: settings), "↑ still cycles")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.downArrow, flags: rightCmd, settings: settings), "↓ still cycles")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: 1, flags: rightCmd, settings: settings), "letters are still ours")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.escape, flags: rightCmd, settings: settings))
    }

    func testModifiedKeysPassWhenThatSettingIsOn() {
        var settings = Settings()
        settings.passThroughModifiedKeys = true
        XCTAssertTrue(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.shift, .leftShiftDevice]), settings: settings), "⌘⇧P")
        XCTAssertTrue(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.option, .leftOptionDevice]), settings: settings))
        XCTAssertTrue(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.control, .leftControlDevice]), settings: settings))
        XCTAssertTrue(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.leftCommandDevice]), settings: settings), "both ⌘ keys")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd, settings: settings), "right ⌘ alone is still ours")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.capsLock]), settings: settings), "Caps Lock is not a shortcut modifier")
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.leftArrow, flags: rightCmd, settings: settings), "arrows need their own setting")
    }

    func testSettingsAreIndependent() {
        var settings = Settings()
        settings.passThroughLeftRightArrows = true
        settings.passThroughModifiedKeys = false
        XCTAssertFalse(KeyPassThrough.passes(keyCode: keyP, flags: rightCmd.union([.shift]), settings: settings))
        settings.passThroughLeftRightArrows = false
        settings.passThroughModifiedKeys = true
        XCTAssertFalse(KeyPassThrough.passes(keyCode: KeyCode.rightArrow, flags: rightCmd, settings: settings))
        XCTAssertTrue(KeyPassThrough.passes(keyCode: KeyCode.rightArrow, flags: rightCmd.union([.shift]), settings: settings), "⇧→ is a modified key")
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
        XCTAssertFalse(s.movePointerToWindow)
        XCTAssertFalse(s.instantSpaceSwitching)
        XCTAssertFalse(s.passThroughLeftRightArrows)
        XCTAssertFalse(s.passThroughModifiedKeys)
        XCTAssertTrue(s.showOverlay)
        XCTAssertEqual(s.overlayPosition, .center)
        XCTAssertTrue(s.tintMenuBarIcon)
        XCTAssertEqual(s.iconColors, .default)
        XCTAssertEqual(s.excludedPatterns, [])
        XCTAssertFalse(s.includeFinder)
        XCTAssertEqual(s.priorityPatterns, [])
        XCTAssertTrue(s.priorityList.isEmpty)
    }

    func testFinderIsExcludedByDefault() {
        let list = Settings.default.exclusionList
        XCTAssertTrue(list.excludes(Fixtures.finder))
        XCTAssertFalse(list.excludes(Fixtures.safari))
        XCTAssertEqual(AppMatcher.matches(for: "f", in: list.filter(Fixtures.all)), [])
    }

    func testIncludeFinderSettingRestoresIt() {
        var s = Settings()
        s.includeFinder = true
        XCTAssertFalse(s.exclusionList.excludes(Fixtures.finder))
        XCTAssertEqual(AppMatcher.matches(for: "f", in: s.exclusionList.filter(Fixtures.all)), [Fixtures.finder])
    }

    func testBuiltInExclusionDoesNotLeakIntoUserPatterns() {
        let s = Settings()
        XCTAssertEqual(s.excludedPatterns, [], "the built-in rule is not stored as a user pattern")
        XCTAssertTrue(s.exclusionList.excludes(Fixtures.finder))
    }

    func testUserPatternsStillApplyAlongsideBuiltIns() {
        var s = Settings()
        s.excludedPatterns = ["Slack"]
        XCTAssertTrue(s.exclusionList.excludes(Fixtures.slack))
        XCTAssertTrue(s.exclusionList.excludes(Fixtures.finder))
        s.includeFinder = true
        XCTAssertTrue(s.exclusionList.excludes(Fixtures.slack))
        XCTAssertFalse(s.exclusionList.excludes(Fixtures.finder))
    }

    func testRoundTrip() throws {
        var s = Settings()
        s.switchMode = .onRelease
        s.matchInitials = false
        s.commitOnUniqueMatch = false
        s.movePointerToWindow = true
        s.instantSpaceSwitching = true
        s.passThroughLeftRightArrows = true
        s.passThroughModifiedKeys = true
        s.tintMenuBarIcon = false
        s.iconColors.matched = SRGBColor(hex: "#123456")!
        s.overlayPosition = .top
        s.excludedPatterns = ["com.apple.*", "Slack"]
        s.priorityPatterns = ["Xcode", "com.google.*"]
        s.includeFinder = true
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

    func testPartialIconColorsFallBackPerKey() throws {
        let json = #"{"iconColors":{"matched":{"red":1,"green":0,"blue":0},"noMatch":"garbage"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.iconColors.matched, SRGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(decoded.iconColors.listening, IconColors.default.listening)
        XCTAssertEqual(decoded.iconColors.noMatch, IconColors.default.noMatch)
    }

    func testMatchOptionsReflectSettings() {
        var s = Settings()
        s.matchWordPrefixes = false
        s.priorityPatterns = ["Slack"]
        XCTAssertEqual(s.matchOptions, MatchOptions(wordPrefixes: false, initials: true, priority: PriorityList(patterns: ["Slack"])))
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

final class SRGBColorTests: XCTestCase {
    func testHexRoundTrip() {
        let color = SRGBColor(hex: "#30D158")!
        XCTAssertEqual(color.hexString, "#30D158")
        XCTAssertEqual(SRGBColor(hex: "30d158"), color)
        XCTAssertEqual(SRGBColor(hex: "  #30D158\n"), color)
    }

    func testComponents() {
        let color = SRGBColor(hex: "#FF8000")!
        XCTAssertEqual(color.red, 1, accuracy: 0.001)
        XCTAssertEqual(color.green, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0, accuracy: 0.001)
    }

    func testInvalidHex() {
        XCTAssertNil(SRGBColor(hex: ""))
        XCTAssertNil(SRGBColor(hex: "#FFF"))
        XCTAssertNil(SRGBColor(hex: "#GGGGGG"))
        XCTAssertNil(SRGBColor(hex: "#FFFFFFFF"))
    }

    func testComponentsAreClamped() {
        let color = SRGBColor(red: 2, green: -1, blue: .nan)
        XCTAssertEqual(color, SRGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(color.hexString, "#FF0000")
    }

    func testDefaultsAreTheSystemColours() {
        XCTAssertEqual(IconColors.default.listening.hexString, "#0A84FF")
        XCTAssertEqual(IconColors.default.matched.hexString, "#30D158")
        XCTAssertEqual(IconColors.default.noMatch.hexString, "#FF453A")
    }

    func testCodableRoundTrip() throws {
        let colors = IconColors(listening: SRGBColor(hex: "#111111")!, matched: SRGBColor(hex: "#222222")!, noMatch: SRGBColor(hex: "#333333")!)
        let data = try JSONEncoder().encode(colors)
        XCTAssertEqual(try JSONDecoder().decode(IconColors.self, from: data), colors)
    }
}

final class SpaceSwitchPlannerTests: XCTestCase {
    func testNoMoveWhenAlreadyThere() {
        XCTAssertNil(SpaceSwitchPlanner.move(from: 2, to: 2, count: 5))
    }

    func testRightAndLeft() {
        XCTAssertEqual(SpaceSwitchPlanner.move(from: 0, to: 3, count: 5), SpaceMove(direction: .right, steps: 3))
        XCTAssertEqual(SpaceSwitchPlanner.move(from: 4, to: 1, count: 5), SpaceMove(direction: .left, steps: 3))
        XCTAssertEqual(SpaceSwitchPlanner.move(from: 1, to: 2, count: 3), SpaceMove(direction: .right, steps: 1))
    }

    func testInvalidIndicesYieldNoMove() {
        XCTAssertNil(SpaceSwitchPlanner.move(from: 0, to: 5, count: 5))
        XCTAssertNil(SpaceSwitchPlanner.move(from: -1, to: 0, count: 5))
        XCTAssertNil(SpaceSwitchPlanner.move(from: 0, to: 1, count: 0))
    }
}
