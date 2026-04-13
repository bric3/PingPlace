import CoreGraphics

struct NotificationWindowSnapshot {
    let identifier: String?
    let focused: Bool
    let isNotificationCenterPanelOpen: Bool
    let notificationSubrole: String?
    let rootWindowPosition: CGPoint
    let windowSize: CGSize
    let notificationSize: CGSize
    let notificationPosition: CGPoint

    init(
        identifier: String?,
        focused: Bool,
        isNotificationCenterPanelOpen: Bool,
        notificationSubrole: String?,
        rootWindowPosition: CGPoint = .zero,
        windowSize: CGSize,
        notificationSize: CGSize,
        notificationPosition: CGPoint
    ) {
        self.identifier = identifier
        self.focused = focused
        self.isNotificationCenterPanelOpen = isNotificationCenterPanelOpen
        self.notificationSubrole = notificationSubrole
        self.rootWindowPosition = rootWindowPosition
        self.windowSize = windowSize
        self.notificationSize = notificationSize
        self.notificationPosition = notificationPosition
    }
}

struct NotificationWindowCache: Equatable {
    let initialPosition: CGPoint
    let initialWindowSize: CGSize
    let initialNotificationSize: CGSize
    let initialPadding: CGFloat
    let windowIdentifier: String?
}

struct NotificationWindowMovePlan {
    let cacheResetIdentifiers: (previous: String?, current: String?)?
    let initialPositionRecalculated: Bool
    let cacheInitialized: Bool
    let resetPosition: CGPoint?
    let targetPosition: CGPoint
    let resolvedScreen: ScreenDescriptor?
    let referenceScreen: ScreenDescriptor?
}

enum NotificationWindowMoveEvaluation {
    case skip(NotificationMoveDecision)
    case move(NotificationWindowMovePlan)
}

final class NotificationWindowPlacementEngine {
    private let paddingAboveDock: CGFloat
    private(set) var cache: NotificationWindowCache?

    init(paddingAboveDock: CGFloat) {
        self.paddingAboveDock = paddingAboveDock
    }

    func clearCache() {
        cache = nil
    }

    func evaluateMove(
        snapshot: NotificationWindowSnapshot,
        currentPosition: NotificationPosition,
        displayTarget: NotificationDisplayTarget = .mainDisplay,
        screens: [ScreenDescriptor]
    ) -> NotificationWindowMoveEvaluation {
        let decision = NotificationMovePolicy.moveDecision(
            identifier: snapshot.identifier,
            focused: snapshot.focused,
            isNotificationCenterPanelOpen: snapshot.isNotificationCenterPanelOpen,
            notificationSubrole: snapshot.notificationSubrole
        )
        guard decision == .move else {
            return .skip(decision)
        }

        var cacheResetIdentifiers: (previous: String?, current: String?)?
        if NotificationMovePolicy.shouldResetCache(
            cachedWindowIdentifier: cache?.windowIdentifier,
            currentWindowIdentifier: snapshot.identifier
        ) {
            cacheResetIdentifiers = (cache?.windowIdentifier, snapshot.identifier)
            cache = nil
        }

        let resolvedScreen = ScreenResolutionPolicy.resolveScreen(
            position: snapshot.notificationPosition,
            windowSize: snapshot.windowSize,
            screens: screens
        )
        let targetScreen = ScreenResolutionPolicy.preferredScreen(target: displayTarget, screens: screens) ?? resolvedScreen

        let cacheInitialized: Bool
        let initialPositionRecalculated: Bool
        if cache == nil {
            let resolvedScreenWidth = resolvedScreen?.frame.width ?? snapshot.windowSize.width
            let geometry = NotificationGeometry.effectiveInitialPosition(
                position: snapshot.notificationPosition,
                notifSize: snapshot.notificationSize,
                screenWidth: resolvedScreenWidth
            )
            cache = NotificationWindowCache(
                initialPosition: geometry.position,
                initialWindowSize: snapshot.windowSize,
                initialNotificationSize: snapshot.notificationSize,
                initialPadding: geometry.padding,
                windowIdentifier: snapshot.identifier
            )
            cacheInitialized = true
            initialPositionRecalculated = geometry.position != snapshot.notificationPosition
        } else {
            cacheInitialized = false
            initialPositionRecalculated = false
        }

        let cache = cache!
        let resetPosition = snapshot.notificationPosition != cache.initialPosition ? cache.initialPosition : nil
        let referenceScreen = targetScreen
        let targetWindowSize = referenceScreen.map(\.frame.size) ?? cache.initialWindowSize
        let dockSize = referenceScreen.map(ScreenResolutionPolicy.dockSize(for:)) ?? 0
        let target = NotificationGeometry.newPosition(
            currentPosition: currentPosition,
            windowSize: targetWindowSize,
            notifSize: cache.initialNotificationSize,
            position: cache.initialPosition,
            padding: cache.initialPadding,
            dockSize: dockSize,
            paddingAboveDock: paddingAboveDock
        )

        return .move(
            NotificationWindowMovePlan(
                cacheResetIdentifiers: cacheResetIdentifiers,
                initialPositionRecalculated: initialPositionRecalculated,
                cacheInitialized: cacheInitialized,
                resetPosition: resetPosition,
                targetPosition: CGPoint(x: target.x, y: target.y),
                resolvedScreen: resolvedScreen,
                referenceScreen: referenceScreen
            )
        )
    }
}
