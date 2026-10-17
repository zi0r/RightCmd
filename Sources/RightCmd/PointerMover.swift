import AppKit
import ApplicationServices
import RightCmdCore

/// Moves the pointer into the window of an app that was just switched to.
///
/// The window frame comes from Accessibility (`kAXFocusedWindowAttribute`, then main, then
/// the first window), in the top-left-origin screen coordinates that CoreGraphics also uses
/// for the pointer, so no conversion is needed. The move is skipped when the app has no
/// usable window, the window is minimised, or the pointer is already inside it.
enum PointerMover {
    @discardableResult
    static func centerPointer(inWindowOf candidate: AppCandidate) -> Bool {
        let app = AXUIElementCreateApplication(candidate.id)
        // AX calls block on the target; keep a hung app from stalling the main thread.
        _ = AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = frontWindow(of: app) else {
            Log.activation.debug("No window to point at for \(candidate.name, privacy: .public)")
            return false
        }
        if boolAttribute(kAXMinimizedAttribute, of: window) == true {
            return false
        }
        guard let frame = frame(of: window), frame.width > 0, frame.height > 0 else {
            return false
        }

        if let current = CGEvent(source: nil)?.location, frame.contains(current) {
            return false   // already there; a jump would only be noise
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        move(to: center)
        Log.activation.info("Pointer moved to \(candidate.name, privacy: .public) window center")
        return true
    }

    // MARK: Windows

    private static func frontWindow(of app: AXUIElement) -> AXUIElement? {
        if let focused = elementAttribute(kAXFocusedWindowAttribute, of: app) { return focused }
        if let main = elementAttribute(kAXMainWindowAttribute, of: app) { return main }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return nil }
        return list.first
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = axValue(kAXPositionAttribute, of: window, type: .cgPoint, initial: .zero),
              let size: CGSize = axValue(kAXSizeAttribute, of: window, type: .cgSize, initial: .zero) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: AX helpers

    private static func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    private static func axValue<T>(_ attribute: String, of element: AXUIElement, type: AXValueType, initial: T) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == type else { return nil }
        var result = initial
        guard AXValueGetValue(axValue, type, &result) else { return nil }
        return result
    }

    // MARK: Pointer

    private static func move(to point: CGPoint) {
        // Warp places the cursor; re-associating cancels the brief input suppression that
        // follows a warp; the posted move event lets apps update hover state.
        _ = CGWarpMouseCursorPosition(point)
        _ = CGAssociateMouseAndMouseCursorPosition(1)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
}
