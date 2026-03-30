import CoreGraphics
import Foundation

private enum TestFailure: Error {
    case assertionFailed(String)
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    if actual != expected {
        throw TestFailure.assertionFailed("\(label): expected \(expected), got \(actual)")
    }
}

private func assertEqual(_ actual: CGFloat, _ expected: CGFloat, _ label: String, epsilon: CGFloat = 0.0001) throws {
    if abs(actual - expected) > epsilon {
        throw TestFailure.assertionFailed("\(label): expected \(expected), got \(actual)")
    }
}

private func assertTrue(_ condition: Bool, _ label: String) throws {
    if !condition {
        throw TestFailure.assertionFailed("\(label): expected true")
    }
}

private let externalMainScreen = ScreenDescriptor(
    frame: CGRect(x: 0, y: 0, width: 3360, height: 1890),
    visibleFrame: CGRect(x: 0, y: 0, width: 3360, height: 1859),
    isMain: true
)

private let laptopSecondaryScreen = ScreenDescriptor(
    frame: CGRect(x: 822, y: -1169, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 822, y: -1169, width: 1800, height: 1129),
    isMain: false
)

private let singleLaptopMainScreen = ScreenDescriptor(
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1129),
    isMain: true
)

private let dualScreenLayout = [externalMainScreen, laptopSecondaryScreen]

private let pointInsideLaptopScreen = CGPoint(x: 1440, y: -1100)
private let pointOutsideAllKnownScreens = CGPoint(x: 9999, y: 9999)
private let laptopWindowSize = CGSize(width: 1800, height: 1169)
private let unknownWindowSize = CGSize(width: 1200, height: 800)
private let widgetTreeWithCycle: [Int: [Int]] = [
    1: [2, 3],
    2: [4],
    3: [5],
    4: [2, 6],
    5: [],
    6: [],
]
private let deepLinearTreeNodeCount = 20000

private final class TestScheduledAction: ScheduledNotificationAction {
    let action: () -> Void
    private(set) var isCancelled = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }
}

private final class TestScheduler: NotificationScheduler {
    private(set) var scheduledActions: [TestScheduledAction] = []

    @discardableResult
    func schedule(after _: TimeInterval, _ action: @escaping () -> Void) -> ScheduledNotificationAction {
        let scheduled = TestScheduledAction(action: action)
        scheduledActions.append(scheduled)
        return scheduled
    }

    func runNext() {
        guard !scheduledActions.isEmpty else { return }
        let action = scheduledActions.removeFirst()
        if !action.isCancelled {
            action.action()
        }
    }

    func firstScheduledAction() -> TestScheduledAction? {
        scheduledActions.first
    }
}

private final class TestControllerDelegate: NotificationControllerDelegate {
    var currentPosition: NotificationPosition = .deadCenter
    var screenSummary = "screens=[test]"
    var hasNCUI = false
    var moveResults: [Bool] = []
    private(set) var moveReasons: [String] = []
    private(set) var loggedMessages: [String] = []
    private(set) var clearCacheCallCount = 0

    func debugLog(_ message: String) {
        loggedMessages.append(message)
    }

    func notificationPosition() -> NotificationPosition {
        currentPosition
    }

    func screenTopologySummary() -> String {
        screenSummary
    }

    func clearCachedNotificationGeometry() {
        clearCacheCallCount += 1
    }

    func moveAllNotifications(reason: String) -> Bool {
        moveReasons.append(reason)
        if moveResults.isEmpty {
            return false
        }
        return moveResults.removeFirst()
    }

    func hasNotificationCenterUI() -> Bool {
        hasNCUI
    }
}

private func testInitialPositionInBounds() throws {
    let result = NotificationGeometry.effectiveInitialPosition(
        position: CGPoint(x: 1700, y: 100),
        notifSize: CGSize(width: 200, height: 60),
        screenWidth: 1920
    )
    try assertEqual(result.position.x, 1700, "initial in-bounds x")
    try assertEqual(result.padding, 20, "initial in-bounds padding")
}

private func testInitialPositionRecomputedWhenOutOfBounds() throws {
    let result = NotificationGeometry.effectiveInitialPosition(
        position: CGPoint(x: 1900, y: 100),
        notifSize: CGSize(width: 300, height: 60),
        screenWidth: 1920
    )
    try assertEqual(result.position.x, 1604, "initial overflow recomputed x")
    try assertEqual(result.padding, 16, "initial overflow default padding")
}

