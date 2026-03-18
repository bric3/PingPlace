import CoreGraphics

enum ScreenResolutionPolicy {
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

        return screens.first(where: \.isMain) ?? screens.first
    }

    static func dockSize(for screen: ScreenDescriptor) -> CGFloat {
        screen.frame.height - screen.visibleFrame.height
    }
}
