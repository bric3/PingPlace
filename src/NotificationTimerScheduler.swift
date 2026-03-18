import Foundation

final class TimerNotificationAction: ScheduledNotificationAction {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

struct NotificationTimerScheduler: NotificationScheduler {
    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ScheduledNotificationAction {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
        return TimerNotificationAction(timer: timer)
    }
}