private func testDeadCenterPlacement() throws {
    let result = NotificationGeometry.newPosition(
        currentPosition: .deadCenter,
        windowSize: CGSize(width: 1920, height: 1080),
        notifSize: CGSize(width: 320, height: 80),
        position: CGPoint(x: 1000, y: 0),
        padding: 80,
        dockSize: 40,
        paddingAboveDock: 30
    )
    try assertEqual(result.x, -200, "dead-center x")
    try assertEqual(result.y, 460, "dead-center y")
}

private func testPlacementForAllNotificationPositions() throws {
    let windowSize = CGSize(width: 1920, height: 1080)
    let notificationSize = CGSize(width: 320, height: 80)
    let notificationPosition = CGPoint(x: 1000, y: 0)
    let padding: CGFloat = 80
    let dockSize: CGFloat = 40
    let paddingAboveDock: CGFloat = 30

    let expectations: [(NotificationPosition, CGFloat, CGFloat)] = [
        (.topLeft, -920, 0),
        (.topMiddle, -200, 0),
        (.topRight, 0, 0),
        (.middleLeft, -920, 460),
        (.deadCenter, -200, 460),
        (.middleRight, 0, 460),
        (.bottomLeft, -920, 930),
        (.bottomMiddle, -200, 930),
        (.bottomRight, 0, 930),
    ]

    for (position, expectedX, expectedY) in expectations {
        let result = NotificationGeometry.newPosition(
            currentPosition: position,
            windowSize: windowSize,
            notifSize: notificationSize,
            position: notificationPosition,
            padding: padding,
            dockSize: dockSize,
            paddingAboveDock: paddingAboveDock
        )

        try assertEqual(result.x, expectedX, "\(position.displayName) x")
        try assertEqual(result.y, expectedY, "\(position.displayName) y")
    }
}

private func testMoveDecisionSkipsWidgetWindows() throws {
    let result = NotificationMovePolicy.moveDecision(
        identifier: "widget-local-123",
        focused: false,
        isNotificationCenterPanelOpen: false,
        notificationSubrole: "AXNotificationCenterBanner"
    )
    try assertEqual(result, .skipWidget, "widget windows should be skipped")
}

private func testMoveDecisionSkipsFocusedWindows() throws {
    let result = NotificationMovePolicy.moveDecision(
        identifier: "notification-banner",
        focused: true,
        isNotificationCenterPanelOpen: false,
        notificationSubrole: "AXNotificationCenterBanner"
    )
    try assertEqual(result, .skipFocused, "focused windows should be skipped")
}

private func testMoveDecisionAllowsRegularBanners() throws {
    let result = NotificationMovePolicy.moveDecision(
        identifier: "notification-banner",
        focused: false,
        isNotificationCenterPanelOpen: false,
        notificationSubrole: "AXNotificationCenterBanner"
    )
    try assertEqual(result, .move, "regular banners should be moved")
}

private func testMoveDecisionSkipsWhenNotificationCenterPanelIsOpen() throws {
    let result = NotificationMovePolicy.moveDecision(
        identifier: "notification-banner",
        focused: false,
        isNotificationCenterPanelOpen: true,
        notificationSubrole: "AXNotificationCenterBanner"
    )
    try assertEqual(result, .skipPanelOpen, "panel-open state should block moves")
}

private func testMoveDecisionAllowsAlertsWhilePanelIsOpen() throws {
    let result = NotificationMovePolicy.moveDecision(
        identifier: "notification-alert",
        focused: false,
        isNotificationCenterPanelOpen: true,
        notificationSubrole: "AXNotificationCenterAlert"
    )
    try assertEqual(result, .move, "alert windows should still move while panel-open heuristics are active")
}

private func testCacheResetWhenWindowIdentifierChanges() throws {
    try assertTrue(
        NotificationMovePolicy.shouldResetCache(
            cachedWindowIdentifier: "banner-1",
            currentWindowIdentifier: "panel-1"
        ),
        "cache should reset on identifier change"
    )
}

