import ApplicationServices
import Cocoa

enum NotificationCenterAXTraversalPolicy {
    static let descendantAttributes: [String] = [
        kAXChildrenAttribute as String,
        "AXContents",
        "AXVisibleChildren",
        "AXRows",
        "AXColumns",
        "AXSelectedChildren",
        "AXTabs",
    ]

    static let ignoredFallbackAttributes: Set<String> = [
        kAXParentAttribute as String,
        kAXWindowAttribute as String,
        kAXTopLevelUIElementAttribute as String,
        kAXFocusedApplicationAttribute as String,
        kAXFocusedWindowAttribute as String,
        kAXTitleUIElementAttribute as String,
    ]

    static func shouldInspectFallbackAttribute(_ attribute: String) -> Bool {
        !descendantAttributes.contains(attribute) && !ignoredFallbackAttributes.contains(attribute)
    }
}

protocol NotificationCenterAXClient {
    func notificationCenterProcessIdentifier(bundleID: String) -> pid_t?
    func notificationWindows(pid: pid_t) -> [AXUIElement]?
    func windowIdentifier(_ element: AXUIElement) -> String?
    func isFocused(_ element: AXUIElement) -> Bool
    func position(of element: AXUIElement) -> CGPoint?
    func size(of element: AXUIElement) -> CGSize?
    @discardableResult
    func setPosition(_ element: AXUIElement, point: CGPoint) -> AXError
    func firstElement(root: AXUIElement, targetSubroles: [String]) -> AXUIElement?
    func hasSystemWideFocusedApplication(pid: pid_t) -> Bool
    func hasSystemWideFocusedWindow(pid: pid_t) -> Bool
    func hasFocusedWindow(pid: pid_t) -> Bool
    func hasWidgetUI(pid: pid_t) -> Bool
    func hasWidgetDescendant(root: AXUIElement) -> Bool
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

    func setPosition(_ element: AXUIElement, point: CGPoint) -> AXError {
        var point = point
        let value = AXValueCreate(.cgPoint, &point)!
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func firstElement(root: AXUIElement, targetSubroles: [String]) -> AXUIElement? {
        if let preferredMatch = firstMatchingElement(
            roots: [root],
            childProvider: { preferredChildren(of: $0) },
            targetSubroles: targetSubroles
        ) {
            return preferredMatch
        }

        return firstMatchingElement(
            roots: [root],
            childProvider: { fallbackChildren(of: $0) },
            targetSubroles: targetSubroles
        )
    }

    func hasSystemWideFocusedApplication(pid: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplicationRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApplicationRef) == .success,
              let focusedApplicationRef else {
            return false
        }
        let focusedApplication = focusedApplicationRef as! AXUIElement
        var focusedApplicationPID: pid_t = 0
        AXUIElementGetPid(focusedApplication, &focusedApplicationPID)
        return focusedApplicationPID == pid
    }

    func hasSystemWideFocusedWindow(pid: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindowRef else {
            return false
        }
        let focusedWindow = focusedWindowRef as! AXUIElement
        var focusedWindowPID: pid_t = 0
        AXUIElementGetPid(focusedWindow, &focusedWindowPID)
        return focusedWindowPID == pid
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
        return hasWidgetIdentifier(roots: [axApp])
    }

    func hasWidgetDescendant(root: AXUIElement) -> Bool {
        hasWidgetIdentifier(roots: [root])
    }

    private func hasWidgetIdentifier(roots: [AXUIElement]) -> Bool {
        return TreeTraversal.firstMatchingNode(
            roots: roots,
            childProvider: { fallbackChildren(of: $0) },
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

    private func firstMatchingElement(
        roots: [AXUIElement],
        childProvider: (AXUIElement) -> [AXUIElement],
        targetSubroles: [String]
    ) -> AXUIElement? {
        TreeTraversal.firstMatchingNode(
            roots: roots,
            childProvider: childProvider,
            matches: { element in
                guard let subrole = subrole(of: element) else {
                    return false
                }
                return targetSubroles.contains(subrole)
            }
        )
    }

    private func preferredChildren(of element: AXUIElement) -> [AXUIElement] {
        var combined: [AXUIElement] = []
        var seen: Set<AXUIElement> = []

        for attribute in NotificationCenterAXTraversalPolicy.descendantAttributes {
            for child in attributeElements(of: element, attribute: attribute) where seen.insert(child).inserted {
                combined.append(child)
            }
        }

        return combined
    }

    private func fallbackChildren(of element: AXUIElement) -> [AXUIElement] {
        var combined = preferredChildren(of: element)
        var seen = Set(combined)

        for attribute in attributeNames(of: element)
            where NotificationCenterAXTraversalPolicy.shouldInspectFallbackAttribute(attribute)
        {
            for child in attributeElements(of: element, attribute: attribute) where seen.insert(child).inserted {
                combined.append(child)
            }
        }

        return combined
    }

    private func attributeElements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let valueRef else {
            return []
        }

        if let children = valueRef as? [AXUIElement] {
            return children
        }

        if CFGetTypeID(valueRef) == AXUIElementGetTypeID() {
            let child = unsafeBitCast(valueRef, to: AXUIElement.self)
            return [child]
        }

        return []
    }

    private func attributeNames(of element: AXUIElement) -> [String] {
        var attributeNamesRef: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributeNamesRef) == .success,
              let attributeNamesRef,
              let attributeNames = attributeNamesRef as? [String] else {
            return []
        }
        return attributeNames
    }
}
