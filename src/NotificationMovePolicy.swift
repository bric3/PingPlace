enum NotificationMovePolicy {
    static func moveDecision(
        identifier: String?,
        focused: Bool,
        isNotificationCenterPanelOpen: Bool,
        notificationSubrole: String?
    ) -> NotificationMoveDecision {
        if isNotificationCenterPanelOpen,
           shouldSkipForPanelOpen(notificationSubrole: notificationSubrole) {
            return .skipPanelOpen
        }
        if let identifier, identifier.hasPrefix("widget") {
            return .skipWidget
        }
        if focused {
            return .skipFocused
        }
        return .move
    }

    static func shouldResetCache(cachedWindowIdentifier: String?, currentWindowIdentifier: String?) -> Bool {
        guard let cachedWindowIdentifier, let currentWindowIdentifier else {
            return false
        }
        return cachedWindowIdentifier != currentWindowIdentifier
    }

    private static func shouldSkipForPanelOpen(notificationSubrole: String?) -> Bool {
        switch notificationSubrole {
        case "AXNotificationCenterAlert":
            return false
        case "AXNotificationCenterBanner",
             "AXNotificationCenterNotification",
             "AXNotificationCenterBannerWindow":
            return true
        default:
            return true
        }
    }
}
