import Foundation

/// What a key press means to the switcher while the activator key is held.
public enum KeyInput: Equatable, Sendable {
    /// A printable character to append to the query.
    case character(Character)
    /// Remove the last character of the query.
    case backspace
    /// Cancel the session (and, in live mode, return to the original app).
    case escape
    /// Commit the current selection and end the session.
    case confirm
    /// Move the selection to the next matching app.
    case next
    /// Move the selection to the previous matching app.
    case previous
    /// A key that has no meaning here. It is still swallowed so it does not reach other apps.
    case ignored
}

/// Virtual key codes (`kVK_*` from Carbon's Events.h). Layout independent.
public enum KeyCode {
    public static let returnKey: Int64 = 0x24
    public static let tab: Int64 = 0x30
    public static let space: Int64 = 0x31
    public static let delete: Int64 = 0x33          // Backspace on most keyboards
    public static let escape: Int64 = 0x35
    public static let rightCommand: Int64 = 0x36
    public static let command: Int64 = 0x37         // Left command
    public static let rightOption: Int64 = 0x3D
    public static let rightControl: Int64 = 0x3E
    public static let keypadEnter: Int64 = 0x4C
    public static let forwardDelete: Int64 = 0x75
    public static let leftArrow: Int64 = 0x7B
    public static let rightArrow: Int64 = 0x7C
    public static let downArrow: Int64 = 0x7D
    public static let upArrow: Int64 = 0x7E
}

/// Turns a key code plus the character the current keyboard layout produces for it
/// into a `KeyInput`. The character is resolved by the app layer (UCKeyTranslate), so
/// non-US layouts work; this function only decides what the key *means*.
public enum KeyClassifier {
    public static func classify(keyCode: Int64, character: Character?) -> KeyInput {
        switch keyCode {
        case KeyCode.delete, KeyCode.forwardDelete:
            return .backspace
        case KeyCode.escape:
            return .escape
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .confirm
        case KeyCode.downArrow, KeyCode.rightArrow:
            return .next
        case KeyCode.upArrow, KeyCode.leftArrow:
            return .previous
        case KeyCode.tab, KeyCode.space:
            // Space is deliberately not typable: ⌘Space is a system hotkey (Spotlight) and
            // word-prefix matching makes it unnecessary; `Settings.passThroughSpace` lets it
            // reach the system instead. Tab is reserved (⌘Tab is the system app switcher).
            return .ignored
        default:
            break
        }
        guard let character, isTypable(character) else {
            return .ignored
        }
        return .character(character)
    }

    /// Letters, digits and ordinary punctuation/symbols count; whitespace and control
    /// characters do not.
    static func isTypable(_ character: Character) -> Bool {
        if character.isWhitespace || character.isNewline { return false }
        if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return false
        }
        return character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
    }
}

/// Modifier flags as carried by `CGEventFlags`, including the undocumented-but-stable
/// device-specific bits from IOKit's `NX_DEVICE*KEYMASK` that distinguish left from right keys.
public struct ModifierFlags: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    // kCGEventFlagMask*
    public static let capsLock = ModifierFlags(rawValue: 1 << 16)
    public static let shift = ModifierFlags(rawValue: 1 << 17)
    public static let control = ModifierFlags(rawValue: 1 << 18)
    public static let option = ModifierFlags(rawValue: 1 << 19)
    public static let command = ModifierFlags(rawValue: 1 << 20)
    public static let numericPad = ModifierFlags(rawValue: 1 << 21)
    public static let help = ModifierFlags(rawValue: 1 << 22)
    public static let function = ModifierFlags(rawValue: 1 << 23)

    // NX_DEVICE*KEYMASK (IOKit/hidsystem/IOLLEvent.h)
    public static let leftControlDevice = ModifierFlags(rawValue: 0x0000_0001)
    public static let leftShiftDevice = ModifierFlags(rawValue: 0x0000_0002)
    public static let rightShiftDevice = ModifierFlags(rawValue: 0x0000_0004)
    public static let leftCommandDevice = ModifierFlags(rawValue: 0x0000_0008)
    public static let rightCommandDevice = ModifierFlags(rawValue: 0x0000_0010)
    public static let leftOptionDevice = ModifierFlags(rawValue: 0x0000_0020)
    public static let rightOptionDevice = ModifierFlags(rawValue: 0x0000_0040)
    public static let rightControlDevice = ModifierFlags(rawValue: 0x0000_2000)
}

/// Which right-hand modifier key starts a switch. Right ⌘ is the default; the right ⌥ and
/// ⌃ keys are offered because they're equally underused and leave ⌘ shortcuts untouched.
public enum ActivatorModifier: String, Codable, CaseIterable, Sendable {
    case rightCommand
    case rightOption
    case rightControl

    /// The virtual key code reported on this key's own `flagsChanged` events.
    public var keyCode: Int64 {
        switch self {
        case .rightCommand: return KeyCode.rightCommand
        case .rightOption: return KeyCode.rightOption
        case .rightControl: return KeyCode.rightControl
        }
    }

