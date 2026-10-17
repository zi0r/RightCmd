import AppKit
import RightCmdCore
import SwiftUI

protocol OverlayPresenting: AnyObject {
    var position: OverlayPosition { get set }
    func show(_ state: OverlayState)
    func hide()
}

/// The overlay content. A plain value view (no `ObservableObject`) so that assigning it as
/// the hosting view's `rootView` updates synchronously and `fittingSize` is correct for the
/// state just shown, rather than one keystroke behind.
struct OverlayView: View {
    let state: OverlayState
    let icon: (AppCandidate) -> NSImage?

    private let maxVisibleMatches = 5

    var body: some View {
        VStack(spacing: 10) {
            Text(state.query.isEmpty ? "…" : state.query.uppercased())
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 420)

            if state.secureInputActive {
                Label("Secure input is on — keystrokes can’t be read", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !state.query.isEmpty {
                if state.matches.isEmpty {
                    Text("No matching app")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    matchList
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(minWidth: 260)
        .fixedSize()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var matchList: some View {
        let visible = Array(state.matches.prefix(maxVisibleMatches).enumerated())
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(visible, id: \.element.id) { item in
                matchRow(
                    item.element,
                    isSelected: item.offset == state.selectedIndex,
                    isPrioritized: state.prioritizedIDs.contains(item.element.id),
                    isDeprioritized: state.deprioritizedIDs.contains(item.element.id)
                )
            }
            if state.matches.count > maxVisibleMatches {
                Text("+\(state.matches.count - maxVisibleMatches) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
    }

    private func matchRow(_ app: AppCandidate, isSelected: Bool, isPrioritized: Bool, isDeprioritized: Bool) -> some View {
        HStack(spacing: 10) {
            if let image = icon(app) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 28, height: 28)
            }
            Text(app.name)
                .font(isSelected ? Font.title3.weight(.semibold) : Font.title3)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360, alignment: .leading)
            if isPrioritized {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("On your priority list")
            } else if isDeprioritized {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("On your deprioritized list")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .opacity(isSelected ? 1 : 0.6)
    }
}

/// A non-activating, click-through panel that floats above everything, on every Space.
final class OverlayPanel: OverlayPresenting {
    var position: OverlayPosition = .center

    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayView>
    private var iconCache: [Int32: NSImage] = [:]

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true

        let empty = OverlayState(query: "", matches: [], selectedIndex: nil, secureInputActive: false)
        hostingView = NSHostingView(rootView: OverlayView(state: empty, icon: { _ in nil }))
        panel.contentView = hostingView
    }

    func show(_ state: OverlayState) {
        pruneIconCache(keeping: state.matches)
        hostingView.rootView = OverlayView(state: state, icon: { [weak self] in self?.icon(for: $0) })

        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = NSRect(origin: origin(for: size), size: size)
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: Icons

    private func icon(for candidate: AppCandidate) -> NSImage? {
        if let cached = iconCache[candidate.id] { return cached }
        guard let app = NSRunningApplication(processIdentifier: candidate.id), let image = app.icon else {
            return nil
        }
        iconCache[candidate.id] = image
        return image
    }

    private func pruneIconCache(keeping candidates: [AppCandidate]) {
        let keep = Set(candidates.map(\.id))
        iconCache = iconCache.filter { keep.contains($0.key) }
    }

    // MARK: Placement

    /// The screen the user is working on: the one under the pointer, like Spotlight.
    /// `NSScreen.main` would be wrong here because this process never has a key window.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func origin(for size: NSSize) -> NSPoint {
        guard let screen = targetScreen() else { return .zero }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let margin: CGFloat = 40
        let y: CGFloat
        switch position {
        case .center:
            // Slightly above true center reads better, like Spotlight.
            y = visible.midY - size.height / 2 + visible.height * 0.12
        case .top:
            y = visible.maxY - size.height - margin
        case .bottom:
            y = visible.minY + margin
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}