private func testCacheDoesNotResetWithoutIdentifiers() throws {
    try assertEqual(
        NotificationMovePolicy.shouldResetCache(
            cachedWindowIdentifier: "banner-1",
            currentWindowIdentifier: nil
        ),
        false,
        "cache should not reset when current identifier is absent"
    )
}

private func testNotificationCenterStateChangeDetectsOpen() throws {
    try assertEqual(
        NotificationCenterStatePolicy.stateChange(
            previousState: 0,
            isOpen: true
        ),
        .opened,
        "state change should detect panel opening"
    )
}

private func testNotificationCenterStateChangeDetectsClose() throws {
    try assertEqual(
        NotificationCenterStatePolicy.stateChange(
            previousState: 1,
            isOpen: false
        ),
        .closed,
        "state change should detect panel closing"
    )
}

private func testNotificationCenterStateChangeDetectsNoChange() throws {
    try assertEqual(
        NotificationCenterStatePolicy.stateChange(
            previousState: 0,
            isOpen: false
        ),
        .unchanged,
        "state change should stay unchanged when panel remains closed"
    )
}

private func testRecoveryRetryActionRetriesWhenNoMoveAndAttemptsRemain() throws {
    try assertEqual(
        NotificationCenterStatePolicy.recoveryRetryAction(
            didMoveNotification: false,
            attemptNumber: 3,
            maxAttempts: 10
        ),
        .retry,
        "recovery should retry while attempts remain and no notification moved"
    )
}

private func testRecoveryRetryActionStopsAfterSuccessfulMove() throws {
    try assertEqual(
        NotificationCenterStatePolicy.recoveryRetryAction(
            didMoveNotification: true,
            attemptNumber: 0,
            maxAttempts: 10
        ),
        .stop,
        "recovery should stop after a successful move"
    )
}

private func testRecoveryRetryActionStopsAtAttemptLimit() throws {
    try assertEqual(
        NotificationCenterStatePolicy.recoveryRetryAction(
            didMoveNotification: false,
            attemptNumber: 10,
            maxAttempts: 10
        ),
        .stop,
        "recovery should stop after exhausting retry attempts"
    )
}

private func testFirstMatchingNodeFindsNodeInCyclicGraph() throws {
    let found = TreeTraversal.firstMatchingNode(
        roots: [1],
        childProvider: { widgetTreeWithCycle[$0] ?? [] },
        matches: { $0 == 6 }
    )

    try assertEqual(found, 6, "iterative traversal should find a match in a cyclic graph")
}

private func testFirstMatchingNodeHandlesDeepGraphWithoutRecursion() throws {
    let found = TreeTraversal.firstMatchingNode(
        roots: [0],
        childProvider: { node in
            node < deepLinearTreeNodeCount ? [node + 1] : []
        },
        matches: { $0 == deepLinearTreeNodeCount }
    )

    try assertEqual(found, deepLinearTreeNodeCount, "iterative traversal should handle deep graphs")
}

private func testFirstMatchingNodeReturnsNilWhenNoMatchExists() throws {
    let found = TreeTraversal.firstMatchingNode(
        roots: [1],
        childProvider: { widgetTreeWithCycle[$0] ?? [] },
        matches: { $0 == 99 }
    )

    try assertEqual(found, nil, "iterative traversal should return nil when no match exists")
}

private func testControllerWakeClearsCacheAndTriggersMove() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    controller.handleWake()

    try assertEqual(delegate.clearCacheCallCount, 1, "wake should clear cached geometry")
    try assertEqual(delegate.moveReasons, ["didWakeNotification"], "wake should trigger immediate move")
    try assertEqual(scheduler.scheduledActions.count, 0, "wake should not schedule retry after successful move")
}

private func testControllerScreenChangeSchedulesRetryWhenNoMoveOccurs() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = [false, true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    controller.handleScreenConfigurationChanged()
    try assertEqual(delegate.moveReasons, ["didChangeScreenParametersNotification"], "screen change should try immediate move first")
    try assertEqual(scheduler.scheduledActions.count, 1, "screen change should schedule retry after failed move")

    scheduler.runNext()
    try assertEqual(
        delegate.moveReasons,
        ["didChangeScreenParametersNotification", "didChangeScreenParametersNotification-retry1"],
        "retry should use suffixed reason"
    )
}

