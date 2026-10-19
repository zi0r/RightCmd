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

    private let store: SettingsStore
    private let appProvider = WorkspaceAppProvider()

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.settings
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Pick up a change made elsewhere (the menu bar) without writing back. Cheap enough
    /// to call on every store change: a no-op when the values already agree.
    func syncFromStore() {
        if settings != store.settings {
            settings = store.settings
        }
    }

    /// Full refresh when the window opens: settings, login state and the running-app list.
    func refresh() {
        if settings != store.settings {
            settings = store.settings
        }
        launchAtLogin = LaunchAtLogin.isEnabled
        runningApps = appProvider.candidates(excluding: .empty)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Pattern list editing (priority and deprioritized lists)

    typealias PatternList = WritableKeyPath<RightCmdCore.Settings, [String]>

    /// Adds an app by bundle identifier (stable across renames and localisation), or by
    /// name when it has none.
    func add(app: AppCandidate, to list: PatternList) {
        add(pattern: app.bundleIdentifier ?? app.name, to: list)
    }

    func add(pattern raw: String, to list: PatternList) {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        guard !settings[keyPath: list].contains(where: { $0.caseInsensitiveCompare(pattern) == .orderedSame }) else { return }
        settings[keyPath: list].append(pattern)
    }

    func move(at index: Int, by delta: Int, in list: PatternList) {
        let target = index + delta
        guard settings[keyPath: list].indices.contains(index),
              settings[keyPath: list].indices.contains(target) else { return }
        settings[keyPath: list].swapAt(index, target)
    }

    func remove(at index: Int, from list: PatternList) {
        guard settings[keyPath: list].indices.contains(index) else { return }
        settings[keyPath: list].remove(at: index)
    }

    /// A friendly label for a pattern: the running app's name when the pattern is its
    /// bundle identifier, otherwise the pattern itself.
    func displayName(forPattern pattern: String) -> String {
        if let app = runningApps.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(pattern) == .orderedSame }) {
            return app.name
        }
        return pattern
    }

    /// Whether the label differs from the raw pattern (so the pattern is worth showing too).
    func isBundleIdentifierPattern(_ pattern: String) -> Bool {
        displayName(forPattern: pattern) != pattern
    }

    // MARK: Alias editing

    func addAlias(forPattern raw: String) {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        guard !settings.appAliases.contains(where: { $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame }) else { return }
        settings.appAliases.append(AppAlias(pattern: pattern, names: []))
    }

    func addAlias(for app: AppCandidate) {
        addAlias(forPattern: app.bundleIdentifier ?? app.name)
    }

    func removeAlias(withPattern pattern: String) {
        settings.appAliases.removeAll { $0.pattern == pattern }
    }

    /// Parses a comma-separated list of names into the entry with this pattern.
    func setAliasNames(forPattern pattern: String, from text: String) {
        guard let index = settings.appAliases.firstIndex(where: { $0.pattern == pattern }) else { return }
        let names = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if settings.appAliases[index].names != names {
            settings.appAliases[index].names = names
        }
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

    private var key: String { model.settings.activator.symbol }
    private var keyName: String { model.settings.activator.name }

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Switching") {
                HStack {
                    Text("Hold this key to switch:")
                    Picker("", selection: $model.settings.activator) {
                        ForEach(ActivatorModifier.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Hint("The key becomes dedicated to switching while held; its left-hand twin is unaffected. The change applies on the next press.")
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
                Toggle("Move the pointer to the window you switch to", isOn: $model.settings.movePointerToWindow)
                Hint("Happens once per hold, as soon as the switch is settled; not if the pointer is already in that window, and not after Escape.")
                Toggle("Switch Spaces instantly", isOn: $model.settings.instantSpaceSwitching)
                    .disabled(!SpaceSwitcher.isAvailable)
                Hint(SpaceSwitcher.isAvailable
                     ? "When the app’s window is on another Space, jump there without the slide animation (the InstantSpaceSwitcher technique). Relies on private macOS APIs; turn it off if a macOS update makes it misbehave."
                     : "Unavailable: this macOS does not expose the window-server calls it needs.")
            }

            SettingsGroup(title: "Pass keys through while \(keyName) is held") {
                Toggle("Let ← and → reach the system", isOn: $model.settings.passThroughLeftRightArrows)
                Hint("For \(key)← / \(key)→ Space shortcuts bound in System Settings › Keyboard › Shortcuts › Mission Control. ↑ and ↓ still cycle between matches.")
                Toggle("Let Space reach the system", isOn: $model.settings.passThroughSpace)
                Hint("For \(key)Space launchers such as Spotlight, Raycast or Alfred.")
                Toggle("Pass through keys pressed with another modifier", isOn: $model.settings.passThroughModifiedKeys)
                Hint("Lets shortcuts like \(key)⇧P reach the front app while \(keyName) is held. With this on, type app names with \(keyName) alone (Shift is no longer ignored).")
                Toggle("Let apps see \(keyName) itself", isOn: $model.settings.passThroughActivatorModifier)
                Hint("Delivers the modifier press and release, for apps that react to \(key) being held (link underlining, temporary tool modes). Leave off unless a pass-through shortcut misbehaves; it also triggers “double-tap” launchers bound to that key.")
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
                Hint("RightCmd needs Accessibility access to see the \(keyName) key and bring apps to the front.")
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
                Hint("Each app is also matched under the other names macOS has for it (its bundle file name and Info.plist names), so localised or renamed apps answer to both.")
            }

            SettingsGroup(title: "Aliases") {
                Hint("Extra names to match an app under, for apps whose name isn’t what you think of (Windows App ← “Microsoft Remote Desktop”, “RDP”). Aliases match exactly like the real name, and the overlay shows which alias matched.")
                AliasListEditor(model: model)
            }
        }
    }
}

