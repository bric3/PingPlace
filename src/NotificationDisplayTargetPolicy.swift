enum NotificationDisplayTargetPolicy {
    static func showsDisplaySelector(
        isPortableMac: Bool,
        screens: [ScreenDescriptor]
    ) -> Bool {
        isPortableMac && screens.contains(where: \.isBuiltIn)
    }

    static func effectiveTarget(
        requestedTarget: NotificationDisplayTarget,
        isPortableMac: Bool,
        screens: [ScreenDescriptor]
    ) -> NotificationDisplayTarget {
        guard requestedTarget == .builtInDisplay else { return requestedTarget }
        return showsDisplaySelector(isPortableMac: isPortableMac, screens: screens) ? .builtInDisplay : .mainDisplay
    }

    static func sectionTitle(
        isPortableMac: Bool,
        screens: [ScreenDescriptor]
    ) -> String {
        showsDisplaySelector(isPortableMac: isPortableMac, screens: screens)
            ? "Position"
            : "Position on the Main Display"
    }
}
