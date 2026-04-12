import Foundation

enum PingPlaceLaunchMode: Equatable {
    case full
    case menuPreview

    static func detect(arguments: [String], environment: [String: String]) -> PingPlaceLaunchMode {
        if arguments.contains("--menu-preview") {
            return .menuPreview
        }

        if let rawValue = environment["PINGPLACE_MENU_PREVIEW"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["1", "true", "yes", "on"].contains(rawValue)
        {
            return .menuPreview
        }

        return .full
    }
}
