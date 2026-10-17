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
    /// Running apps offered by the "Add Running App" menu, refreshed when the window opens.
    @Published var runningApps: [AppCandidate] = []
    @Published var newPriorityPattern: String = ""

    private let store: SettingsStore
    private let appProvider = WorkspaceAppProvider()

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
        runningApps = appProvider.candidates(excluding: .empty)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Priority list editing

    /// Adds an app by bundle identifier (stable across renames and localisation), or by
    /// name when it has none.
    func addPriority(app: AppCandidate) {
        addPriority(pattern: app.bundleIdentifier ?? app.name)
    }

    func addPriority(pattern raw: String) {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        guard !settings.priorityPatterns.contains(where: { $0.caseInsensitiveCompare(pattern) == .orderedSame }) else { return }
        settings.priorityPatterns.append(pattern)
    }

    func addTypedPriority() {
        addPriority(pattern: newPriorityPattern)
        newPriorityPattern = ""
    }

    func movePriority(at index: Int, by delta: Int) {
        let target = index + delta
        guard settings.priorityPatterns.indices.contains(index),
              settings.priorityPatterns.indices.contains(target) else { return }
        settings.priorityPatterns.swapAt(index, target)
    }

    func removePriority(at index: Int) {
        guard settings.priorityPatterns.indices.contains(index) else { return }
        settings.priorityPatterns.remove(at: index)
    }

    /// A friendly label for a pattern: the running app's name when the pattern is its
    /// bundle identifier, otherwise the pattern itself.
    func displayName(forPriorityPattern pattern: String) -> String {
        if let app = runningApps.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(pattern) == .orderedSame }) {
            return app.name
        }
        return pattern
    }

    /// Whether the label differs from the raw pattern (so the pattern is worth showing too).
    func isBundleIdentifierPattern(_ pattern: String) -> Bool {
        displayName(forPriorityPattern: pattern) != pattern
    }

    /// A `ColorPicker` binding for one of the icon colours. A picker can hand back a colour
    /// with no RGB form (e.g. a pattern); those are ignored and the previous value stays.
    func iconColorBinding(_ keyPath: WritableKeyPath<IconColors, SRGBColor>) -> Binding<Color> {
        Binding(
            get: { Color(self.settings.iconColors[keyPath: keyPath]) },
            set: { newValue in
                guard let rgb = SRGBColor(newValue) else { return }
                self.settings.iconColors[keyPath: keyPath] = rgb
            }
        )
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

            Section {
                if model.settings.priorityPatterns.isEmpty {
                    Text("No priority apps. Matches are ordered by match quality, then name.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.settings.priorityPatterns.enumerated()), id: \.offset) { item in
                    priorityRow(index: item.offset, pattern: item.element)
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(model.runningApps, id: \.id) { app in
                            Button(app.name) { model.addPriority(app: app) }
                        }
                    }
                    .fixedSize()
                    TextField("or a name / bundle id pattern", text: $model.newPriorityPattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.addTypedPriority() }
                    Button("Add") { model.addTypedPriority() }
                        .disabled(model.newPriorityPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Priority apps")
            } footer: {
                Text("Apps on this list outrank every other match, top first. They still have to match what you type; priority only settles the order. Patterns use the same syntax as exclusions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("Tint the icon while right ⌘ is held", isOn: $model.settings.tintMenuBarIcon)
                ColorPicker("Listening (nothing typed yet)", selection: model.iconColorBinding(\.listening), supportsOpacity: false)
                ColorPicker("Match", selection: model.iconColorBinding(\.matched), supportsOpacity: false)
                ColorPicker("No match", selection: model.iconColorBinding(\.noMatch), supportsOpacity: false)
                HStack {
                    Spacer()
                    Button("Reset Colors") { model.settings.iconColors = .default }
                        .disabled(model.settings.iconColors == .default)
                }
            } header: {
                Text("Menu bar icon")
            } footer: {
                Text("The colour stays for a moment after you let go, so the result of a quick switch is still visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Include Finder", isOn: $model.settings.includeFinder)
                TextEditor(text: $exclusionsDraft)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .onChange(of: exclusionsDraft) { _, newValue in
                        model.excludedPatternsText = newValue
                    }
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Finder is left out unless included: it is always running and would otherwise claim “F”. Below, one pattern per line, matched against the app name or bundle identifier. “*” matches anything, e.g. com.apple.* or *Helper.")
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
        // given one explicitly or it collapses to its title bar. Height is a minimum so the
        // window can be resized taller; the form scrolls when shorter than its content.
        .frame(width: SettingsWindowController.contentSize.width)
        .frame(minHeight: SettingsWindowController.contentSize.height, maxHeight: .infinity)
        .onAppear {
            model.refresh()
            exclusionsDraft = model.excludedPatternsText
        }
    }
}

extension SettingsView {
    @ViewBuilder
    fileprivate func priorityRow(index: Int, pattern: String) -> some View {
        let count = model.settings.priorityPatterns.count
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(forPriorityPattern: pattern))
                if model.isBundleIdentifierPattern(pattern) {
                    Text(pattern).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { model.movePriority(at: index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
            Button { model.movePriority(at: index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("Move down")
            Button(role: .destructive) { model.removePriority(at: index) } label: { Image(systemName: "minus.circle") }
                .help("Remove")
        }
        .buttonStyle(.borderless)
    }
}

/// Owns the single settings window; reopening brings the existing one forward.
final class SettingsWindowController {
    static let contentSize = NSSize(width: 480, height: 820)

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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(Self.contentSize)
            window.contentMinSize = Self.contentSize
            window.contentMaxSize = NSSize(width: Self.contentSize.width, height: .greatestFiniteMagnitude)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
