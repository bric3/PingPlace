import CoreGraphics

struct ScreenDescriptor: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
}

enum NotificationMoveDecision: Equatable {
    case skipPanelOpen
    case skipWidget
    case skipFocused
    case move
}

enum NotificationCenterStateChange: Equatable {
    case unchanged
    case opened
    case closed
}

enum RecoveryRetryAction: Equatable {
    case stop
    case retry
}
