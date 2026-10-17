import AppKit
import RightCmdCore
import SwiftUI

/// Observable bridge over `SettingsStore` for SwiftUI bindings.
///
/// `RightCmdCore.Settings` is spelled out because SwiftUI also exports a `Settings` scene
/// type, which makes the bare name ambiguous in any file that imports both modules.
final class SettingsModel: ObservableObject {
    @Published var settings: RightCmdCore.Settings {
        didSet { store.replace(settings) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            do {
                try LaunchAtLogin.setEnabled(launchAtLogin)
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }
    @Published var launchAtLoginError: String?

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.settings
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Re-read from the store (e.g. after a menu change) without writing back.
    func refresh() {
        if settings != store.settings {
            settings = store.settings
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    var excludedPatternsText: String {
        get { settings.excludedPatterns.joined(separator: "\n") }
        set {
            settings.excludedPatterns = newValue
                .split(whereSeparator: { $0 == "\n" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var exclusionsDraft: String = ""

    var body: some View {
        Form {
            Section("Switching") {
                Picker("Switch to the app", selection: $model.settings.switchMode) {
                    ForEach(SwitchMode.allCases, id: \.self) { mode in
                        Text(StatusMenuController.title(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Toggle("Switch as soon as only one app matches", isOn: $model.settings.commitOnUniqueMatch)
                Toggle("Prefer another app when the best match is already in front", isOn: $model.settings.skipFrontmostApp)
            }

            Section("Matching") {
                Toggle("Match the start of any word (“c” finds Google Chrome)", isOn: $model.settings.matchWordPrefixes)
                Toggle("Match initials (“vsc” finds Visual Studio Code)", isOn: $model.settings.matchInitials)
            }

            Section("Overlay") {
                Toggle("Show overlay while typing", isOn: $model.settings.showOverlay)
                Picker("Position", selection: $model.settings.overlayPosition) {
                    Text("Center").tag(OverlayPosition.center)
                    Text("Top").tag(OverlayPosition.top)
                    Text("Bottom").tag(OverlayPosition.bottom)
                }
                .disabled(!model.settings.showOverlay)
            }

            Section {
                TextEditor(text: $exclusionsDraft)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .onChange(of: exclusionsDraft) { _, newValue in
                        model.excludedPatternsText = newValue
                    }
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("One pattern per line, matched against the app name or bundle identifier. “*” matches anything, e.g. com.apple.* or *Helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .disabled(!LaunchAtLogin.isSupported)
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Text(AccessibilityPermission.isTrusted() ? "Accessibility: granted" : "Accessibility: not granted")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings…") { AccessibilityPermission.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        // A grouped Form is scroll-backed and has no intrinsic height, so the window must be
        // given one explicitly or it collapses to its title bar.
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
        .onAppear {
            model.refresh()
            exclusionsDraft = model.excludedPatternsText
        }
    }
}

/// Owns the single settings window; reopening brings the existing one forward.
final class SettingsWindowController {
    static let contentSize = NSSize(width: 480, height: 560)

    private let model: SettingsModel
    private var window: NSWindow?

    init(settingsStore: SettingsStore) {
        self.model = SettingsModel(store: settingsStore)
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            hosting.preferredContentSize = Self.contentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "RightCmd Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(Self.contentSize)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
