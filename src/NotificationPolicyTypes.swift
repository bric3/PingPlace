import CoreGraphics

struct ScreenDescriptor: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
    let isBuiltIn: Bool

    init(frame: CGRect, visibleFrame: CGRect, isMain: Bool, isBuiltIn: Bool = false) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
    }
}

struct NotificationCenterPanelSignal: Equatable {
    let hasFocusedWindow: Bool
    let hasWidgetUI: Bool
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

enum NotificationScanResult: Equatable {
    case movedNotification
    case noMovableCandidates
    case placeholderOnly
}
