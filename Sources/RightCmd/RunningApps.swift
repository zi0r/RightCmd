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
final class WorkspaceAppProvider: AppProviding {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Alternate names come from the bundle's Info.plist, which doesn't change while the
    /// process lives; cache per pid so a session start doesn't re-read thirty plists.
    private var alternateNameCache: [pid_t: [String]] = [:]

    init() {}

    func candidates(excluding exclusions: ExclusionList) -> [AppCandidate] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID }
        let live = Set(running.map(\.processIdentifier))
        alternateNameCache = alternateNameCache.filter { live.contains($0.key) }
        return exclusions.filter(running.map(candidate(for:)))
    }

    func frontmost() -> AppCandidate? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return candidate(for: app)
    }

    func candidate(for app: NSRunningApplication) -> AppCandidate {
        let name = Self.primaryName(for: app)
        return AppCandidate(
            id: app.processIdentifier,
            name: name,
            bundleIdentifier: app.bundleIdentifier,
            alternateNames: alternateNames(for: app, primary: name)
        )
    }

    static func primaryName(for app: NSRunningApplication) -> String {
        app.localizedName
            ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            ?? app.bundleIdentifier
            ?? "pid \(app.processIdentifier)"
    }

    /// The bundle's file name and its `CFBundleDisplayName` / `CFBundleName`, when they
    /// differ from the localized name macOS shows. Covers localised and renamed apps
    /// (the executable name is deliberately left out: Electron apps all share one).
    private func alternateNames(for app: NSRunningApplication, primary: String) -> [String] {
        if let cached = alternateNameCache[app.processIdentifier] { return cached }
        var names: [String] = []
        if let url = app.bundleURL {
            names.append(url.deletingPathExtension().lastPathComponent)
            if let info = Bundle(url: url)?.infoDictionary {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let value = info[key] as? String { names.append(value) }
                }
            }
        }
        let deduped = AppCandidate(id: 0, name: primary, alternateNames: names).alternateNames
        alternateNameCache[app.processIdentifier] = deduped
        return deduped
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
