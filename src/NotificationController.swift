import Foundation

protocol NotificationControllerDelegate: AnyObject {
    func debugLog(_ message: String)
    func notificationPosition() -> NotificationPosition
    func screenTopologySummary() -> String
    func clearCachedNotificationGeometry()
    @discardableResult
    func moveAllNotifications(reason: String) -> Bool
    func hasNotificationCenterUI() -> Bool
}

protocol ScheduledNotificationAction: AnyObject {
    func cancel()
}

protocol NotificationScheduler {
    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledNotificationAction
}

final class NotificationController {
    private weak var delegate: NotificationControllerDelegate?
    private let scheduler: NotificationScheduler
    private let recoveryRetryInterval: TimeInterval
    private let recoveryRetryLimit: Int

    private var recoveryRetryTask: ScheduledNotificationAction?
    private var lastWidgetWindowCount: Int = 0
    private var pollingEndTime: Date?
    private var recoveryRetryAttempt: Int = 0
    private var recoveryRetryReason: String?

    init(
        delegate: NotificationControllerDelegate,
        scheduler: NotificationScheduler,
        recoveryRetryInterval: TimeInterval,
        recoveryRetryLimit: Int
    ) {
        self.delegate = delegate
        self.scheduler = scheduler
        self.recoveryRetryInterval = recoveryRetryInterval
        self.recoveryRetryLimit = recoveryRetryLimit
    }

    func noteNotificationMoved() {
        pollingEndTime = Date().addingTimeInterval(6.5)
    }

    func handleWake() {
        guard let delegate else { return }
        delegate.debugLog("System did wake. \(delegate.screenTopologySummary())")
        delegate.clearCachedNotificationGeometry()
        delegate.debugLog("Recomputing notification placement after wake. \(delegate.screenTopologySummary())")
        triggerRecoveryReposition(reason: "didWakeNotification")
    }

    func handleScreenConfigurationChanged() {
        guard let delegate else { return }
        delegate.debugLog("Screen parameters changed notification received. \(delegate.screenTopologySummary())")
        delegate.clearCachedNotificationGeometry()
        delegate.debugLog("Recomputing notification placement after screen parameter change. \(delegate.screenTopologySummary())")
        triggerRecoveryReposition(reason: "didChangeScreenParametersNotification")
    }

    func handleWidgetMonitorTick() {
        guard let delegate else { return }

        let hasNCUI = delegate.hasNotificationCenterUI()
        let currentNCState = hasNCUI ? 1 : 0
        let stateChange = NotificationCenterStatePolicy.stateChange(
            previousState: lastWidgetWindowCount,
            isOpen: hasNCUI
        )

        switch stateChange {
        case .unchanged:
            break
        case .opened:
            delegate.debugLog("Notification Center state changed (\(lastWidgetWindowCount) → \(currentNCState)) - panel opened")
        case .closed:
            delegate.debugLog("Notification Center state changed (\(lastWidgetWindowCount) → \(currentNCState)) - panel closed, triggering move")
            if pollingEndTime == nil || Date() >= pollingEndTime! {
                pollingEndTime = Date().addingTimeInterval(6.5)
            }
            if delegate.notificationPosition() != .topRight {
                _ = delegate.moveAllNotifications(reason: "widgetMonitorTimer")
            }
        }

        lastWidgetWindowCount = currentNCState
    }

    func invalidate() {
        recoveryRetryTask?.cancel()
        recoveryRetryTask = nil
    }

    private func triggerRecoveryReposition(reason: String) {
        guard let delegate else { return }

        recoveryRetryReason = reason
        recoveryRetryAttempt = 0
        recoveryRetryTask?.cancel()

        let didMove = delegate.moveAllNotifications(reason: reason)
        scheduleRecoveryRetryIfNeeded(reason: reason, didMove: didMove)
    }

    private func scheduleRecoveryRetryIfNeeded(reason: String, didMove: Bool) {
        guard let delegate else { return }

        let action = NotificationCenterStatePolicy.recoveryRetryAction(
            didMoveNotification: didMove,
            attemptNumber: recoveryRetryAttempt,
            maxAttempts: recoveryRetryLimit
        )

        switch action {
        case .stop:
            if !didMove, recoveryRetryAttempt >= recoveryRetryLimit {
                delegate.debugLog("Recovery retry window exhausted (\(recoveryRetryAttempt)/\(recoveryRetryLimit)) for \(reason).")
            }
            recoveryRetryTask?.cancel()
            recoveryRetryTask = nil
        case .retry:
            recoveryRetryAttempt += 1
            delegate.debugLog("Scheduling recovery retry \(recoveryRetryAttempt)/\(recoveryRetryLimit) for \(reason) in \(recoveryRetryInterval)s.")
            recoveryRetryTask?.cancel()
            recoveryRetryTask = scheduler.schedule(after: recoveryRetryInterval) { [weak self] in
                guard let self, let delegate = self.delegate else { return }
                let activeReason = self.recoveryRetryReason ?? reason
                let didMoveOnRetry = delegate.moveAllNotifications(reason: "\(activeReason)-retry\(self.recoveryRetryAttempt)")
                self.scheduleRecoveryRetryIfNeeded(reason: activeReason, didMove: didMoveOnRetry)
            }
        }
    }
}
