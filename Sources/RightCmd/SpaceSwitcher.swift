import AppKit
import CoreGraphics
import RightCmdCore
import SpaceSwitchKit

/// Everything needed to jump to the Space an app's window is on.
struct SpaceSwitchPlan {
    let displayIdentifier: String
    let move: SpaceMove
}

/// Decides whether activating an app would make macOS change Spaces, and if so jumps
/// there instantly first (see `SpaceSwitchKit`). Mirrors the system rule: no switch while
/// the app has any window on its display's current Space; otherwise go to the Space of
/// the app's frontmost window.
enum SpaceSwitcher {
    static var isAvailable: Bool { rcs_is_available() }

    static func plan(forWindowsOf pid: pid_t) -> SpaceSwitchPlan? {
        guard isAvailable else { return nil }
        let windows = normalWindowIDs(for: pid)
        guard !windows.isEmpty else { return nil }

        var locations: [RCSWindowLocation] = []
        for windowID in windows {
            var location = RCSWindowLocation()
            if rcs_locate_window(windowID, &location) {
                locations.append(location)
            }
        }
        // A window already on a current Space means activation won't move anywhere.
        guard !locations.contains(where: { $0.spaceIndex == $0.currentIndex }), let front = locations.first else {
            return nil
        }
        guard let move = SpaceSwitchPlanner.move(
            from: Int(front.currentIndex),
            to: Int(front.spaceIndex),
            count: Int(front.spaceCount)
        ) else {
            return nil
        }
        return SpaceSwitchPlan(displayIdentifier: identifier(of: front), move: move)
    }

    /// Posts the instant swipe(s). The Dock applies a swipe to the display under the
    /// pointer, so the pointer is first moved onto the target display if it isn't there.
    @discardableResult
    static func perform(_ plan: SpaceSwitchPlan) -> Bool {
        if !rcs_pointer_is_on_display(plan.displayIdentifier) {
            _ = rcs_move_pointer_to_display(plan.displayIdentifier)
        }
        let direction: RCSDirection = plan.move.direction == .right ? RCSDirectionRight : RCSDirectionLeft
        return rcs_post_space_switch(direction, UInt32(plan.move.steps))
    }

    // MARK: Helpers

    /// The app's ordinary (layer 0) windows, front to back, across all Spaces.
    private static func normalWindowIDs(for pid: pid_t) -> [CGWindowID] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID else {
                return nil
            }
            // Skip the tiny helper windows some apps keep around; they have no Space of note.
            if let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
               let width = bounds["Width"]?.doubleValue, let height = bounds["Height"]?.doubleValue,
               width < 50 || height < 50 {
                return nil
            }
            return number
        }
    }

    /// The C `char[128]` as a String: the bytes up to the first NUL, decoded as UTF-8.
    /// Reads the tuple's storage directly, so no `inout` borrow and no reliance on a
    /// terminator being present.
    private static func identifier(of location: RCSWindowLocation) -> String {
        withUnsafeBytes(of: location.displayIdentifier) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Wraps an `AppActivating` so that, when enabled and the target's window is on another
/// Space, the Space is changed instantly before the app is activated. Activation is held
/// until the window server reports the Space change (or a short timeout), because
/// activating first would make macOS start its own animated switch.
final class SpaceAwareActivator: AppActivating {
    private let base: AppActivating
    private let isEnabled: () -> Bool
    private var waiter: SpaceChangeWaiter?

    init(base: AppActivating, isEnabled: @escaping () -> Bool) {
        self.base = base
        self.isEnabled = isEnabled
    }

    @discardableResult
    func activate(_ candidate: AppCandidate) -> Bool {
        waiter?.cancel()
        waiter = nil

        guard isEnabled(), let plan = SpaceSwitcher.plan(forWindowsOf: candidate.id) else {
            return base.activate(candidate)
        }
        guard SpaceSwitcher.perform(plan) else {
            Log.activation.error("Instant Space switch could not be posted; activating normally")
            return base.activate(candidate)
        }
        Log.activation.info("Instant Space switch: \(plan.move.steps) step(s) \(plan.move.direction == .right ? "right" : "left", privacy: .public) for \(candidate.name, privacy: .public)")

        let base = self.base
        waiter = SpaceChangeWaiter(expectedChanges: plan.move.steps, timeout: 0.4) {
            base.activate(candidate)
        }
        return true
    }
}

/// Runs a completion after `expectedChanges` active-Space notifications, or after
/// `timeout`, whichever comes first. Cancelling drops the completion.
private final class SpaceChangeWaiter {
    private var observer: NSObjectProtocol?
    private var remaining: Int
    private var completion: (() -> Void)?

    init(expectedChanges: Int, timeout: TimeInterval, completion: @escaping () -> Void) {
        self.remaining = max(1, expectedChanges)
        self.completion = completion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.noteChange()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish()
        }
    }

    deinit {
        removeObserver()
    }

    func cancel() {
        completion = nil
        removeObserver()
    }

    private func noteChange() {
        remaining -= 1
        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        guard let completion else { return }
        self.completion = nil
        removeObserver()
        completion()
    }

    private func removeObserver() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
}
