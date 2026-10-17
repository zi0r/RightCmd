import Foundation

/// A running application that can be switched to.
///
/// This is a platform-neutral value type so the matching and session logic can be
/// unit tested without AppKit. The app layer builds these from `NSRunningApplication`.
public struct AppCandidate: Hashable, Identifiable, Sendable {
    /// The process identifier. Unique among running processes.
    public let id: Int32
    /// The user-visible application name, e.g. "Safari" or "Visual Studio Code".
    public let name: String
    /// The bundle identifier, when known, e.g. "com.apple.Safari".
    public let bundleIdentifier: String?

    public init(id: Int32, name: String, bundleIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}