private func testControllerSessionActivationClearsCacheAndTriggersMove() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    controller.handleSessionDidBecomeActive()

    try assertEqual(delegate.clearCacheCallCount, 1, "session activation should clear cached geometry")
    try assertEqual(delegate.moveReasons, ["sessionDidBecomeActiveNotification"], "session activation should trigger immediate move")
    try assertEqual(scheduler.scheduledActions.count, 0, "session activation should not schedule retry after successful move")
}

private func testControllerSessionActivationSchedulesRetryWhenNoMoveOccurs() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = [false, true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    controller.handleSessionDidBecomeActive()
    try assertEqual(delegate.moveReasons, ["sessionDidBecomeActiveNotification"], "session activation should try immediate move first")
    try assertEqual(scheduler.scheduledActions.count, 1, "session activation should schedule retry after failed move")

    scheduler.runNext()
    try assertEqual(
        delegate.moveReasons,
        ["sessionDidBecomeActiveNotification", "sessionDidBecomeActiveNotification-retry1"],
        "session activation retry should use suffixed reason"
    )
}

private func testControllerWidgetCloseTriggersMoveWhenNotTopRight() throws {
    let delegate = TestControllerDelegate()
    delegate.currentPosition = .deadCenter
    delegate.moveResults = [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    delegate.hasNCUI = true
    controller.handleWidgetMonitorTick()
    delegate.hasNCUI = false
    controller.handleWidgetMonitorTick()

    try assertEqual(delegate.moveReasons, ["notificationCenterClosed"], "panel close should trigger recovery move when position is not top-right")
}

private func testControllerWidgetCloseSchedulesRetryWhenNoMoveOccurs() throws {
    let delegate = TestControllerDelegate()
    delegate.currentPosition = .deadCenter
    delegate.moveResults = [false, true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    delegate.hasNCUI = true
    controller.handleWidgetMonitorTick()
    delegate.hasNCUI = false
    controller.handleWidgetMonitorTick()

    try assertEqual(delegate.moveReasons, ["notificationCenterClosed"], "panel close should try immediate recovery move")
    try assertEqual(scheduler.scheduledActions.count, 1, "panel close should schedule retry when immediate move finds nothing")

    scheduler.runNext()
    try assertEqual(
        delegate.moveReasons,
        ["notificationCenterClosed", "notificationCenterClosed-retry1"],
        "panel close retry should use suffixed reason"
    )
}

private func testControllerWidgetCloseDoesNotTriggerMoveWhenTopRight() throws {
    let delegate = TestControllerDelegate()
    delegate.currentPosition = .topRight
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    delegate.hasNCUI = true
    controller.handleWidgetMonitorTick()
    delegate.hasNCUI = false
    controller.handleWidgetMonitorTick()

    try assertEqual(delegate.moveReasons, [], "panel close should not trigger move when position is top-right")
}

private func testControllerInvalidateCancelsScheduledRetry() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = [false]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 10
    )

    controller.handleScreenConfigurationChanged()
    let scheduledAction = scheduler.firstScheduledAction()
    controller.invalidate()

    try assertEqual(scheduledAction?.isCancelled, true, "invalidate should cancel scheduled retry")
}

private func testControllerStopsRetryingAfterAttemptLimit() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = Array(repeating: false, count: 4)
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 3
    )

    controller.handleScreenConfigurationChanged()
    scheduler.runNext()
    scheduler.runNext()
    scheduler.runNext()

    try assertEqual(
        delegate.moveReasons,
        [
            "didChangeScreenParametersNotification",
            "didChangeScreenParametersNotification-retry1",
            "didChangeScreenParametersNotification-retry2",
            "didChangeScreenParametersNotification-retry3",
        ],
        "controller should stop scheduling retries after retry limit"
    )
}

private func testControllerKeepsRetryingLongEnoughForDelayedScreenChangeNotifications() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = Array(repeating: false, count: 12) + [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 20
    )

    controller.handleScreenConfigurationChanged()

    for _ in 0..<12 {
        scheduler.runNext()
    }

    try assertEqual(
        delegate.moveReasons.last,
        "didChangeScreenParametersNotification-retry12",
        "controller should keep retrying until delayed notifications become available"
    )
    try assertEqual(scheduler.scheduledActions.count, 0, "controller should stop retrying after the delayed successful move")
}

