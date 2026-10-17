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

// MARK: - Panes

/// Shared frame for every pane so the window width is constant and only the height changes
/// between tabs. Panes are plain stacks (not a grouped `Form`, which is scroll-backed and
/// has no intrinsic height), so each one reports its real size and nothing ever scrolls.
private struct SettingsPane<Content: View>: View {
    static var width: CGFloat { 540 }
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(20)
            .frame(width: Self.width, alignment: .topLeading)
    }
}

/// A titled group whose content is left-aligned and fills the width.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Switching") {
                Text("Switch to the app:")
                Picker("", selection: $model.settings.switchMode) {
                    ForEach(SwitchMode.allCases, id: \.self) { mode in
                        Text(StatusMenuController.title(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Toggle("Switch as soon as only one app matches", isOn: $model.settings.commitOnUniqueMatch)
                Toggle("Prefer another app when the best match is already in front", isOn: $model.settings.skipFrontmostApp)
            }

            SettingsGroup(title: "Startup") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .disabled(!LaunchAtLogin.isSupported)
                if !LaunchAtLogin.isSupported {
                    Hint("Available when running from RightCmd.app.")
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            SettingsGroup(title: "Permissions") {
                HStack {
                    Label(
                        AccessibilityPermission.isTrusted() ? "Accessibility access granted" : "Accessibility access not granted",
                        systemImage: AccessibilityPermission.isTrusted() ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(AccessibilityPermission.isTrusted() ? Color.secondary : Color.orange)
                    Spacer()
                    Button("Open System Settings…") { AccessibilityPermission.openSystemSettings() }
                }
                Hint("RightCmd needs Accessibility access to see the right ⌘ key and bring apps to the front.")
            }
        }
    }
}

struct MatchingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Match the typed letters against") {
                Toggle("The start of the app name (always on)", isOn: .constant(true))
                    .disabled(true)
                Toggle("The start of any later word (“c” finds Google Chrome)", isOn: $model.settings.matchWordPrefixes)
                Toggle("Initials (“vsc” finds Visual Studio Code)", isOn: $model.settings.matchInitials)
            }

            SettingsGroup(title: "Priority apps") {
                Hint("Apps on this list outrank every other match, top first. They still have to match what you type; priority only settles the order.")
                priorityList
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
            }
        }
    }

    private var priorityList: some View {
        List {
            if model.settings.priorityPatterns.isEmpty {
                Text("No priority apps yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.settings.priorityPatterns.enumerated()), id: \.offset) { item in
                priorityRow(index: item.offset, pattern: item.element)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 170)
    }

    private func priorityRow(index: Int, pattern: String) -> some View {
        let count = model.settings.priorityPatterns.count
        return HStack(spacing: 8) {
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
        .padding(.vertical, 2)
    }
}

struct AppearancePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Overlay") {
                Toggle("Show the overlay while typing", isOn: $model.settings.showOverlay)
                HStack {
                    Text("Position:")
                    Picker("", selection: $model.settings.overlayPosition) {
                        Text("Center").tag(OverlayPosition.center)
                        Text("Top").tag(OverlayPosition.top)
                        Text("Bottom").tag(OverlayPosition.bottom)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!model.settings.showOverlay)
            }

            SettingsGroup(title: "Menu bar icon") {
                Toggle("Tint the icon while right ⌘ is held", isOn: $model.settings.tintMenuBarIcon)
                Hint("The colour stays for a moment after you let go, so the result of a quick switch is still visible.")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    colorRow("Listening (nothing typed yet)", \.listening)
                    colorRow("Match", \.matched)
                    colorRow("No match", \.noMatch)
                }
                .disabled(!model.settings.tintMenuBarIcon)
                HStack {
                    Spacer()
                    Button("Reset Colors") { model.settings.iconColors = .default }
                        .disabled(model.settings.iconColors == .default)
                }
            }
        }
    }
}

extension AppearancePane {
    /// Label in the first column, colour well in the second, so the wells line up.
    fileprivate func colorRow(_ label: String, _ keyPath: WritableKeyPath<IconColors, SRGBColor>) -> some View {
        GridRow {
            Text(label)
            ColorPicker("", selection: model.iconColorBinding(keyPath), supportsOpacity: false)
                .labelsHidden()
        }
    }
}

struct ExclusionsPane: View {
    @ObservedObject var model: SettingsModel
    @State private var exclusionsDraft: String = ""

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Built-in") {
                Toggle("Include Finder", isOn: $model.settings.includeFinder)
                Hint("Finder is left out unless included: it is always running and would otherwise claim “F”.")
            }

            SettingsGroup(title: "Excluded apps") {
                TextEditor(text: $exclusionsDraft)
                    .font(.body.monospaced())
                    .frame(height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: exclusionsDraft) { _, newValue in
                        model.excludedPatternsText = newValue
                    }
                Hint("One pattern per line, matched against the app name or bundle identifier. “*” matches anything, e.g. com.apple.* or *Helper.")
            }
        }
        .onAppear { exclusionsDraft = model.excludedPatternsText }
    }
}

// MARK: - Window

/// Toolbar-style tabs, with the window resized to fit each pane as it is selected.
///
/// `NSTabViewController` manages the toolbar for us but does not resize the window to the
/// selected pane by itself, so that is done here from the pane's fitting size.
private final class SettingsTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = false
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fitWindowToSelectedPane(animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedPane(animated: true)
    }

    private func fitWindowToSelectedPane(animated: Bool) {
        guard let window = view.window,
              tabViewItems.indices.contains(selectedTabViewItemIndex),
              let pane = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        pane.view.layoutSubtreeIfNeeded()
        let size = pane.view.fittingSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let current = window.frame
        // Keep the window's top-left corner where it is, like System Settings.
        frame.origin = NSPoint(x: current.minX, y: current.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated)
    }
}

/// Owns the single settings window; reopening brings the existing one forward.
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(settingsStore: SettingsStore) {
        self.model = SettingsModel(store: settingsStore)
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.addTabViewItem(makeTab("General", symbol: "gearshape", view: GeneralPane(model: model)))
        tabs.addTabViewItem(makeTab("Matching", symbol: "textformat.abc", view: MatchingPane(model: model)))
        tabs.addTabViewItem(makeTab("Appearance", symbol: "paintpalette", view: AppearancePane(model: model)))
        tabs.addTabViewItem(makeTab("Exclusions", symbol: "eye.slash", view: ExclusionsPane(model: model)))

        let window = NSWindow(contentViewController: tabs)
        window.title = "RightCmd Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func makeTab<V: View>(_ label: String, symbol: String, view: V) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: NSHostingController(rootView: view))
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
