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
    private let runtimeConfiguration = PingPlaceRuntimeConfiguration.detect(
        arguments: CommandLine.arguments,
        environment: ProcessInfo.processInfo.environment
    )
    private var launchMode: PingPlaceLaunchMode { runtimeConfiguration.launchMode }
    private lazy var settings = PingPlaceSettings(source: runtimeConfiguration.settingsSource)
    private lazy var isMenuBarIconHidden: Bool = settings.bool(forKey: .isMenuBarIconHidden)
    private let logger: Logger = .init(subsystem: "com.grimridge.PingPlace", category: "NotificationMover")
    private lazy var debugMode: Bool = {
        if let explicitDebugMode = settings.object(forKey: .debugMode) as? Bool {
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
    private let isPortableMac = MachineModelPolicy.currentModelIdentifier().map { MachineModelPolicy.isPortableMac(modelIdentifier: $0) } ?? false
    private weak var displayTargetPickerView: NotificationDisplayTargetPickerView?
    private weak var positionPickerView: NotificationPositionPickerView?
    private var instanceTerminationObserver: NSObjectProtocol?
    private var settingsFileWatchTimer: Timer?
    private var settingsFileLastModifiedAt: Date?

    private lazy var currentPosition: NotificationPosition = {
        guard let rawValue: String = settings.string(forKey: .notificationPosition),
              let position = NotificationPosition(rawValue: rawValue)
        else {
            return .topMiddle
        }
        return position
    }()
    private lazy var currentDisplayTarget: NotificationDisplayTarget = {
        guard let rawValue = settings.string(forKey: .notificationDisplayTarget),
              let target = NotificationDisplayTarget(rawValue: rawValue)
        else {
            return .mainDisplay
        }
        return target
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

    func notificationDisplayTarget() -> NotificationDisplayTarget {
        effectiveDisplayTarget()
    }

    func applicationDidFinishLaunching(_: Notification) {
        if let debugLogPath = fileDebugLogger?.path {
            debugLog("Debug mode enabled. Writing trace file to: \(debugLogPath)")
        }
        debugLog("Application launched. \(buildIdentitySummary())")
        switch runtimeConfiguration.settingsSource {
        case let .suite(name):
            debugLog("Using settings suite: \(name)")
        case let .file(url):
            debugLog("Using settings file: \(url.path)")
        case .standard:
            break
        }
        debugLog(screenTopologySummary())
        terminatePreviousInstanceIfNeeded()
        registerInstanceTerminationObserver()
        if launchMode == .menuPreview {
            debugLog("Menu preview mode enabled. Accessibility checks, event listeners, settings writes, and notification moves are disabled.")
        } else {
            checkAccessibilityPermissions()
            eventSource.start()
        }
        if launchMode == .menuPreview || !isMenuBarIconHidden {
            setupStatusItem()
        }
        startSettingsFileWatchIfNeeded()
        if launchMode != .menuPreview {
            moveAllNotifications(reason: "applicationDidFinishLaunching")
        }
    }

    func applicationWillBecomeActive(_: Notification) {
        guard isMenuBarIconHidden else { return }
        isMenuBarIconHidden = false
        settings.set(false, forKey: .isMenuBarIconHidden)
        syncSettingsFileWatchState()
        setupStatusItem()
    }

    func applicationWillTerminate(_: Notification) {
        if let instanceTerminationObserver {
            DistributedNotificationCenter.default().removeObserver(instanceTerminationObserver)
            self.instanceTerminationObserver = nil
        }
        settingsFileWatchTimer?.invalidate()
        settingsFileWatchTimer = nil
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
            if launchMode == .menuPreview {
                button.toolTip = "PingPlace Preview"
            } else if launchMode == .smokeTest {
                button.toolTip = "PingPlace Smoke Test"
            }
        }
        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        let screens = currentScreenDescriptors()
        let showsDisplaySelector = NotificationDisplayTargetPolicy.showsDisplaySelector(
            isPortableMac: isPortableMac,
            screens: screens
        )

        if launchMode == .menuPreview {
            let previewInfoItem = NSMenuItem(title: "Preview", action: nil, keyEquivalent: "")
            previewInfoItem.isEnabled = false
            menu.addItem(previewInfoItem)
            // AppKit menu width is driven by the widest item title, so this explanatory line widens the preview menu.
            let previewDetailItem = NSMenuItem(title: "Selections stay local to this preview.", action: nil, keyEquivalent: "")
            previewDetailItem.isEnabled = false
            menu.addItem(previewDetailItem)
            menu.addItem(NSMenuItem.separator())
        } else if launchMode == .smokeTest {
            let smokeTestInfoItem = NSMenuItem(title: "Smoke Test", action: nil, keyEquivalent: "")
            smokeTestInfoItem.isEnabled = false
            menu.addItem(smokeTestInfoItem)
            let smokeTestDetailItem = NSMenuItem(title: "Selections stay local to this smoke test.", action: nil, keyEquivalent: "")
            smokeTestDetailItem.isEnabled = false
            menu.addItem(smokeTestDetailItem)
            menu.addItem(NSMenuItem.separator())
        }

        let positionSectionTitleItem = NSMenuItem(
            title: NotificationDisplayTargetPolicy.sectionTitle(
                isPortableMac: isPortableMac,
                screens: screens
            ),
            action: nil,
            keyEquivalent: ""
        )
        positionSectionTitleItem.isEnabled = false
        menu.addItem(positionSectionTitleItem)

        if showsDisplaySelector {
            let displayTargetPickerItem = NSMenuItem()
            let pickerView = NotificationDisplayTargetPickerView(selectedTarget: currentDisplayTarget) { [weak self] target in
                self?.setDisplayTarget(target)
            }
            displayTargetPickerItem.view = pickerView
            displayTargetPickerItem.isEnabled = true
            displayTargetPickerView = pickerView
            menu.addItem(displayTargetPickerItem)
        }

        let positionPickerItem = NSMenuItem()
        let pickerView = NotificationPositionPickerView(selectedPosition: currentPosition) { [weak self] position in
            self?.setPosition(position)
        }
        positionPickerItem.view = pickerView
        positionPickerItem.isEnabled = true
        positionPickerView = pickerView
        menu.addItem(positionPickerItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.state = FileManager.default.fileExists(atPath: launchAgentPlistPath) ? .on : .off
        if launchMode == .menuPreview {
            launchItem.action = #selector(handlePreviewOnlyAction(_:))
        }
        menu.addItem(launchItem)

        let hideMenuBarIconItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(toggleMenuBarIcon(_:)), keyEquivalent: "")
        if launchMode == .menuPreview {
            hideMenuBarIconItem.action = #selector(handlePreviewOnlyAction(_:))
        }
        menu.addItem(hideMenuBarIconItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        let quitTitle: String
        switch launchMode {
        case .menuPreview:
            quitTitle = "Quit Preview"
        case .smokeTest:
            quitTitle = "Quit Smoke Test"
        case .full:
            quitTitle = "Quit"
        }
        menu.addItem(NSMenuItem(title: quitTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private func terminatePreviousInstanceIfNeeded() {
        DistributedNotificationCenter.default().postNotificationName(
            PingPlaceInstanceIPC.terminateInstanceNotification,
            object: nil,
            userInfo: PingPlaceInstanceIPC.terminationUserInfo(
                senderProcessID: ProcessInfo.processInfo.processIdentifier,
                launchMode: launchMode
            ),
            deliverImmediately: true
        )
    }

    private func registerInstanceTerminationObserver() {
        instanceTerminationObserver = DistributedNotificationCenter.default().addObserver(
            forName: PingPlaceInstanceIPC.terminateInstanceNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard PingPlaceInstanceIPC.shouldTerminateInstance(
                currentProcessID: ProcessInfo.processInfo.processIdentifier,
                currentLaunchMode: self?.launchMode ?? .full,
                userInfo: notification.userInfo
            ) else {
                return
            }
            let modeDescription: String
            switch self?.launchMode {
            case .menuPreview:
                modeDescription = "preview"
            case .smokeTest:
                modeDescription = "smoke-test"
            case .full, .none:
                modeDescription = "regular"
            }
            self?.debugLog("Another \(modeDescription) PingPlace instance started. Terminating this instance.")
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func toggleMenuBarIcon(_: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon"
        alert.informativeText = "The menu bar icon will be hidden. To show it again, launch PingPlace again."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isMenuBarIconHidden = true
        settings.set(true, forKey: .isMenuBarIconHidden)
        syncSettingsFileWatchState()
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

    @objc private func handlePreviewOnlyAction(_ sender: NSMenuItem) {
        debugLog("Preview-only menu action selected: \(sender.title)")
    }

    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let position: NotificationPosition = sender.representedObject as? NotificationPosition else { return }
        setPosition(position)
    }

    private func setPosition(_ position: NotificationPosition) {
        let oldPosition = currentPosition
        currentPosition = position
        positionPickerView?.selectedPosition = position
        if launchMode == .menuPreview {
            debugLog("Preview position changed: \(oldPosition.displayName) → \(position.displayName)")
            return
        }

        settings.set(position.rawValue, forKey: .notificationPosition)
        syncSettingsFileWatchState()
        debugLog("Position changed: \(oldPosition.displayName) → \(position.displayName)")
        moveAllNotifications(reason: "changePosition")
    }

    private func setDisplayTarget(_ target: NotificationDisplayTarget) {
        let oldTarget = currentDisplayTarget
        currentDisplayTarget = target
        displayTargetPickerView?.selectedTarget = target

        if launchMode == .menuPreview {
            debugLog("Preview display target changed: \(oldTarget.displayName) → \(target.displayName)")
            return
        }

        settings.set(target.rawValue, forKey: .notificationDisplayTarget)
        syncSettingsFileWatchState()
        let effectiveTarget = effectiveDisplayTarget()
        if effectiveTarget == target {
            debugLog("Display target changed: \(oldTarget.displayName) → \(target.displayName)")
        } else {
            debugLog(
                "Display target changed: \(oldTarget.displayName) → \(target.displayName) " +
                    "(effective: \(effectiveTarget.displayName))"
            )
        }
        clearCachedNotificationGeometry()
        moveAllNotifications(reason: "changeDisplayTarget")
    }

    private enum WindowMoveResult {
        case moved(needsSettleFollowUp: Bool)
        case noBannerContainer
        case nonMovableCandidate
    }

    func moveNotification(_ window: AXUIElement) -> Bool {
        if case .moved = moveNotificationResult(window) {
            return true
        }
        return false
    }

    private func moveNotificationResult(_ window: AXUIElement) -> WindowMoveResult {
        let requestedDisplayTarget = currentDisplayTarget
        let displayTarget = effectiveDisplayTarget()
        guard currentPosition != .topRight || displayTarget != .mainDisplay else { return .nonMovableCandidate }

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
            rootWindowPosition: windowPosition ?? .zero,
            windowSize: resolvedWindowSize,
            notificationSize: resolvedNotifSize,
            notificationPosition: resolvedPosition
        )
        let evaluation = placementEngine.evaluateMove(
            snapshot: snapshot,
            currentPosition: currentPosition,
            displayTarget: displayTarget,
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
                    "requestedTarget=\(requestedDisplayTarget.displayName), " +
                    "effectiveTarget=\(displayTarget.displayName), " +
                    "root=\(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow, windowSize: resolvedWindowSize, notifPosition: windowPosition)), " +
                    "banner=\(elementFingerprint(resolvedBannerContainer, identifier: bannerIdentifier, focused: bannerFocused, size: resolvedNotifSize, position: resolvedPosition)), " +
                    "resolvedScreen=\(screenSummary(from: plan.resolvedScreen)), " +
                    "referenceScreen=\(screenSummary(from: plan.referenceScreen)), " +
                    "targetPosition=\(pointSummary(plan.targetPosition)), " +
                    "targetBannerPosition=\(pointSummary(plan.targetBannerPosition))"
            )

            if plan.initialPositionRecalculated {
                debugLog("Detected incorrect initial position.x: \(resolvedPosition.x). Recalculating position.")
            }
            if plan.cacheInitialized, let cache = placementEngine.cache {
                debugLog("Initial notification cached - size: \(cache.initialNotificationSize), position: \(cache.initialPosition), padding: \(cache.initialPadding)")
            }
            let cache = placementEngine.cache!
            let dockSize = plan.referenceScreen.map(ScreenResolutionPolicy.dockSize(for:)) ?? 0
            let newPosition = calculateNewPosition(
                windowSize: plan.referenceScreen?.frame.size ?? cache.initialWindowSize,
                notifSize: cache.initialNotificationSize,
                position: cache.initialPosition,
                padding: cache.initialPadding,
                dockSize: dockSize
            )
            var movedElementSummary: String
            let bannerMoveResult = axClient.setPosition(resolvedBannerContainer, point: plan.targetBannerPosition)
            var postMoveRootPosition = axClient.position(of: window)
            var postMoveBannerPosition = axClient.position(of: resolvedBannerContainer)
            let bannerMoveApplied = bannerMoveResult == .success &&
                postMoveBannerPosition.map { bannerPosition in
                    abs(bannerPosition.x - plan.targetBannerPosition.x) < 1 &&
                    abs(bannerPosition.y - plan.targetBannerPosition.y) < 1
                } == true

            if bannerMoveApplied {
                movedElementSummary = "banner"
            } else {
                let fallbackReason = "banner:\(bannerMoveResult.rawValue)"
                _ = axClient.setPosition(window, point: plan.targetPosition)
                postMoveRootPosition = axClient.position(of: window)
                postMoveBannerPosition = axClient.position(of: resolvedBannerContainer)
                movedElementSummary = "root(fallback:\(fallbackReason))"

                if let currentRootPosition = postMoveRootPosition,
                   let currentBannerPosition = postMoveBannerPosition
                {
                    let needsCorrection =
                        abs(currentBannerPosition.x - plan.targetBannerPosition.x) > 1 ||
                        abs(currentBannerPosition.y - plan.targetBannerPosition.y) > 1

                    if needsCorrection {
                        let correctedRootPosition = NotificationGeometry.correctedRootPosition(
                            currentRootPosition: currentRootPosition,
                            actualBannerPosition: currentBannerPosition,
                            targetBannerPosition: plan.targetBannerPosition
                        )
                        debugLog(
                            "Applying root correction: " +
                                "currentRoot=\(pointSummary(currentRootPosition)), " +
                                "actualBanner=\(pointSummary(currentBannerPosition)), " +
                                "targetBanner=\(pointSummary(plan.targetBannerPosition)), " +
                                "correctedRoot=\(pointSummary(correctedRootPosition))"
                        )
                        _ = axClient.setPosition(window, point: correctedRootPosition)
                        postMoveRootPosition = axClient.position(of: window)
                        postMoveBannerPosition = axClient.position(of: resolvedBannerContainer)
                        movedElementSummary += "+corrected"
                    }
                }
            }

            let bannerWithinReferenceScreen = plan.referenceScreen.map {
                $0.frame.contains(postMoveBannerPosition ?? .zero)
            } ?? false
            controller.noteNotificationMoved()
            debugLog(
                "Post-move verification: " +
                    "movedElement=\(movedElementSummary), " +
                    "rootPos=\(optionalPointSummary(postMoveRootPosition)), " +
                    "bannerPos=\(optionalPointSummary(postMoveBannerPosition)), " +
                    "bannerWithinReferenceScreen=\(bannerWithinReferenceScreen)"
            )
            debugLog(
                "Moved notification to \(currentPosition.displayName) at (\(newPosition.x), \(newPosition.y)) " +
                    "from root=\(windowFingerprint(window: window, identifier: windowIdentifier, focused: focusedWindow, windowSize: resolvedWindowSize, notifPosition: windowPosition)), " +
                    "banner=\(elementFingerprint(resolvedBannerContainer, identifier: bannerIdentifier, focused: bannerFocused, size: resolvedNotifSize, position: resolvedPosition)), " +
                    "referenceScreen=\(screenSummary(from: plan.referenceScreen))"
            )
            let needsSettleFollowUp = postMoveBannerPosition.map {
                abs($0.x - plan.targetBannerPosition.x) > 1 ||
                    abs($0.y - plan.targetBannerPosition.y) > 1
            } ?? true
            return .moved(needsSettleFollowUp: needsSettleFollowUp)
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

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let copyright: String = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

        let elements: [(NSView, CGFloat)] = [
            (createIconView(), 165),
            (createLabel("PingPlace", font: .boldSystemFont(ofSize: 16)), 110),
            (createLabel("Version \(version)"), 90),
            (createLabel("Fork and later evolutions by bric3"), 70),
            (createOriginalAppLinkButton(), 50),
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

    private func createOriginalAppLinkButton() -> NSButton {
        let button = NSButton()
        button.title = "Original app by Wade Grimridge"
        button.bezelStyle = .inline
        button.isBordered = false
        button.target = self
        button.action = #selector(openOriginalRepository)
        button.attributedTitle = NSAttributedString(string: "Original app by Wade Grimridge", attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        return button
    }

    @objc private func openOriginalRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/NotWadeGrimridge/PingPlace")!)
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
        return axClient.hasSystemWideFocusedApplication(pid: pid)
            || axClient.hasSystemWideFocusedWindow(pid: pid)
    }

    func notificationCenterPanelSignal() -> NotificationCenterPanelSignal {
        guard let pid = axClient.notificationCenterProcessIdentifier(bundleID: notificationCenterBundleID) else {
            return NotificationCenterPanelSignal(
                hasFocusedWindow: false,
                hasWidgetUI: false,
                hasSystemWideFocusedApplication: false,
                hasSystemWideFocusedWindow: false
            )
        }
        return NotificationCenterPanelSignal(
            hasFocusedWindow: axClient.hasFocusedWindow(pid: pid),
            hasWidgetUI: axClient.hasWidgetUI(pid: pid),
            hasSystemWideFocusedApplication: axClient.hasSystemWideFocusedApplication(pid: pid),
            hasSystemWideFocusedWindow: axClient.hasSystemWideFocusedWindow(pid: pid)
        )
    }

    func notificationCenterWindowCreated(_ element: AXUIElement) {
        let moveResult = moveNotificationResult(element)
        let needsSettleFollowUp: Bool
        switch moveResult {
        case let .moved(shouldSettle):
            needsSettleFollowUp = shouldSettle
        case .noBannerContainer, .nonMovableCandidate:
            needsSettleFollowUp = false
        }
        controller.handleNotificationWindowCreated(needsSettleFollowUp: needsSettleFollowUp)
    }

    func notificationCenterStateMonitorTick() {
        controller.handleWidgetMonitorTick()
    }

    func screenParametersChanged() {
        DispatchQueue.main.async {
            self.refreshMenu()
            self.controller.handleScreenConfigurationChanged()
        }
    }

    func sessionDidBecomeActive() {
        DispatchQueue.main.async {
            self.refreshMenu()
            self.controller.handleSessionDidBecomeActive()
        }
    }

    func systemWillSleep() {
        debugLog("System will sleep. \(screenTopologySummary())")
    }

    func systemDidWake() {
        DispatchQueue.main.async {
            self.refreshMenu()
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
        let screens = NSScreen.screens
        let globalTopEdge = screens.map(\.frame.maxY).max() ?? 0
        let mainDisplayID = CGMainDisplayID()

        return screens.map { screen in
            let screenDisplayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDirectDisplayID(truncating: $0) }
            return ScreenDescriptor(
                frame: ScreenResolutionPolicy.accessibilityRect(
                    from: screen.frame,
                    globalTopEdge: globalTopEdge
                ),
                visibleFrame: ScreenResolutionPolicy.accessibilityRect(
                    from: screen.visibleFrame,
                    globalTopEdge: globalTopEdge
                ),
                isMain: ScreenResolutionPolicy.isMainDisplay(
                    screenDisplayID: screenDisplayID,
                    mainDisplayID: mainDisplayID
                ),
                isBuiltIn: isBuiltInScreen(screen)
            )
        }
    }

    private func effectiveDisplayTarget() -> NotificationDisplayTarget {
        NotificationDisplayTargetPolicy.effectiveTarget(
            requestedTarget: currentDisplayTarget,
            isPortableMac: isPortableMac,
            screens: currentScreenDescriptors()
        )
    }

    private func refreshMenu() {
        guard statusItem != nil else { return }
        statusItem?.menu = createMenu()
    }

    private func startSettingsFileWatchIfNeeded() {
        guard let fileURL = settings.fileURL else { return }
        settingsFileLastModifiedAt = settingsFileModificationDate(fileURL: fileURL)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollSettingsFileChanges()
        }
        timer.tolerance = 0.2
        settingsFileWatchTimer = timer
    }

    private func pollSettingsFileChanges() {
        guard let fileURL = settings.fileURL else { return }
        let currentModifiedAt = settingsFileModificationDate(fileURL: fileURL)
        guard currentModifiedAt != settingsFileLastModifiedAt else { return }
        settingsFileLastModifiedAt = currentModifiedAt
        applyWatchedSettingsFileChanges()
    }

    private func settingsFileModificationDate(fileURL: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private func syncSettingsFileWatchState() {
        guard let fileURL = settings.fileURL else { return }
        settingsFileLastModifiedAt = settingsFileModificationDate(fileURL: fileURL)
    }

    private func applyWatchedSettingsFileChanges() {
        var shouldMoveNotifications = false

        let loadedPosition = loadedNotificationPosition()
        if loadedPosition != currentPosition {
            let oldPosition = currentPosition
            currentPosition = loadedPosition
            positionPickerView?.selectedPosition = loadedPosition
            debugLog("Settings file changed position: \(oldPosition.displayName) → \(loadedPosition.displayName)")
            shouldMoveNotifications = true
        }

        let loadedDisplayTarget = loadedNotificationDisplayTarget()
        if loadedDisplayTarget != currentDisplayTarget {
            let oldTarget = currentDisplayTarget
            currentDisplayTarget = loadedDisplayTarget
            displayTargetPickerView?.selectedTarget = loadedDisplayTarget
            debugLog("Settings file changed display target: \(oldTarget.displayName) → \(loadedDisplayTarget.displayName)")
            clearCachedNotificationGeometry()
            shouldMoveNotifications = true
        }

        refreshMenu()

        if shouldMoveNotifications, launchMode != .menuPreview {
            moveAllNotifications(reason: "settingsFileChanged")
        }
    }

    private func loadedNotificationPosition() -> NotificationPosition {
        guard let rawValue = settings.string(forKey: .notificationPosition),
              let position = NotificationPosition(rawValue: rawValue)
        else {
            return .topMiddle
        }
        return position
    }

    private func loadedNotificationDisplayTarget() -> NotificationDisplayTarget {
        guard let rawValue = settings.string(forKey: .notificationDisplayTarget),
              let target = NotificationDisplayTarget(rawValue: rawValue)
        else {
            return .mainDisplay
        }
        return target
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
        guard let descriptor else { return "n/a" }
        let frame = rectSummary(descriptor.frame)
        let visible = rectSummary(descriptor.visibleFrame)
        return "{main=\(descriptor.isMain),builtIn=\(descriptor.isBuiltIn),frame=\(frame),visible=\(visible)}"
    }

    private func screenSummary(from screen: NSScreen?) -> String {
        guard let screen else { return "n/a" }
        let id = screenIdentifier(screen) ?? "unknown"
        let frame = rectSummary(screen.frame)
        let visible = rectSummary(screen.visibleFrame)
        let isMain = screen == NSScreen.main
        let isBuiltIn = isBuiltInScreen(screen)
        return "{id=\(id),main=\(isMain),builtIn=\(isBuiltIn),frame=\(frame),visible=\(visible)}"
    }

    private func sizeSummary(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func pointSummary(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    private func optionalPointSummary(_ point: CGPoint?) -> String {
        point.map(pointSummary) ?? "n/a"
    }

    func screenTopologySummary() -> String {
        let screensSummary = NSScreen.screens.enumerated().map { index, screen in
            let id = screenIdentifier(screen) ?? "unknown"
            let frame = rectSummary(screen.frame)
            let visibleFrame = rectSummary(screen.visibleFrame)
            let isMain = screen == NSScreen.main
            let isBuiltIn = isBuiltInScreen(screen)
            return "#\(index){id=\(id),main=\(isMain),builtIn=\(isBuiltIn),frame=\(frame),visible=\(visibleFrame)}"
        }.joined(separator: " ")
        return "screens=[\(screensSummary)]"
    }

    private func screenIdentifier(_ screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return String(screenNumber.uint32Value)
    }

    private func isBuiltInScreen(_ screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
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
