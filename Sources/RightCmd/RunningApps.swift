import AppKit
import Carbon
import RightCmdCore

/// Supplies the set of switchable apps and the current frontmost app.
protocol AppProviding {
    func candidates(excluding exclusions: ExclusionList) -> [AppCandidate]
    func frontmost() -> AppCandidate?
}

/// Uses `NSWorkspace`, which is the supported way to enumerate apps.
///
/// The reference implementation scraped `CGWindowListCopyWindowInfo`, which lists windows
/// rather than apps and on modern macOS needs Screen Recording permission for window
/// titles. `NSWorkspace.runningApplications` with `.regular` activation policy gives exactly
/// the apps that appear in the Dock and ⌘-Tab, with no extra permissions.
struct WorkspaceAppProvider: AppProviding {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func candidates(excluding exclusions: ExclusionList) -> [AppCandidate] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID }
            .map(Self.candidate(for:))
        return exclusions.filter(apps)
    }

    func frontmost() -> AppCandidate? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Self.candidate(for: app)
    }

    static func candidate(for app: NSRunningApplication) -> AppCandidate {
        let name = app.localizedName
            ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            ?? app.bundleIdentifier
            ?? "pid \(app.processIdentifier)"
        return AppCandidate(id: app.processIdentifier, name: name, bundleIdentifier: app.bundleIdentifier)
    }
}

enum SecureInput {
    /// True while a secure text field (password entry) has focus anywhere on the system.
    /// Event taps don't receive key events in that state.
    static var isEnabled: Bool {
        // `Boolean` from MacTypes; the explicit init is correct whether it imports as
        // `Bool` or `DarwinBoolean`.
        Bool(IsSecureEventInputEnabled())
    }
}
