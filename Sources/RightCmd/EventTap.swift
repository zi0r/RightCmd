import CoreGraphics
import Foundation
import RightCmdCore

/// A keyboard event seen by the tap, reduced to what the switcher needs.
enum TapEvent {
    case flagsChanged(keyCode: Int64, flags: ModifierFlags)
    case keyDown(keyCode: Int64, flags: ModifierFlags, isRepeat: Bool)
    case keyUp(keyCode: Int64, flags: ModifierFlags)
    /// macOS disabled the tap (timeout or user input). It has already been re-enabled;
    /// the handler should drop any in-progress session.
    case tapDisabled
}

enum EventTapError: LocalizedError {
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return "Could not create the keyboard event tap. If Accessibility is already granted, remove RightCmd from the Accessibility list and add it again; the app’s code signature has probably changed."
        }
    }
}

/// An active session-level event tap for key down/up and modifier changes.
///
/// The handler returns `true` to swallow an event (it never reaches other apps) or
/// `false` to pass it through. The callback runs on the main thread because the tap's
/// run loop source is added to the main run loop. Keep the handler fast: macOS disables
/// taps that take too long, so anything heavy is dispatched asynchronously by the caller.
final class KeyboardEventTap {
    typealias Handler = (TapEvent) -> Bool

    private let handler: Handler
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        guard port == nil else { return }

        let mask: CGEventMask =
            Self.mask(for: .keyDown) | Self.mask(for: .keyUp) | Self.mask(for: .flagsChanged)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyboardEventTap.callback,
            userInfo: userInfo
        ) else {
            throw EventTapError.creationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.runLoopSource = source
        Log.tap.info("Event tap started")
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.runLoopSource = nil
        Log.tap.info("Event tap stopped")
    }

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    /// C callback trampoline. Must not capture anything; the instance comes via `userInfo`.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<KeyboardEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        let swallow = tap.process(type: type, event: event)
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// Returns true to swallow the event.
    private func process(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.tap.warning("Event tap was disabled by the system (\(type.rawValue)); re-enabling")
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            _ = handler(.tapDisabled)
            return false

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            return handler(.flagsChanged(keyCode: keyCode, flags: ModifierFlags(rawValue: event.flags.rawValue)))

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return handler(.keyDown(keyCode: keyCode, flags: ModifierFlags(rawValue: event.flags.rawValue), isRepeat: isRepeat))

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            return handler(.keyUp(keyCode: keyCode, flags: ModifierFlags(rawValue: event.flags.rawValue)))

        default:
            return false
        }
    }
}
