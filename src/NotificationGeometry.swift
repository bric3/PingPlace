import CoreGraphics

enum NotificationGeometry {
    static func effectiveInitialPosition(
        position: CGPoint,
        notifSize: CGSize,
        screenWidth: CGFloat,
        defaultRightPadding: CGFloat = 16.0
    ) -> (position: CGPoint, padding: CGFloat) {
        var effectivePosition = position
        let padding: CGFloat

        if position.x + notifSize.width > screenWidth {
            padding = defaultRightPadding
            effectivePosition.x = screenWidth - notifSize.width - padding
        } else {
            let rightEdge = position.x + notifSize.width
            padding = screenWidth - rightEdge
        }

        return (effectivePosition, padding)
    }

    static func newPosition(
        currentPosition: NotificationPosition,
        windowSize: CGSize,
        notifSize: CGSize,
        position: CGPoint,
        padding: CGFloat,
        dockSize: CGFloat,
        paddingAboveDock: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        let newX: CGFloat
        let newY: CGFloat

        switch currentPosition {
        case .topLeft, .middleLeft, .bottomLeft:
            newX = padding - position.x
        case .topMiddle, .bottomMiddle, .deadCenter:
            newX = (windowSize.width - notifSize.width) / 2 - position.x
        case .topRight, .middleRight, .bottomRight:
            newX = windowSize.width - notifSize.width - padding - position.x
        }

        switch currentPosition {
        case .topLeft, .topMiddle, .topRight:
            newY = 0
        case .middleLeft, .middleRight, .deadCenter:
            newY = (windowSize.height - notifSize.height) / 2 - dockSize
        case .bottomLeft, .bottomMiddle, .bottomRight:
            newY = windowSize.height - notifSize.height - dockSize - paddingAboveDock
        }

        return (newX, newY)
    }
}
