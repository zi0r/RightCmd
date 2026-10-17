import Foundation
import os

/// Unified logging. View with:
///   log stream --predicate 'subsystem == "com.rightcmd.app"' --level debug
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.rightcmd.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let tap = Logger(subsystem: subsystem, category: "eventtap")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let activation = Logger(subsystem: subsystem, category: "activation")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}
