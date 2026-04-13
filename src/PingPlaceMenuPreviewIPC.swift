import AppKit
import Foundation

enum PingPlaceInstanceIPC {
    static let terminateInstanceNotification = Notification.Name("com.grimridge.PingPlace.instance.terminate")
    static let senderProcessIDKey = "senderProcessID"
    static let launchModeKey = "launchMode"

    static func terminationUserInfo(senderProcessID: Int32, launchMode: PingPlaceLaunchMode) -> [String: String] {
        [
            senderProcessIDKey: String(senderProcessID),
            launchModeKey: launchMode.rawValue,
        ]
    }

    static func shouldTerminateInstance(
        currentProcessID: Int32,
        currentLaunchMode: PingPlaceLaunchMode,
        userInfo: [AnyHashable: Any]?
    ) -> Bool {
        guard let rawSenderProcessID = userInfo?[senderProcessIDKey] as? String,
              let senderProcessID = Int32(rawSenderProcessID),
              let rawLaunchMode = userInfo?[launchModeKey] as? String,
              let launchMode = PingPlaceLaunchMode(rawValue: rawLaunchMode)
        else {
            return false
        }

        return senderProcessID != currentProcessID && launchMode == currentLaunchMode
    }
}
