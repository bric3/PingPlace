enum NotificationCenterStatePolicy {
    static func isPanelOpen(
        signal: NotificationCenterPanelSignal,
        wasPreviouslyOpen: Bool
    ) -> Bool {
        if signal.hasFocusedWindow {
            return true
        }
        if wasPreviouslyOpen, signal.hasWidgetUI {
            return true
        }
        return false
    }

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
        scanResult: NotificationScanResult,
        attemptNumber: Int,
        maxAttempts: Int
    ) -> RecoveryRetryAction {
        if scanResult == .movedNotification {
            return .stop
        }
        if attemptNumber >= maxAttempts {
            return .stop
        }
        return .retry
    }

    static func placeholderFollowUpAction(
        scanResult: NotificationScanResult,
        attemptNumber: Int,
        maxAttempts: Int
    ) -> RecoveryRetryAction {
        guard scanResult == .placeholderOnly else {
            return .stop
        }
        if attemptNumber >= maxAttempts {
            return .stop
        }
        return .retry
    }
}
