enum NotificationDisplayTarget: String, CaseIterable {
    case mainDisplay
    case builtInDisplay

    var displayName: String {
        switch self {
        case .mainDisplay:
            return "Main Display"
        case .builtInDisplay:
            return "Laptop Display"
        }
    }

    var pickerTitle: String {
        switch self {
        case .mainDisplay:
            return "Position on the Main Display"
        case .builtInDisplay:
            return "Position on the Laptop Display"
        }
    }
}
