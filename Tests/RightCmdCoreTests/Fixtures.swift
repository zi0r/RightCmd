import Foundation
@testable import RightCmdCore

enum Fixtures {
    static let finder = AppCandidate(id: 100, name: "Finder", bundleIdentifier: "com.apple.finder")
    static let safari = AppCandidate(id: 101, name: "Safari", bundleIdentifier: "com.apple.Safari")
    static let slack = AppCandidate(id: 102, name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
    static let systemSettings = AppCandidate(id: 103, name: "System Settings", bundleIdentifier: "com.apple.systempreferences")
    static let chrome = AppCandidate(id: 104, name: "Google Chrome", bundleIdentifier: "com.google.Chrome")
    static let vscode = AppCandidate(id: 105, name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
    static let xcode = AppCandidate(id: 106, name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
    static let sequel = AppCandidate(id: 107, name: "Sequel Ace", bundleIdentifier: "com.sequel-ace.sequel-ace")
    static let eclair = AppCandidate(id: 108, name: "Éclair", bundleIdentifier: "fr.example.eclair")
    static let onePassword = AppCandidate(id: 109, name: "1Password", bundleIdentifier: "com.1password.1password")

    static let all: [AppCandidate] = [
        finder, safari, slack, systemSettings, chrome, vscode, xcode, sequel, eclair, onePassword,
    ]
}

/// Collects the actions a session emits, with small helpers for assertions.
struct ActionLog {
    var actions: [SessionAction] = []

    mutating func record(_ new: [SessionAction]) {
        actions.append(contentsOf: new)
    }

    var activations: [AppCandidate] {
        actions.compactMap {
            if case .activate(let app) = $0 { return app }
            return nil
        }
    }

    var overlays: [OverlayState] {
        actions.compactMap {
            if case .showOverlay(let state) = $0 { return state }
            return nil
        }
    }

    var hideCount: Int {
        actions.filter { $0 == .hideOverlay }.count
    }
}