private func testControllerKeepsRetryingLongEnoughForDelayedWakeNotifications() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = Array(repeating: false, count: 12) + [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 20
    )

    controller.handleWake()

    for _ in 0..<12 {
        scheduler.runNext()
    }

    try assertEqual(
        delegate.moveReasons.last,
        "didWakeNotification-retry12",
        "controller should keep retrying after wake while AX only exposes placeholder windows"
    )
    try assertEqual(scheduler.scheduledActions.count, 0, "controller should stop retrying after the delayed successful wake move")
}

private func testControllerKeepsRetryingLongEnoughForDelayedSessionActivationNotifications() throws {
    let delegate = TestControllerDelegate()
    delegate.moveResults = Array(repeating: false, count: 12) + [true]
    let scheduler = TestScheduler()
    let controller = NotificationController(
        delegate: delegate,
        scheduler: scheduler,
        recoveryRetryInterval: 0.5,
        recoveryRetryLimit: 20
    )

    controller.handleSessionDidBecomeActive()

    for _ in 0..<12 {
        scheduler.runNext()
    }

    try assertEqual(
        delegate.moveReasons.last,
        "sessionDidBecomeActiveNotification-retry12",
        "controller should keep retrying after session activation while login-screen notifications are still placeholder-only"
    )
    try assertEqual(scheduler.scheduledActions.count, 0, "controller should stop retrying after the delayed successful session-activation move")
}

private func testPlacementEngineInitializesCacheAndComputesMovePlan() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let snapshot = NotificationWindowSnapshot(
        identifier: "banner-1",
        focused: false,
        isNotificationCenterPanelOpen: false,
        notificationSubrole: "AXNotificationCenterBanner",
        windowSize: CGSize(width: 3360, height: 1890),
        notificationSize: CGSize(width: 344, height: 73),
        notificationPosition: CGPoint(x: 3376, y: 46)
    )

    let evaluation = engine.evaluateMove(
        snapshot: snapshot,
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .move(plan) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should produce a move plan")
    }

    try assertTrue(plan.cacheInitialized, "placement engine should initialize cache on first move")
    try assertEqual(plan.targetPosition.x, -1492, "placement engine target x")
    try assertEqual(plan.targetPosition.y, 877.5, "placement engine target y")
}

private func testPlacementEngineResetsCacheWhenIdentifierChanges() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    _ = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3376, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-2",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3376, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .move(plan) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should still produce a move plan after cache reset")
    }

    try assertEqual(plan.cacheResetIdentifiers?.previous, "banner-1", "placement engine previous identifier")
    try assertEqual(plan.cacheResetIdentifiers?.current, "banner-2", "placement engine current identifier")
}

private func testPlacementEngineRequestsResetToCachedPosition() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    _ = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3000, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3205, y: 157)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .move(plan) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should produce a move plan for repeated banner")
    }

    try assertEqual(plan.resetPosition, CGPoint(x: 3000, y: 46), "placement engine reset position")
}

private func testPlacementEngineSkipsFocusedWindow() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: true,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3376, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .skip(decision) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should skip focused windows")
    }

    try assertEqual(decision, .skipFocused, "placement engine focused skip decision")
}

private func testPlacementEngineSkipsWidgetWindow() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "widget-local-123",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3376, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .skip(decision) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should skip widget windows")
    }

    try assertEqual(decision, .skipWidget, "placement engine widget skip decision")
}

private func testPlacementEngineClearCacheRemovesCachedState() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    _ = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: false,
            isNotificationCenterPanelOpen: false,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 3360, height: 1890),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 3376, y: 46)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    engine.clearCache()

    try assertEqual(engine.cache?.windowIdentifier, nil, "placement engine cache should be empty after clear")
}

private func testPlacementEngineSkipsWhenPanelIsOpen() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "banner-1",
            focused: false,
            isNotificationCenterPanelOpen: true,
            notificationSubrole: "AXNotificationCenterBanner",
            windowSize: CGSize(width: 1800, height: 1169),
            notificationSize: CGSize(width: 344, height: 73),
            notificationPosition: CGPoint(x: 2371, y: 2056)
        ),
        currentPosition: .deadCenter,
        screens: dualScreenLayout
    )

    guard case let .skip(decision) = evaluation else {
        throw TestFailure.assertionFailed("placement engine should skip when panel is open")
    }

    try assertEqual(decision, .skipPanelOpen, "placement engine panel-open skip decision")
}

