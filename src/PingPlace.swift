import ApplicationServices
import Cocoa
import os.log

final class FileDebugLogger {
    private let fileURL: URL
    private let queue: DispatchQueue = .init(label: "com.grimridge.PingPlace.FileDebugLogger")
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var path: String {
        fileURL.path
    }

    init?() {
        let logsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("PingPlace")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            fileURL = logsDirectory.appendingPathComponent("debug.log")
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
        } catch {
            return nil
        }
    }

    func log(_ message: String) {
        queue.async {
            let timestamp = self.timestampFormatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            guard let handle = try? FileHandle(forWritingTo: self.fileURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {}
        }
    }
}

class NotificationMover: NSObject, NSApplicationDelegate, NSWindowDelegate, NotificationControllerDelegate, NotificationEventHandler {
    private let notificationCenterBundleID: String = "com.apple.notificationcenterui"
    private let bannerSubroles: [String] = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXNotificationCenterNotification",
        "AXNotificationCenterBannerWindow",
    ]
    private let paddingAboveDock: CGFloat = 30
    private var statusItem: NSStatusItem?
    private var isMenuBarIconHidden: Bool = UserDefaults.standard.bool(forKey: "isMenuBarIconHidden")
    private let logger: Logger = .init(subsystem: "com.grimridge.PingPlace", category: "NotificationMover")
    private let debugMode: Bool = {
        if let explicitDebugMode = UserDefaults.standard.object(forKey: "debugMode") as? Bool {
            return explicitDebugMode
        }
        #if PINGPLACE_DEBUG_BUILD
            return true
        #else
            return false
        #endif
    }()
    private lazy var fileDebugLogger: FileDebugLogger? = debugMode ? FileDebugLogger() : nil
    private let launchAgentPlistPath: String = NSHomeDirectory() + "/Library/LaunchAgents/com.grimridge.PingPlace.plist"

    private var currentPosition: NotificationPosition = {
        guard let rawValue: String = UserDefaults.standard.string(forKey: "notificationPosition"),
              let position = NotificationPosition(rawValue: rawValue)
        else {
            return .topMiddle
        }
        return position
    }()

    private lazy var controller = NotificationController(
        delegate: self,
        scheduler: NotificationTimerScheduler(),
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 20,
        placeholderFollowUpInterval: 30,
        placeholderFollowUpLimit: 60
    )
    private lazy var eventSource = NotificationEventSource(
        notificationCenterBundleID: notificationCenterBundleID,
        handler: self,
        log: { [weak self] in self?.debugLog($0) }
    )
    private let axClient: NotificationCenterAXClient = SystemNotificationCenterAXClient()
    private let placementEngine = NotificationWindowPlacementEngine(paddingAboveDock: 30)

    func debugLog(_ message: String) {
        guard debugMode else { return }
        logger.info("\(message, privacy: .public)")
        fileDebugLogger?.log(message)
    }

    func notificationPosition() -> NotificationPosition {
        currentPosition
    }

    func applicationDidFinishLaunching(_: Notification) {
        if let debugLogPath = fileDebugLogger?.path {
            debugLog("Debug mode enabled. Writing trace file to: \(debugLogPath)")
        }
        debugLog("Application launched. \(buildIdentitySummary())")
        debugLog(screenTopologySummary())
        checkAccessibilityPermissions()
        eventSource.start()
        if !isMenuBarIconHidden {
            setupStatusItem()
        }
        moveAllNotifications(reason: "applicationDidFinishLaunching")
    }

    func applicationWillBecomeActive(_: Notification) {
        guard isMenuBarIconHidden else { return }
        isMenuBarIconHidden = false
        UserDefaults.standard.set(false, forKey: "isMenuBarIconHidden")
        setupStatusItem()
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "PingPlace needs accessibility permission to detect and move notifications.\n\nPlease grant permission in System Settings and restart the app."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSApplication.shared.terminate(nil)
            return
        }
    }

    func setupStatusItem() {
        guard !isMenuBarIconHidden else {
            statusItem = nil
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button: NSStatusBarButton = statusItem?.button, let menuBarIcon = NSImage(named: "MenuBarIcon") {
            menuBarIcon.isTemplate = true
            button.image = menuBarIcon
        }
        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        for position: NotificationPosition in NotificationPosition.allCases {
            let item = NSMenuItem(title: position.displayName, action: #selector(changePosition(_:)), keyEquivalent: "")
            item.representedObject = position
            item.state = position == currentPosition ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.state = FileManager.default.fileExists(atPath: launchAgentPlistPath) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(toggleMenuBarIcon(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let donateMenu = NSMenuItem(title: "Donate", action: nil, keyEquivalent: "")
        let donateSubmenu = NSMenu()
        donateSubmenu.addItem(NSMenuItem(title: "Ko-fi", action: #selector(openKofi), keyEquivalent: ""))
        donateSubmenu.addItem(NSMenuItem(title: "Buy Me a Coffee", action: #selector(openBuyMeACoffee), keyEquivalent: ""))
        donateMenu.submenu = donateSubmenu

        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(donateMenu)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func openKofi() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/wadegrimridge")!)
    }

    @objc private func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://www.buymeacoffee.com/wadegrimridge")!)
    }

    @objc private func toggleMenuBarIcon(_: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon"
        alert.informativeText = "The menu bar icon will be hidden. To show it again, launch PingPlace again."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isMenuBarIconHidden = true
        UserDefaults.standard.set(true, forKey: "isMenuBarIconHidden")
        statusItem = nil
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let isEnabled = FileManager.default.fileExists(atPath: launchAgentPlistPath)

        if isEnabled {
            do {
                try FileManager.default.removeItem(atPath: launchAgentPlistPath)
                sender.state = .off
            } catch {
                showError("Failed to disable launch at login: \(error.localizedDescription)")
            }
        } else {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.grimridge.PingPlace</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(Bundle.main.executablePath!)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            do {
                try plistContent.write(toFile: launchAgentPlistPath, atomically: true, encoding: .utf8)
                sender.state = .on
            } catch {
                showError("Failed to enable launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let position: NotificationPosition = sender.representedObject as? NotificationPosition else { return }
        let oldPosition: NotificationPosition = currentPosition
        currentPosition = position
        UserDefaults.standard.set(position.rawValue, forKey: "notificationPosition")

        sender.menu?.items.forEach { item in
            item.state = (item.representedObject as? NotificationPosition) == position ? .on : .off
        }

        debugLog("Position changed: \(oldPosition.displayName) → \(position.displayName)")
        moveAllNotifications(reason: "changePosition")
    }

    private enum WindowMoveResult {
        case moved
        case noBannerContainer
        case nonMovableCandidate
    }

    func moveNotification(_ window: AXUIElement) -> Bool {
        moveNotificationResult(window) == .moved
    }

    private func moveNotificationResult(_ window: AXUIElement) -> WindowMoveResult {
        guard currentPosition != .topRight else { return .nonMovableCandidate }

        let windowIdentifier = axClient.windowIdentifier(window)
        let focusedWindow = axClient.isFocused(window)
        let windowSize = axClient.size(of: window)
        let windowPosition = axClient.position(of: window)
        let bannerContainer = axClient.firstElement(root: window, targetSubroles: bannerSubroles)
        let bannerIdentifier = bannerContainer.flatMap(axClient.windowIdentifier)
        let bannerFocused = bannerContainer.map(axClient.isFocused) ?? false
        let bannerSubrole = bannerContainer.flatMap(axClient.subrole)
        let notifSize = bannerContainer.flatMap(axClient.size)
        let position = bannerContainer.flatMap(axClient.position)

        guard let resolvedWindowSize = windowSize,
              let resolvedBannerContainer = bannerContainer,
              let resolvedNotifSize = notifSize,
              let resolvedPosition = position
        else {
            let rootFingerprint = windowFingerprint(
                window: window,
                identifier: windowIdentifier,
                focused: focusedWindow,
                windowSize: windowSize,
                notifPosition: windowPosition
            )
            let bannerFingerprint = bannerContainer.map {
                elementFingerprint(
                    $0,
                    identifier: bannerIdentifier,
                    focused: bannerFocused,
                    size: notifSize,
                    position: position
                )
            } ?? "none"
            debugLog(
                "Failed to get notification dimensions or find banner container: " +
                    "root=\(rootFingerprint), " +
                    "bannerFound=\(bannerContainer != nil), " +
                    "banner=\(bannerFingerprint)"
            )
            return .noBannerContainer
        }
        let snapshot = NotificationWindowSnapshot(
            identifier: windowIdentifier,
            focused: focusedWindow,
            isNotificationCenterPanelOpen: hasNotificationCenterUI(),
            notificationSubrole: bannerSubrole,
            windowSize: resolvedWindowSize,
            notificationSize: resolvedNotifSize,
            notificationPosition: resolvedPosition
        )
        let evaluation = placementEngine.evaluateMove(
            snapshot: snapshot,
            currentPosition: currentPosition,
            screens: currentScreenDescriptors()
        )

        switch evaluation {
        case .skip(.skipPanelOpen):
            debugLog(
                "Skipping move - Notification Center panel is open: " +
                    "root=\(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow, windowSize: resolvedWindowSize, notifPosition: windowPosition)), " +
                    "banner=\(elementFingerprint(resolvedBannerContainer, identifier: bannerIdentifier, focused: bannerFocused, size: resolvedNotifSize, position: resolvedPosition))"
            )
            return .nonMovableCandidate
        case .skip(.skipWidget):
            debugLog("Skipping move - widget window detected: \(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow))")
            return .nonMovableCandidate
        case .skip(.skipFocused):
            debugLog("Skipping move - focused Notification Center window: \(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow))")
            return .nonMovableCandidate
        case .skip(.move):
            return .nonMovableCandidate
        case let .move(plan):
            if let identifiers = plan.cacheResetIdentifiers {
                let previousIdentifier = identifiers.previous ?? "none"
                let currentIdentifier = identifiers.current ?? "none"
                debugLog("Window identifier changed (\(previousIdentifier) → \(currentIdentifier)). Resetting cached geometry.")
            }

            debugLog(
                "Window candidate: " +
                    "root=\(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow, windowSize: resolvedWindowSize, notifPosition: windowPosition)), " +
                    "banner=\(elementFingerprint(resolvedBannerContainer, identifier: bannerIdentifier, focused: bannerFocused, size: resolvedNotifSize, position: resolvedPosition)), " +
                    "resolvedScreen=\(screenSummary(from: plan.resolvedScreen)), " +
                    "referenceScreen=\(screenSummary(from: plan.referenceScreen))"
            )

            if plan.initialPositionRecalculated {
                debugLog("Detected incorrect initial position.x: \(resolvedPosition.x). Recalculating position.")
            }
            if plan.cacheInitialized, let cache = placementEngine.cache {
                debugLog("Initial notification cached - size: \(cache.initialNotificationSize), position: \(cache.initialPosition), padding: \(cache.initialPadding)")
            }
            if let resetPosition = plan.resetPosition {
                axClient.setPosition(window, point: resetPosition)
            }

            let cache = placementEngine.cache!
            let dockSize = plan.referenceScreen.map(ScreenResolutionPolicy.dockSize(for:)) ?? 0
            let newPosition = calculateNewPosition(
                windowSize: cache.initialWindowSize,
                notifSize: cache.initialNotificationSize,
                position: cache.initialPosition,
                padding: cache.initialPadding,
                dockSize: dockSize
            )
            axClient.setPosition(window, point: plan.targetPosition)
            controller.noteNotificationMoved()
            debugLog(
                "Moved notification to \(currentPosition.displayName) at (\(newPosition.x), \(newPosition.y)) " +
                    "from root=\(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow, windowSize: resolvedWindowSize, notifPosition: windowPosition)), " +
                    "banner=\(elementFingerprint(resolvedBannerContainer, identifier: bannerIdentifier, focused: bannerFocused, size: resolvedNotifSize, position: resolvedPosition)), " +
                    "referenceScreen=\(screenSummary(from: plan.referenceScreen))"
            )
            return .moved
        }
    }

    @discardableResult
    func moveAllNotifications(reason: String = "manual") -> NotificationScanResult {
        guard let pid = axClient.notificationCenterProcessIdentifier(bundleID: notificationCenterBundleID) else {
            debugLog("Cannot find Notification Center process")
            return .noMovableCandidates
        }
        debugLog("moveAllNotifications triggered (\(reason)). \(screenTopologySummary())")

        guard let windows = axClient.notificationWindows(pid: pid) else {
            debugLog("Failed to get notification windows")
            return .noMovableCandidates
        }
        debugLog("Notification Center windows snapshot (\(reason)): count=\(windows.count) [\(windowInventorySummary(windows))]")

        var movedAny = false
        var foundBannerContainer = false
        for (index, window) in windows.enumerated() {
            debugLog("Inspecting Notification Center window \(index + 1)/\(windows.count): \(windowFingerprint(window: window, identifier: axClient.windowIdentifier(window), focused: axClient.isFocused(window), windowSize: axClient.size(of: window), notifPosition: axClient.position(of: window)))")
            switch moveNotificationResult(window) {
            case .moved:
                movedAny = true
                foundBannerContainer = true
            case .nonMovableCandidate:
                foundBannerContainer = true
            case .noBannerContainer:
                break
            }
        }
        debugLog("moveAllNotifications completed (\(reason)): movedAny=\(movedAny), windows=\(windows.count)")
        if movedAny {
            return .movedNotification
        }
        if !foundBannerContainer, !windows.isEmpty {
            return .placeholderOnly
        }
        return .noMovableCandidates
    }

    @objc func showAbout() {
        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow.center()
        aboutWindow.title = "About PingPlace"
        aboutWindow.delegate = self

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))

        let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let copyright: String = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

        let elements: [(NSView, CGFloat)] = [
            (createIconView(), 165),
            (createLabel("PingPlace", font: .boldSystemFont(ofSize: 16)), 110),
            (createLabel("Version \(version)"), 90),
            (createLabel("Made with <3 by Wade"), 70),
            (createTwitterButton(), 40),
            (createLabel(copyright, color: .secondaryLabelColor, size: 11), 20),
        ]

        for (view, y) in elements {
            view.frame = NSRect(x: 0, y: y, width: 300, height: 20)
            if view is NSImageView {
                view.frame = NSRect(x: 100, y: y, width: 100, height: 100)
            }
            contentView.addSubview(view)
        }

        aboutWindow.contentView = contentView
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createIconView() -> NSImageView {
        let iconImageView = NSImageView()
        if let iconImage = NSImage(named: "icon") {
            iconImageView.image = iconImage
            iconImageView.imageScaling = .scaleProportionallyDown
        }
        return iconImageView
    }

    private func createLabel(_ text: String, font: NSFont = .systemFont(ofSize: 12), color: NSColor = .labelColor, size _: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = font
        label.textColor = color
        return label
    }

    private func createTwitterButton() -> NSButton {
        let button = NSButton()
        button.title = "@WadeGrimridge"
        button.bezelStyle = .inline
        button.isBordered = false
        button.target = self
        button.action = #selector(openTwitter)
        button.attributedTitle = NSAttributedString(string: "@WadeGrimridge", attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        return button
    }

    @objc private func openTwitter() {
        NSWorkspace.shared.open(URL(string: "https://x.com/WadeGrimridge")!)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func clearCachedNotificationGeometry() {
        placementEngine.clearCache()
    }

    func hasNotificationCenterUI() -> Bool {
        guard let pid = axClient.notificationCenterProcessIdentifier(bundleID: notificationCenterBundleID) else { return false }
        return axClient.hasFocusedWindow(pid: pid)
    }

    func notificationCenterPanelSignal() -> NotificationCenterPanelSignal {
        guard let pid = axClient.notificationCenterProcessIdentifier(bundleID: notificationCenterBundleID) else {
            return NotificationCenterPanelSignal(hasFocusedWindow: false, hasWidgetUI: false)
        }
        return NotificationCenterPanelSignal(
            hasFocusedWindow: axClient.hasFocusedWindow(pid: pid),
            hasWidgetUI: axClient.hasWidgetUI(pid: pid)
        )
    }

    func notificationCenterWindowCreated(_ element: AXUIElement) {
        _ = moveNotification(element)
    }

    func notificationCenterStateMonitorTick() {
        controller.handleWidgetMonitorTick()
    }

    func screenParametersChanged() {
        DispatchQueue.main.async {
            self.controller.handleScreenConfigurationChanged()
        }
    }

    func sessionDidBecomeActive() {
        DispatchQueue.main.async {
            self.controller.handleSessionDidBecomeActive()
        }
    }

    func systemWillSleep() {
        debugLog("System will sleep. \(screenTopologySummary())")
    }

    func systemDidWake() {
        DispatchQueue.main.async {
            self.controller.handleWake()
        }
    }

    private func calculateNewPosition(
        windowSize: CGSize,
        notifSize: CGSize,
        position: CGPoint,
        padding: CGFloat,
        dockSize: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        debugLog("Calculating new position with windowSize: \(windowSize), notifSize: \(notifSize), position: \(position), padding: \(padding)")
        let result = NotificationGeometry.newPosition(
            currentPosition: currentPosition,
            windowSize: windowSize,
            notifSize: notifSize,
            position: position,
            padding: padding,
            dockSize: dockSize,
            paddingAboveDock: paddingAboveDock
        )

        debugLog("Calculated new position - x: \(result.x), y: \(result.y)")
        return result
    }

    private func currentScreenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            ScreenDescriptor(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: screen == NSScreen.main
            )
        }
    }

    private func screen(from descriptor: ScreenDescriptor?) -> NSScreen? {
        guard let descriptor else { return nil }
        return NSScreen.screens.first(where: { $0.frame == descriptor.frame && $0.visibleFrame == descriptor.visibleFrame })
    }

    private func windowFingerprint(
        window: AXUIElement,
        identifier: String?,
        focused: Bool,
        windowSize: CGSize? = nil,
        notifSize: CGSize? = nil,
        notifPosition: CGPoint? = nil,
        resolvedScreen: NSScreen? = nil
    ) -> String {
        let role = axClient.role(of: window) ?? "unknown"
        let subrole = axClient.subrole(of: window) ?? "unknown"
        return elementFingerprint(
            role: role,
            subrole: subrole,
            identifier: identifier,
            focused: focused,
            size: windowSize,
            secondarySize: notifSize,
            position: notifPosition,
            screenSummary: screenSummary(from: resolvedScreen)
        )
    }

    private func elementFingerprint(
        _ element: AXUIElement,
        identifier: String?,
        focused: Bool,
        size: CGSize? = nil,
        position: CGPoint? = nil
    ) -> String {
        let role = axClient.role(of: element) ?? "unknown"
        let subrole = axClient.subrole(of: element) ?? "unknown"
        return elementFingerprint(
            role: role,
            subrole: subrole,
            identifier: identifier,
            focused: focused,
            size: size,
            secondarySize: nil,
            position: position,
            screenSummary: "n/a"
        )
    }

    private func elementFingerprint(
        role: String,
        subrole: String,
        identifier: String?,
        focused: Bool,
        size: CGSize?,
        secondarySize: CGSize?,
        position: CGPoint?,
        screenSummary: String
    ) -> String {
        let id = identifier ?? "none"
        let sizeSummary = size.map(self.sizeSummary) ?? "n/a"
        let secondarySizeSummary = secondarySize.map(self.sizeSummary) ?? "n/a"
        let positionSummary = position.map(self.pointSummary) ?? "n/a"
        return "id=\(id),focused=\(focused),role=\(role),subrole=\(subrole),windowSize=\(sizeSummary),notifSize=\(secondarySizeSummary),notifPos=\(positionSummary),screen=\(screenSummary)"
    }

    private func windowInventorySummary(_ windows: [AXUIElement]) -> String {
        windows.enumerated().map { index, window in
            let summary = windowFingerprint(
                window: window,
                identifier: axClient.windowIdentifier(window),
                focused: axClient.isFocused(window),
                windowSize: axClient.size(of: window),
                notifPosition: axClient.position(of: window)
            )
            return "#\(index + 1){\(summary)}"
        }.joined(separator: " ")
    }

    private func screenSummary(from descriptor: ScreenDescriptor?) -> String {
        let resolvedScreen = descriptor.flatMap { screen(from: $0) }
        return screenSummary(from: resolvedScreen)
    }

    private func screenSummary(from screen: NSScreen?) -> String {
        guard let screen else { return "n/a" }
        let id = screenIdentifier(screen) ?? "unknown"
        let frame = rectSummary(screen.frame)
        let visible = rectSummary(screen.visibleFrame)
        let isMain = screen == NSScreen.main
        return "{id=\(id),main=\(isMain),frame=\(frame),visible=\(visible)}"
    }

    private func sizeSummary(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func pointSummary(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    func screenTopologySummary() -> String {
        let screensSummary = NSScreen.screens.enumerated().map { index, screen in
            let id = screenIdentifier(screen) ?? "unknown"
            let frame = rectSummary(screen.frame)
            let visibleFrame = rectSummary(screen.visibleFrame)
            let isMain = screen == NSScreen.main
            return "#\(index){id=\(id),main=\(isMain),frame=\(frame),visible=\(visibleFrame)}"
        }.joined(separator: " ")
        return "screens=[\(screensSummary)]"
    }

    private func screenIdentifier(_ screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return String(screenNumber.uint32Value)
    }

    private func rectSummary(_ rect: CGRect) -> String {
        let x = Int(rect.origin.x.rounded())
        let y = Int(rect.origin.y.rounded())
        let w = Int(rect.size.width.rounded())
        let h = Int(rect.size.height.rounded())
        return "\(x),\(y),\(w)x\(h)"
    }

    private func buildIdentitySummary() -> String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "build={version=\(shortVersion),bundle=\(bundleVersion),commit=\(GeneratedBuildInfo.gitCommit),dirty=\(GeneratedBuildInfo.gitDirtyState),builtAt=\(GeneratedBuildInfo.buildTimestamp),sourceFingerprint=\(GeneratedBuildInfo.sourceFingerprint)}"
    }

}

@main
struct PingPlaceApp {
    static func main() {
        let app: NSApplication = .shared
        let delegate: NotificationMover = .init()
        app.delegate = delegate
        app.run()
    }
}