    /// The generic (side-agnostic) flag this key sets.
    public var flag: ModifierFlags {
        switch self {
        case .rightCommand: return .command
        case .rightOption: return .option
        case .rightControl: return .control
        }
    }

    /// The device-specific bit for the left-hand twin of this key.
    public var leftDeviceFlag: ModifierFlags {
        switch self {
        case .rightCommand: return .leftCommandDevice
        case .rightOption: return .leftOptionDevice
        case .rightControl: return .leftControlDevice
        }
    }

    /// The device-specific bit for this key.
    public var rightDeviceFlag: ModifierFlags {
        switch self {
        case .rightCommand: return .rightCommandDevice
        case .rightOption: return .rightOptionDevice
        case .rightControl: return .rightControlDevice
        }
    }

    /// "⌘", "⌥" or "⌃".
    public var symbol: String {
        switch self {
        case .rightCommand: return "⌘"
        case .rightOption: return "⌥"
        case .rightControl: return "⌃"
        }
    }

    /// "right ⌘" etc., for prose.
    public var name: String { "right \(symbol)" }

    /// "Right ⌘ (Command)" etc., for menus and pickers.
    public var displayName: String {
        switch self {
        case .rightCommand: return "Right ⌘ (Command)"
        case .rightOption: return "Right ⌥ (Option)"
        case .rightControl: return "Right ⌃ (Control)"
        }
    }

    /// The generic flags of the two modifiers that are *not* this one.
    var otherModifierFlags: ModifierFlags {
        let all: ModifierFlags = [.command, .option, .control]
        return all.subtracting(flag)
    }
}

/// What a `flagsChanged` event means for the activator key.
public enum ActivatorChange: Equatable, Sendable {
    case pressed
    case released
    /// Some other modifier changed; not our concern.
    case none
}

public enum ActivatorKey {
    /// Interprets a `flagsChanged` event.
    ///
    /// The key code identifies *which* modifier key changed, and the flags tell us its new
    /// state. The device-specific bits are used when present so that releasing the right
    /// key while its left twin is still held is correctly reported as a release;
    /// keyboards or remappers that don't set device bits still work via the generic flag.
    public static func change(
        forFlagsChangedKeyCode keyCode: Int64,
        flags: ModifierFlags,
        activator: ActivatorModifier = .rightCommand
    ) -> ActivatorChange {
        guard keyCode == activator.keyCode else { return .none }
        return isHeld(flags, activator: activator) ? .pressed : .released
    }

    /// Whether the flags are consistent with the activator key being down. Used both to
    /// interpret the key's own `flagsChanged` event and as a sanity check on every other
    /// event, so a missed release can never leave the switcher swallowing keystrokes.
    public static func isHeld(_ flags: ModifierFlags, activator: ActivatorModifier) -> Bool {
        guard flags.contains(activator.flag) else { return false }
        if flags.contains(activator.leftDeviceFlag) && !flags.contains(activator.rightDeviceFlag) {
            // Only the left twin is reported down.
            return false
        }
        return true
    }

    /// `isHeld` for the default activator.
    public static func isRightCommandHeld(_ flags: ModifierFlags) -> Bool {
        isHeld(flags, activator: .rightCommand)
    }

    /// True when modifiers other than the activator and Shift are held, which makes a
    /// key press ambiguous: the two other generic modifiers, or the activator's *left*
    /// twin. Such presses are swallowed but not typed. Shift is allowed because it
    /// doesn't change which app a letter refers to.
    public static func blocksTyping(_ flags: ModifierFlags, activator: ActivatorModifier = .rightCommand) -> Bool {
        if !flags.isDisjoint(with: activator.otherModifierFlags) { return true }
        return flags.contains(activator.leftDeviceFlag)
    }
}

/// Keys that are handed to the system untouched while the activator key is held.
public enum KeyPassThrough {
    /// True if a key event with this key code and these flags should be passed through
    /// rather than swallowed and interpreted, given the settings. Applies to key down, key
    /// up and auto-repeat alike, so the receiver sees a complete, ordinary key press.
    public static func passes(keyCode: Int64, flags: ModifierFlags, settings: Settings) -> Bool {
        if settings.passThroughLeftRightArrows,
           keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow {
            return true
        }
        if settings.passThroughSpace, keyCode == KeyCode.space {
            return true
        }
        if settings.passThroughModifiedKeys, hasExtraModifier(flags, activator: settings.activator) {
            return true
        }
        return false
    }

    /// Shift, either of the two other modifiers, or the activator's left twin held
    /// alongside the activator. Caps Lock and the Fn/numeric-pad flags don't count; they
    /// don't make a key a shortcut.
    public static func hasExtraModifier(_ flags: ModifierFlags, activator: ActivatorModifier = .rightCommand) -> Bool {
        if flags.contains(.shift) { return true }
        if !flags.isDisjoint(with: activator.otherModifierFlags) { return true }
        return flags.contains(activator.leftDeviceFlag)
    }
}