struct PrioritiesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Priority apps") {
                Hint("Apps on this list outrank every other match, top first. They still have to match what you type; priority only settles the order.")
                PatternListEditor(model: model, list: \.priorityPatterns, emptyText: "No priority apps yet.")
            }

            SettingsGroup(title: "Deprioritized apps") {
                Hint("Apps on this list rank after every other match but stay switchable, top first. An app on both lists counts as a priority app.")
                PatternListEditor(model: model, list: \.deprioritizedPatterns, emptyText: "No deprioritized apps yet.")
            }
        }
    }
}

/// Alias entries: one row per app pattern with a comma-separated names field.
private struct AliasListEditor: View {
    @ObservedObject var model: SettingsModel
    @State private var draft: String = ""

    var body: some View {
        List {
            if model.settings.appAliases.isEmpty {
                Text("No aliases yet.")
                    .foregroundStyle(.secondary)
            }
            // Identified by pattern (unique) so a row keeps its edit state when rows above
            // it are removed.
            ForEach(model.settings.appAliases, id: \.pattern) { alias in
                AliasRow(model: model, alias: alias)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 150)

        HStack {
            Menu("Add Running App") {
                ForEach(model.runningApps, id: \.id) { app in
                    Button(app.name) { model.addAlias(for: app) }
                }
            }
            .fixedSize()
            TextField("or a name / bundle id pattern", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addDraft() }
            Button("Add") { addDraft() }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addDraft() {
        model.addAlias(forPattern: draft)
        draft = ""
    }
}

/// One alias row. The names field edits a local draft and commits on Return or when it
/// loses focus, so a comma being typed isn't normalised away mid-keystroke.
private struct AliasRow: View {
    @ObservedObject var model: SettingsModel
    let alias: AppAlias
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(forPattern: alias.pattern))
                    .lineLimit(1)
                if model.isBundleIdentifierPattern(alias.pattern) {
                    Text(alias.pattern).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 180, alignment: .leading)
            TextField("aliases, comma-separated", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Button(role: .destructive) { model.removeAlias(withPattern: alias.pattern) } label: { Image(systemName: "minus.circle") }
                .help("Remove")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
        .onAppear { text = alias.names.joined(separator: ", ") }
    }

    private func commit() {
        model.setAliasNames(forPattern: alias.pattern, from: text)
    }
}

/// An ordered list of app patterns with move/remove controls, an add-running-app menu and
/// a free-text pattern field. Used for both the priority and the deprioritized lists.
private struct PatternListEditor: View {
    @ObservedObject var model: SettingsModel
    let list: SettingsModel.PatternList
    let emptyText: String
    @State private var draft: String = ""

    private var patterns: [String] { model.settings[keyPath: list] }

    var body: some View {
        List {
            if patterns.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(patterns.enumerated()), id: \.offset) { item in
                row(index: item.offset, pattern: item.element)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 150)

        HStack {
            Menu("Add Running App") {
                ForEach(model.runningApps, id: \.id) { app in
                    Button(app.name) { model.add(app: app, to: list) }
                }
            }
            .fixedSize()
            TextField("or a name / bundle id pattern", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addDraft() }
            Button("Add") { addDraft() }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addDraft() {
        model.add(pattern: draft, to: list)
        draft = ""
    }

    private func row(index: Int, pattern: String) -> some View {
        let count = patterns.count
        return HStack(spacing: 8) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(forPattern: pattern))
                if model.isBundleIdentifierPattern(pattern) {
                    Text(pattern).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { model.move(at: index, by: -1, in: list) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
            Button { model.move(at: index, by: 1, in: list) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("Move down")
            Button(role: .destructive) { model.remove(at: index, from: list) } label: { Image(systemName: "minus.circle") }
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
                Toggle("Tint the icon while \(model.settings.activator.name) is held", isOn: $model.settings.tintMenuBarIcon)
                Hint("The colour stays for a moment after you let go, so the result of a quick switch is still visible.")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    colorRow("Listening (nothing typed yet)", \.listening)
                    colorRow("Match", \.matched)
                    colorRow("No match", \.noMatch)
                    colorRow("Passing keys through", \.passThrough)
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

    /// Called by the app when settings change anywhere, so an open window stays current.
    func settingsDidChange() {
        guard window?.isVisible == true else { return }
        model.syncFromStore()
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.addTabViewItem(makeTab("General", symbol: "gearshape", view: GeneralPane(model: model)))
        tabs.addTabViewItem(makeTab("Matching", symbol: "textformat.abc", view: MatchingPane(model: model)))
        tabs.addTabViewItem(makeTab("Priorities", symbol: "list.number", view: PrioritiesPane(model: model)))
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