private func testPlacementEngineAllowsAlertsWhenPanelIsOpen() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "alert-1",
            focused: false,
            isNotificationCenterPanelOpen: true,
            notificationSubrole: "AXNotificationCenterAlert",
            windowSize: CGSize(width: 1800, height: 1169),
            notificationSize: CGSize(width: 344, height: 57),
            notificationPosition: CGPoint(x: 1440, y: 55)
        ),
        currentPosition: .deadCenter,
        screens: [laptopSecondaryScreen]
    )

    guard case .move = evaluation else {
        throw TestFailure.assertionFailed("placement engine should still move alerts while panel-open heuristics are active")
    }
}

private func testPlacementEngineAllowsWakeAlertOnSingleMainScreenEvenWhenPanelOpenHeuristicIsActive() throws {
    let engine = NotificationWindowPlacementEngine(paddingAboveDock: 30)
    let evaluation = engine.evaluateMove(
        snapshot: NotificationWindowSnapshot(
            identifier: "wake-alert-1",
            focused: false,
            isNotificationCenterPanelOpen: true,
            notificationSubrole: "AXNotificationCenterAlert",
            windowSize: CGSize(width: 1800, height: 1169),
            notificationSize: CGSize(width: 344, height: 57),
            notificationPosition: CGPoint(x: 1440, y: 55)
        ),
        currentPosition: .deadCenter,
        screens: [singleLaptopMainScreen]
    )

    guard case let .move(plan) = evaluation else {
        throw TestFailure.assertionFailed("wake alert on a single main screen should still move even when panel-open heuristics are active")
    }

    try assertEqual(plan.referenceScreen?.frame, singleLaptopMainScreen.frame, "wake alert should use the single laptop screen as reference")
    try assertEqual(plan.targetPosition.x, -712, "wake alert target x")
    try assertEqual(plan.targetPosition.y, 516, "wake alert target y")
}

private func testResolveScreenPrefersPositionMatch() throws {
    let resolved = ScreenResolutionPolicy.resolveScreen(
        position: pointInsideLaptopScreen,
        windowSize: laptopWindowSize,
        screens: dualScreenLayout
    )

    try assertEqual(resolved?.frame, laptopSecondaryScreen.frame, "position-based screen selection")
}

private func testResolveScreenFallsBackToWindowSize() throws {
    let resolved = ScreenResolutionPolicy.resolveScreen(
        position: CGPoint(x: 4000, y: 55),
        windowSize: laptopWindowSize,
        screens: dualScreenLayout
    )

    try assertEqual(resolved?.frame, laptopSecondaryScreen.frame, "size-based screen fallback")
}

private func testResolveScreenFallsBackToMainScreen() throws {
    let resolved = ScreenResolutionPolicy.resolveScreen(
        position: pointOutsideAllKnownScreens,
        windowSize: unknownWindowSize,
        screens: dualScreenLayout
    )

    try assertEqual(resolved?.frame, externalMainScreen.frame, "main-screen fallback")
}

private func testDockSizeUsesVisibleFrameDifference() throws {
    let screen = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
        isMain: true
    )

    try assertEqual(ScreenResolutionPolicy.dockSize(for: screen), 40, "dock size")
}

