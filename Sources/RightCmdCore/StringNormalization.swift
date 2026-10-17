import Foundation

/// Text folding used for matching so that "Éclair" matches "ec" and "safari" matches "SAF".
public enum StringNormalization {
    /// Lowercases the string and strips combining diacritical marks.
    ///
    /// Implemented with canonical decomposition and Unicode combining classes rather than
    /// `String.folding(options:locale:)`, so it behaves identically on every Foundation.
    public static func fold(_ string: String) -> String {
        let decomposed = string.decomposedStringWithCanonicalMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars
        where scalar.properties.canonicalCombiningClass == .notReordered {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
    }

    /// Splits a (typically already folded) string into words on anything that is not a
    /// letter or a digit. "Visual Studio Code" → ["visual", "studio", "code"],
    /// "iTerm2" → ["iterm2"], "1Password 8" → ["1password", "8"].
    public static func words(_ string: String) -> [String] {
        string
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The first character of each word, joined. "Visual Studio Code" → "vsc".
    public static func initials(_ string: String) -> String {
        String(words(string).compactMap { $0.first })
    }
}
