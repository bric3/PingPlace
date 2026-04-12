import AppKit
import Foundation

enum PingPlaceMenuPreviewIPC {
    static let terminatePreviewNotification = Notification.Name("com.grimridge.PingPlace.menuPreview.terminate")
    static let senderProcessIDKey = "senderProcessID"

    static func terminationUserInfo(senderProcessID: Int32) -> [String: String] {
        [senderProcessIDKey: String(senderProcessID)]
    }

    static func shouldTerminatePreview(currentProcessID: Int32, userInfo: [AnyHashable: Any]?) -> Bool {
        guard let rawSenderProcessID = userInfo?[senderProcessIDKey] as? String,
              let senderProcessID = Int32(rawSenderProcessID)
        else {
            return true
        }

        return senderProcessID != currentProcessID
    }
}