@main
struct NotificationBehaviorTestRunner {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("initial position in bounds", testInitialPositionInBounds),
            ("initial position overflow", testInitialPositionRecomputedWhenOutOfBounds),
            ("dead-center placement", testDeadCenterPlacement),
            ("placement for all notification positions", testPlacementForAllNotificationPositions),
            ("move decision skips widget windows", testMoveDecisionSkipsWidgetWindows),
            ("move decision skips focused windows", testMoveDecisionSkipsFocusedWindows),
            ("move decision allows regular banners", testMoveDecisionAllowsRegularBanners),
            ("move decision skips while panel is open", testMoveDecisionSkipsWhenNotificationCenterPanelIsOpen),
            ("move decision allows alerts while panel is open", testMoveDecisionAllowsAlertsWhilePanelIsOpen),
            ("cache resets when window identifier changes", testCacheResetWhenWindowIdentifierChanges),
            ("cache does not reset without identifiers", testCacheDoesNotResetWithoutIdentifiers),
            ("notification center detects open transition", testNotificationCenterStateChangeDetectsOpen),
            ("notification center detects close transition", testNotificationCenterStateChangeDetectsClose),
            ("notification center detects unchanged state", testNotificationCenterStateChangeDetectsNoChange),
            ("recovery retries when attempts remain", testRecoveryRetryActionRetriesWhenNoMoveAndAttemptsRemain),
            ("recovery stops after successful move", testRecoveryRetryActionStopsAfterSuccessfulMove),
            ("recovery stops at attempt limit", testRecoveryRetryActionStopsAtAttemptLimit),
            ("iterative traversal finds node in cyclic graph", testFirstMatchingNodeFindsNodeInCyclicGraph),
            ("iterative traversal handles deep graph", testFirstMatchingNodeHandlesDeepGraphWithoutRecursion),
            ("iterative traversal returns nil when no match exists", testFirstMatchingNodeReturnsNilWhenNoMatchExists),
            ("controller wake clears cache and moves", testControllerWakeClearsCacheAndTriggersMove),
            ("controller screen change schedules retry", testControllerScreenChangeSchedulesRetryWhenNoMoveOccurs),
            ("controller session activation clears cache and moves", testControllerSessionActivationClearsCacheAndTriggersMove),
            ("controller session activation schedules retry", testControllerSessionActivationSchedulesRetryWhenNoMoveOccurs),
            ("controller widget close triggers move", testControllerWidgetCloseTriggersMoveWhenNotTopRight),
            ("controller widget close schedules retry", testControllerWidgetCloseSchedulesRetryWhenNoMoveOccurs),
            ("controller widget close skips top-right", testControllerWidgetCloseDoesNotTriggerMoveWhenTopRight),
            ("controller invalidate cancels retry", testControllerInvalidateCancelsScheduledRetry),
            ("controller stops retrying at limit", testControllerStopsRetryingAfterAttemptLimit),
            ("controller keeps retrying for delayed screen change notifications", testControllerKeepsRetryingLongEnoughForDelayedScreenChangeNotifications),
            ("controller keeps retrying for delayed wake notifications", testControllerKeepsRetryingLongEnoughForDelayedWakeNotifications),
            ("controller keeps retrying for delayed session activation notifications", testControllerKeepsRetryingLongEnoughForDelayedSessionActivationNotifications),
            ("placement engine initializes cache and computes move plan", testPlacementEngineInitializesCacheAndComputesMovePlan),
            ("placement engine resets cache when identifier changes", testPlacementEngineResetsCacheWhenIdentifierChanges),
            ("placement engine requests reset to cached position", testPlacementEngineRequestsResetToCachedPosition),
            ("placement engine skips focused window", testPlacementEngineSkipsFocusedWindow),
            ("placement engine skips widget window", testPlacementEngineSkipsWidgetWindow),
            ("placement engine clear cache removes state", testPlacementEngineClearCacheRemovesCachedState),
            ("placement engine skips while panel is open", testPlacementEngineSkipsWhenPanelIsOpen),
            ("placement engine allows alerts while panel is open", testPlacementEngineAllowsAlertsWhenPanelIsOpen),
            ("placement engine allows wake alerts on single main screen while panel-open heuristic is active", testPlacementEngineAllowsWakeAlertOnSingleMainScreenEvenWhenPanelOpenHeuristicIsActive),
            ("resolve screen prefers position match", testResolveScreenPrefersPositionMatch),
            ("resolve screen falls back to window size", testResolveScreenFallsBackToWindowSize),
            ("resolve screen falls back to main screen", testResolveScreenFallsBackToMainScreen),
            ("dock size uses visible frame difference", testDockSizeUsesVisibleFrameDifference),
        ]

        do {
            for (_, test) in tests {
                try test()
            }
            print("All \(tests.count) tests passed.")
        } catch let TestFailure.assertionFailed(message) {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        } catch {
            fputs("Unexpected test failure: \(error)\n", stderr)
            exit(1)
        }
    }
}
