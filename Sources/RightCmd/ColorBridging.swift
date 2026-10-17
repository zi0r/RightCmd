import AppKit
import RightCmdCore
import SwiftUI

extension NSColor {
    convenience init(_ rgb: SRGBColor) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension Color {
    init(_ rgb: SRGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension SRGBColor {
    /// Converts a SwiftUI colour (e.g. from `ColorPicker`) to sRGB components. Returns nil
    /// for colours with no RGB representation.
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}
