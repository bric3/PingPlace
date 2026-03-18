enum NotificationMovePolicy {
    static func moveDecision(identifier: String?, focused: Bool) -> NotificationMoveDecision {
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
}
