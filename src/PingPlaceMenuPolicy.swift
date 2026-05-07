import Foundation

enum PingPlaceMenuPolicy {
    static func showsRerunDetectionMenuItem(
        explicitFlag: Bool,
        isDebugBuild: Bool
    ) -> Bool {
        explicitFlag || isDebugBuild
    }
}
