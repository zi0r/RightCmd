import Carbon
import Foundation

/// Resolves a virtual key code to the base character it produces on the user's current
/// keyboard layout, so a French AZERTY user typing "a" gets "a" and not "q".
///
/// Unlike the reference implementation's hard-coded ANSI table, this asks the Text Input
/// Services for the active layout's `uchr` data and runs `UCKeyTranslate` with no
/// modifiers, so ⌘/⇧ state doesn't affect the result. Input sources without layout data
/// (e.g. some CJK input methods) fall back to the current ASCII-capable layout.
protocol KeyCharacterTranslating {
    func character(forKeyCode keyCode: Int64) -> Character?
}

final class KeyboardLayoutTranslator: KeyCharacterTranslating {
    func character(forKeyCode keyCode: Int64) -> Character? {
        guard keyCode >= 0, keyCode <= Int64(UInt16.max) else { return nil }

        var layoutData: CFData? = nil
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            layoutData = Self.layoutData(for: source)
        }
        if layoutData == nil, let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            layoutData = Self.layoutData(for: source)
        }
        guard let data = layoutData else { return nil }
        return Self.translate(keyCode: UInt16(keyCode), layoutData: data)
    }

    private static func layoutData(for source: TISInputSource) -> CFData? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func translate(keyCode: UInt16, layoutData: CFData) -> Character? {
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout -> Character? in
            var deadKeyState: UInt32 = 0
            var actualLength = 0        // UniCharCount imports as Int
            var buffer = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,                                     // no modifiers: base character
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                buffer.count,
                &actualLength,
                &buffer
            )
            guard status == noErr, actualLength > 0 else { return nil }
            let string = String(utf16CodeUnits: buffer, count: actualLength)
            return string.first
        }
    }
}
