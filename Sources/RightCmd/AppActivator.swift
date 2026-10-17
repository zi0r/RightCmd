import AppKit
import ApplicationServices
import RightCmdCore

protocol AppActivating {
    /// Brings the app to the front. Returns false if the process is gone.
    @discardableResult
    func activate(_ candidate: AppCandidate) -> Bool
}

/// Activates an app from the background.
///
/// Since macOS 14, AppKit's cooperative activation model can ignore activation requests
/// from an app that isn't itself active, and this utility never is. Two mechanisms are
/// used together, which is what mature switchers do in practice:
///
/// 1. Accessibility: set `kAXFrontmostAttribute` on the application element and raise its
///    focused window. This process is already AX-trusted (the event tap needs it), and
///    the window server honours it regardless of which app is active.
/// 2. `NSRunningApplication.activate(options:)` as a belt-and-braces fallback. It is
///    deprecated in favour of the cooperative API but still functional; the call is wrapped
///    in a helper that is itself marked deprecated, which silences the diagnostic.
struct AccessibilityAppActivator: AppActivating {
    @discardableResult
    func activate(_ candidate: AppCandidate) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: candidate.id), !app.isTerminated else {
            Log.activation.error("Cannot activate \(candidate.name, privacy: .public): process \(candidate.id) is gone")
            return false
        }

        if app.isHidden {
            app.unhide()
        }

        let element = AXUIElementCreateApplication(candidate.id)
        let axResult = AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if axResult != .success {
            Log.activation.debug("AXFrontmost failed for \(candidate.name, privacy: .public): \(axResult.rawValue)")
        }
        raiseFocusedWindow(of: element)

        Self.legacyActivate(app)

        Log.activation.info("Activated \(candidate.name, privacy: .public) (pid \(candidate.id))")
        return true
    }

    private func raiseFocusedWindow(of element: AXUIElement) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value else { return }
        // The attribute value is an AXUIElement; the cast is a type check, not a conversion.
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    @available(macOS, deprecated: 14.0, message: "Intentional: see type documentation.")
    private static func legacyActivate(_ app: NSRunningApplication) {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
