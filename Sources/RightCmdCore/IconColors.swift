import Foundation

/// An sRGB colour with components in 0...1. Kept free of AppKit so settings stay portable
/// and testable; the app layer converts to and from `NSColor`/`Color`.
public struct SRGBColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// Parses `#RRGGBB` or `RRGGBB` (case-insensitive). Returns nil for anything else.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB`, upper-case.
    public var hexString: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    private static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    private static func byte(_ component: Double) -> Int {
        Int((component * 255).rounded())
    }
}

/// Colours used to tint the menu bar icon while the activator key is held.
public struct IconColors: Codable, Equatable, Sendable {
    /// The activator key is held and nothing has been typed yet.
    public var listening: SRGBColor
    /// The typed letters match at least one app.
    public var matched: SRGBColor
    /// The typed letters match nothing.
    public var noMatch: SRGBColor
    /// Keys are being passed through to the system or the front app: a pass-through key is
    /// down, or a modifier combination that the pass-through settings hand on is held.
    public var passThrough: SRGBColor

    public init(listening: SRGBColor, matched: SRGBColor, noMatch: SRGBColor, passThrough: SRGBColor = IconColors.defaultPassThrough) {
        self.listening = listening
        self.matched = matched
        self.noMatch = noMatch
        self.passThrough = passThrough
    }

    /// The system blue, green, red and orange.
    public static let `default` = IconColors(
        listening: SRGBColor(hex: "#0A84FF")!,
        matched: SRGBColor(hex: "#30D158")!,
        noMatch: SRGBColor(hex: "#FF453A")!,
        passThrough: defaultPassThrough
    )

    public static let defaultPassThrough = SRGBColor(hex: "#FF9F0A")!

    private enum CodingKeys: String, CodingKey {
        case listening, matched, noMatch, passThrough
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = IconColors.default
        listening = (try? c.decodeIfPresent(SRGBColor.self, forKey: .listening)) ?? defaults.listening
        matched = (try? c.decodeIfPresent(SRGBColor.self, forKey: .matched)) ?? defaults.matched
        noMatch = (try? c.decodeIfPresent(SRGBColor.self, forKey: .noMatch)) ?? defaults.noMatch
        passThrough = (try? c.decodeIfPresent(SRGBColor.self, forKey: .passThrough)) ?? defaults.passThrough
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listening, forKey: .listening)
        try c.encode(matched, forKey: .matched)
        try c.encode(noMatch, forKey: .noMatch)
        try c.encode(passThrough, forKey: .passThrough)
    }
}
