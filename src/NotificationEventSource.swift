import ApplicationServices
import Cocoa

protocol NotificationEventHandler: AnyObject {
    func notificationCenterWindowCreated(_ element: AXUIElement)
    func notificationCenterStateMonitorTick()
    func screenParametersChanged()
    func sessionDidBecomeActive()
    func systemWillSleep()
    func systemDidWake()
}

final class NotificationEventSource {
    private let notificationCenterBundleID: String
    private weak var handler: NotificationEventHandler?
    private let log: (String) -> Void

    private var axObserver: AXObserver?
    private var widgetMonitorTimer: Timer?
    private var screenParametersObserver: NSObjectProtocol?
    private var sessionDidBecomeActiveObserver: NSObjectProtocol?
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?

    init(
        notificationCenterBundleID: String,
        handler: NotificationEventHandler,
        log: @escaping (String) -> Void
    ) {
        self.notificationCenterBundleID = notificationCenterBundleID
        self.handler = handler
        self.log = log
    }

    deinit {
        stop()
    }

    func start() {
        setupAXObserver()
        setupWidgetMonitor()
        setupScreenChangeObserver()
        setupSessionActivityObservers()
        setupSleepWakeObservers()
    }

    func stop() {
        widgetMonitorTimer?.invalidate()
        widgetMonitorTimer = nil

        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        if let sessionDidBecomeActiveObserver {
            workspaceNotificationCenter.removeObserver(sessionDidBecomeActiveObserver)
            self.sessionDidBecomeActiveObserver = nil
        }
        if let willSleepObserver {
            workspaceNotificationCenter.removeObserver(willSleepObserver)
            self.willSleepObserver = nil
        }
        if let didWakeObserver {
            workspaceNotificationCenter.removeObserver(didWakeObserver)
            self.didWakeObserver = nil
        }

        axObserver = nil
    }

    private func setupAXObserver() {
        guard let pid = notificationCenterProcessIdentifier() else {
            log("Failed to setup observer - Notification Center not found")
            return
        }

        let app = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        AXObserverCreate(pid, eventSourceObserverCallback, &observer)
        guard let observer else {
            log("Failed to setup observer - AXObserverCreate returned nil")
            return
        }

        axObserver = observer
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

        log("Observer setup complete for Notification Center (PID: \(pid))")
    }

    private func setupWidgetMonitor() {
        widgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.handler?.notificationCenterStateMonitorTick()
        }
    }

    private func setupScreenChangeObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.screenParametersChanged()
        }
    }

    private func setupSleepWakeObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        willSleepObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.systemWillSleep()
        }

        didWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.systemDidWake()
        }
    }

    private func setupSessionActivityObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        sessionDidBecomeActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.sessionDidBecomeActive()
        }
    }

    private func notificationCenterProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier
    }

    fileprivate func handleAXWindowCreated(_ element: AXUIElement) {
        handler?.notificationCenterWindowCreated(element)
    }
}

private func eventSourceObserverCallback(observer _: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?) {
    guard notification as String == kAXWindowCreatedNotification as String,
          let context else {
        return
    }

    let eventSource = Unmanaged<NotificationEventSource>.fromOpaque(context).takeUnretainedValue()
    eventSource.handleAXWindowCreated(element)
}
