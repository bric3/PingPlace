import CoreGraphics

enum ScreenResolutionPolicy {
    static func accessibilityRect(
        from cocoaRect: CGRect,
        globalTopEdge: CGFloat
    ) -> CGRect {
        CGRect(
            x: cocoaRect.origin.x,
            y: globalTopEdge - cocoaRect.maxY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    static func preferredScreen(
        target: NotificationDisplayTarget,
        screens: [ScreenDescriptor]
    ) -> ScreenDescriptor? {
        guard !screens.isEmpty else { return nil }

        switch target {
        case .mainDisplay:
            return screens.first(where: \.isMain) ?? screens.first
        case .builtInDisplay:
            return screens.first(where: \.isBuiltIn) ?? screens.first(where: \.isMain) ?? screens.first
        }
    }

    static func resolveScreen(
        position: CGPoint,
        windowSize: CGSize,
        screens: [ScreenDescriptor],
        tolerance: CGFloat = 40
    ) -> ScreenDescriptor? {
        guard !screens.isEmpty else { return nil }

        if let byPosition = screens.first(where: { $0.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(position) }) {
            return byPosition
        }

        if let bySize = screens.first(where: {
            abs($0.frame.width - windowSize.width) < 1 && abs($0.frame.height - windowSize.height) < 1
        }) {
            return bySize
        }

        return preferredScreen(target: .mainDisplay, screens: screens)
    }

    static func dockSize(for screen: ScreenDescriptor) -> CGFloat {
        screen.frame.height - screen.visibleFrame.height
    }
}
