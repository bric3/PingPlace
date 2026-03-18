enum NotificationCenterStatePolicy {
    static func stateChange(
        previousState: Int,
        isOpen: Bool
    ) -> NotificationCenterStateChange {
        let currentState = isOpen ? 1 : 0
        guard previousState != currentState else {
            return .unchanged
        }
        return isOpen ? .opened : .closed
    }

    static func recoveryRetryAction(
        didMoveNotification: Bool,
        attemptNumber: Int,
        maxAttempts: Int
    ) -> RecoveryRetryAction {
        if didMoveNotification {
            return .stop
        }
        if attemptNumber >= maxAttempts {
            return .stop
        }
        return .retry
    }
}
