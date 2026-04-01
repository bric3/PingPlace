import ApplicationServices
import Cocoa

protocol NotificationCenterAXClient {
    func notificationCenterProcessIdentifier(bundleID: String) -> pid_t?
    func notificationWindows(pid: pid_t) -> [AXUIElement]?
    func windowIdentifier(_ element: AXUIElement) -> String?
    func isFocused(_ element: AXUIElement) -> Bool
    func position(of element: AXUIElement) -> CGPoint?
    func size(of element: AXUIElement) -> CGSize?
    func setPosition(_ element: AXUIElement, point: CGPoint)
    func firstElement(root: AXUIElement, targetSubroles: [String]) -> AXUIElement?
    func hasFocusedWindow(pid: pid_t) -> Bool
    func hasWidgetUI(pid: pid_t) -> Bool
    func role(of element: AXUIElement) -> String?
    func subrole(of element: AXUIElement) -> String?
}

struct SystemNotificationCenterAXClient: NotificationCenterAXClient {
    func notificationCenterProcessIdentifier(bundleID: String) -> pid_t? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        })?.processIdentifier
    }

    func notificationWindows(pid: pid_t) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        return windows
    }

    func windowIdentifier(_ element: AXUIElement) -> String? {
        var identifierRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef) == .success else {
            return nil
        }
        return identifierRef as? String
    }

    func isFocused(_ element: AXUIElement) -> Bool {
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef as? Bool else {
            return false
        }
        return focused
    }

    func position(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        guard let posVal = positionValue,
              AXValueGetType(posVal as! AXValue) == .cgPoint else {
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }

    func size(of element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let sizeVal = sizeValue,
              AXValueGetType(sizeVal as! AXValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return size
    }

    func setPosition(_ element: AXUIElement, point: CGPoint) {
        var point = point
        let value = AXValueCreate(.cgPoint, &point)!
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func firstElement(root: AXUIElement, targetSubroles: [String]) -> AXUIElement? {
        TreeTraversal.firstMatchingNode(
            roots: [root],
            childProvider: { children(of: $0) },
            matches: { element in
                guard let subrole = subrole(of: element) else {
                    return false
                }
                return targetSubroles.contains(subrole)
            }
        )
    }

    func hasFocusedWindow(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success else {
            return false
        }
        return focusedWindowRef != nil
    }

    func hasWidgetUI(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        return TreeTraversal.firstMatchingNode(
            roots: [axApp],
            childProvider: { children(of: $0) },
            matches: { element in
                guard let identifier = windowIdentifier(element) else {
                    return false
                }
                return identifier.hasPrefix("widget-local")
            }
        ) != nil
    }

    func role(of element: AXUIElement) -> String? {
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    func subrole(of element: AXUIElement) -> String? {
        var subroleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success else {
            return nil
        }
        return subroleRef as? String
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }
        return children
    }
}
