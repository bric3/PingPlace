import Foundation

enum PingPlaceLaunchMode: String, Equatable {
    case full
    case menuPreview
    case smokeTest

    static func detect(arguments: [String], environment: [String: String]) -> PingPlaceLaunchMode {
        if arguments.contains("--menu-preview") {
            return .menuPreview
        }

        if arguments.contains("--smoke-test") {
            return .smokeTest
        }

        if let rawValue = environment["PINGPLACE_MENU_PREVIEW"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["1", "true", "yes", "on"].contains(rawValue)
        {
            return .menuPreview
        }

        if let rawValue = environment["PINGPLACE_SMOKE_TEST"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["1", "true", "yes", "on"].contains(rawValue)
        {
            return .smokeTest
        }

        return .full
    }
}
