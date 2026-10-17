import Foundation

/// Direction of travel along a display's row of Spaces.
public enum SpaceDirection: Equatable, Sendable {
    /// Towards lower indices.
    case left
    /// Towards higher indices.
    case right
}

/// How to get from the current Space to a target Space on the same display.
public struct SpaceMove: Equatable, Sendable {
    public let direction: SpaceDirection
    public let steps: Int

    public init(direction: SpaceDirection, steps: Int) {
        self.direction = direction
        self.steps = steps
    }
}

/// Pure arithmetic for the instant Space switch, kept here so it is unit tested; the
/// app layer supplies the indices from the window server and posts the gestures.
public enum SpaceSwitchPlanner {
    /// A move from `current` to `target` within a display that has `count` Spaces, or nil
    /// when no move is needed or the indices are not valid for that display.
    public static func move(from current: Int, to target: Int, count: Int) -> SpaceMove? {
        guard count > 0, (0..<count).contains(current), (0..<count).contains(target) else { return nil }
        guard current != target else { return nil }
        if target > current {
            return SpaceMove(direction: .right, steps: target - current)
        }
        return SpaceMove(direction: .left, steps: current - target)
    }
}
