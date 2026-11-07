import Foundation

/// The fn key gesture rules, as a pure state machine. It sees fn down and up events and says what to do.
///
/// - Hold fn: `begin` on press, `commit` on release.
/// - Tap fn twice fast: `begin` on the first press, then `lock` on the second press (hands-free).
/// - One fn press while locked: `commit` when that press is released.
/// - One short tap with no second tap: `cancel` (nothing was said).
/// - Another modifier (⌘ ⌥ ⌃ ⇧) with fn: `cancel` while listening. fn alone is the only trigger.
/// - Any other key while fn is held or just tapped (fn+⌫, fn+arrows, fn+F-keys): `cancel`.
public struct FnGesture: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case begin
        case commit
        case cancel
        case lock
    }

    enum Phase: Equatable, Sendable {
        case idle
        /// fn is down since this time.
        case holding(since: TimeInterval)
        /// fn was tapped and released at this time. A second tap may follow.
        case tapped(at: TimeInterval)
        /// Locked, and fn is still down from the second tap.
        case lockedHeld
        case locked
        /// Locked, and fn is down to end it. `commit` comes on release.
        case endingLock
        /// Ignore everything until fn is released.
        case ignoringUntilUp
    }

    /// A press shorter than this is a tap. A longer press is a hold.
    public var holdThreshold: TimeInterval = 0.30
    /// A second tap must come within this time after the first release.
    public var doubleTapWindow: TimeInterval = 0.40

    private(set) var phase: Phase = .idle

    public init() {}

    /// True while a dictation session should be running (listening or waiting for a second tap).
    public var isActive: Bool {
        switch phase {
        case .idle, .ignoringUntilUp: false
        default: true
        }
    }

    public var isLocked: Bool {
        switch phase {
        case .lockedHeld, .locked, .endingLock: true
        default: false
        }
    }

    /// Call when the fn flag changes, or when another modifier changes while fn is down.
    public mutating func handle(fnDown: Bool, othersHeld: Bool, at time: TimeInterval) -> [Action] {
        // A tap that waited too long is over, whatever event comes next.
        var actions: [Action] = []
        if let expired = tick(at: time) { actions.append(expired) }

        switch (phase, fnDown) {
        case (.idle, true):
            if othersHeld {
                phase = .ignoringUntilUp
            } else {
                phase = .holding(since: time)
                actions.append(.begin)
            }
        case let (.holding(since), false):
            if time - since >= holdThreshold {
                phase = .idle
                actions.append(.commit)
            } else {
                phase = .tapped(at: time)
            }
        case (.holding, true):
            if othersHeld {
                phase = .ignoringUntilUp
                actions.append(.cancel)
            }
        case (.tapped, true):
            if othersHeld {
                phase = .ignoringUntilUp
                actions.append(.cancel)
            } else {
                phase = .lockedHeld
                actions.append(.lock)
            }
        case (.lockedHeld, false):
            phase = .locked
        case (.locked, true):
            phase = .endingLock
        case (.endingLock, false):
            phase = .idle
            actions.append(.commit)
        case (.ignoringUntilUp, false):
            phase = .idle
        default:
            break
        }
        return actions
    }

    /// Call when any non-modifier key goes down. fn used as part of a key chord never dictates.
    public mutating func keyPressed() -> [Action] {
        switch phase {
        case .holding:
            phase = .ignoringUntilUp
            return [.cancel]
        case .tapped:
            phase = .idle
            return [.cancel]
        default:
            return []
        }
    }

    /// Call when time passes with no key event. Ends a lone tap after the double-tap window.
    public mutating func tick(at time: TimeInterval) -> Action? {
        guard case let .tapped(at) = phase, time - at >= doubleTapWindow else { return nil }
        phase = .idle
        return .cancel
    }

    /// Time at which `tick` should be called, if a tap is waiting for a second tap.
    public var tickDeadline: TimeInterval? {
        guard case let .tapped(at) = phase else { return nil }
        return at + doubleTapWindow
    }

    public mutating func reset() {
        phase = .idle
    }
}
