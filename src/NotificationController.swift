import Foundation

protocol NotificationControllerDelegate: AnyObject {
    func debugLog(_ message: String)
    func notificationPosition() -> NotificationPosition
    func notificationDisplayTarget() -> NotificationDisplayTarget
    func screenTopologySummary() -> String
    func clearCachedNotificationGeometry()
    @discardableResult
    func moveAllNotifications(reason: String) -> NotificationScanResult
    func notificationCenterPanelSignal() -> NotificationCenterPanelSignal
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
    private let placeholderFollowUpInterval: TimeInterval
    private let placeholderFollowUpLimit: Int

    private var recoveryRetryTask: ScheduledNotificationAction?
    private var placeholderFollowUpTask: ScheduledNotificationAction?
    private var lastWidgetWindowCount: Int = 0
    private var pollingEndTime: Date?
    private var recoveryRetryAttempt: Int = 0
    private var recoveryRetryReason: String?
    private var placeholderFollowUpAttempt: Int = 0
    private var placeholderFollowUpReason: String?

    init(
        delegate: NotificationControllerDelegate,
        scheduler: NotificationScheduler,
        recoveryRetryInterval: TimeInterval,
        recoveryRetryLimit: Int,
        placeholderFollowUpInterval: TimeInterval = 30,
        placeholderFollowUpLimit: Int = 60
    ) {
        self.delegate = delegate
        self.scheduler = scheduler
        self.recoveryRetryInterval = recoveryRetryInterval
        self.recoveryRetryLimit = recoveryRetryLimit
        self.placeholderFollowUpInterval = placeholderFollowUpInterval
        self.placeholderFollowUpLimit = placeholderFollowUpLimit
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

    func handleSessionDidBecomeActive() {
        guard let delegate else { return }
        delegate.debugLog("User session became active. \(delegate.screenTopologySummary())")
        delegate.clearCachedNotificationGeometry()
        delegate.debugLog("Recomputing notification placement after session activation. \(delegate.screenTopologySummary())")
        triggerRecoveryReposition(reason: "sessionDidBecomeActiveNotification")
    }

    func handleWidgetMonitorTick() {
        guard let delegate else { return }

        let hasNCUI = NotificationCenterStatePolicy.isPanelOpen(
            signal: delegate.notificationCenterPanelSignal(),
            wasPreviouslyOpen: lastWidgetWindowCount > 0
        )
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
            if shouldMoveForCurrentDisplayTarget(delegate) {
                triggerRecoveryReposition(reason: "notificationCenterClosed")
            }
        }

        lastWidgetWindowCount = currentNCState
    }

    private func shouldMoveForCurrentDisplayTarget(_ delegate: NotificationControllerDelegate) -> Bool {
        !(delegate.notificationPosition() == .topRight && delegate.notificationDisplayTarget() == .mainDisplay)
    }

    func invalidate() {
        recoveryRetryTask?.cancel()
        recoveryRetryTask = nil
        placeholderFollowUpTask?.cancel()
        placeholderFollowUpTask = nil
    }

    private func triggerRecoveryReposition(reason: String) {
        guard let delegate else { return }

        recoveryRetryReason = reason
        recoveryRetryAttempt = 0
        recoveryRetryTask?.cancel()
        placeholderFollowUpReason = nil
        placeholderFollowUpAttempt = 0
        placeholderFollowUpTask?.cancel()

        let scanResult = delegate.moveAllNotifications(reason: reason)
        scheduleRecoveryRetryIfNeeded(reason: reason, scanResult: scanResult)
    }

    private func scheduleRecoveryRetryIfNeeded(reason: String, scanResult: NotificationScanResult) {
        guard let delegate else { return }

        let action = NotificationCenterStatePolicy.recoveryRetryAction(
            scanResult: scanResult,
            attemptNumber: recoveryRetryAttempt,
            maxAttempts: recoveryRetryLimit
        )

        switch action {
        case .stop:
            if scanResult != .movedNotification, recoveryRetryAttempt >= recoveryRetryLimit {
                delegate.debugLog("Recovery retry window exhausted (\(recoveryRetryAttempt)/\(recoveryRetryLimit)) for \(reason).")
            }
            recoveryRetryTask?.cancel()
            recoveryRetryTask = nil
            schedulePlaceholderFollowUpIfNeeded(reason: reason, scanResult: scanResult)
        case .retry:
            recoveryRetryAttempt += 1
            delegate.debugLog("Scheduling recovery retry \(recoveryRetryAttempt)/\(recoveryRetryLimit) for \(reason) in \(recoveryRetryInterval)s.")
            recoveryRetryTask?.cancel()
            recoveryRetryTask = scheduler.schedule(after: recoveryRetryInterval) { [weak self] in
                guard let self, let delegate = self.delegate else { return }
                let activeReason = self.recoveryRetryReason ?? reason
                let scanResultOnRetry = delegate.moveAllNotifications(reason: "\(activeReason)-retry\(self.recoveryRetryAttempt)")
                self.scheduleRecoveryRetryIfNeeded(reason: activeReason, scanResult: scanResultOnRetry)
            }
        }
    }

    private func schedulePlaceholderFollowUpIfNeeded(reason: String, scanResult: NotificationScanResult) {
        guard let delegate else { return }

        let action = NotificationCenterStatePolicy.placeholderFollowUpAction(
            scanResult: scanResult,
            attemptNumber: placeholderFollowUpAttempt,
            maxAttempts: placeholderFollowUpLimit
        )

        switch action {
        case .stop:
            if scanResult == .placeholderOnly, placeholderFollowUpAttempt >= placeholderFollowUpLimit {
                delegate.debugLog("Placeholder follow-up window exhausted (\(placeholderFollowUpAttempt)/\(placeholderFollowUpLimit)) for \(reason).")
            }
            placeholderFollowUpTask?.cancel()
            placeholderFollowUpTask = nil
        case .retry:
            placeholderFollowUpAttempt += 1
            placeholderFollowUpReason = reason
            delegate.debugLog("Scheduling placeholder follow-up \(placeholderFollowUpAttempt)/\(placeholderFollowUpLimit) for \(reason) in \(placeholderFollowUpInterval)s.")
            placeholderFollowUpTask?.cancel()
            placeholderFollowUpTask = scheduler.schedule(after: placeholderFollowUpInterval) { [weak self] in
                guard let self, let delegate = self.delegate else { return }
                let activeReason = self.placeholderFollowUpReason ?? reason
                let scanResultOnFollowUp = delegate.moveAllNotifications(reason: "\(activeReason)-followup\(self.placeholderFollowUpAttempt)")
                self.schedulePlaceholderFollowUpIfNeeded(reason: activeReason, scanResult: scanResultOnFollowUp)
            }
        }
    }
}
