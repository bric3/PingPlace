import CoreGraphics
import Foundation

private enum TestFailure: Error {
    case assertionFailed(String)
}

private func assertEqual(_ actual: CGFloat, _ expected: CGFloat, _ label: String, epsilon: CGFloat = 0.0001) throws {
    if abs(actual - expected) > epsilon {
        throw TestFailure.assertionFailed("\(label): expected \(expected), got \(actual)")
    }
}

private func testInitialPositionInBounds() throws {
    let result = NotificationGeometry.effectiveInitialPosition(
        position: CGPoint(x: 1700, y: 100),
        notifSize: CGSize(width: 200, height: 60),
        screenWidth: 1920
    )
    try assertEqual(result.position.x, 1700, "initial in-bounds x")
    try assertEqual(result.padding, 20, "initial in-bounds padding")
}

private func testInitialPositionRecomputedWhenOutOfBounds() throws {
    let result = NotificationGeometry.effectiveInitialPosition(
        position: CGPoint(x: 1900, y: 100),
        notifSize: CGSize(width: 300, height: 60),
        screenWidth: 1920
    )
    try assertEqual(result.position.x, 1604, "initial overflow recomputed x")
    try assertEqual(result.padding, 16, "initial overflow default padding")
}

private func testTopLeftPlacement() throws {
    let result = NotificationGeometry.newPosition(
        currentPosition: .topLeft,
        windowSize: CGSize(width: 1920, height: 1080),
        notifSize: CGSize(width: 320, height: 90),
        position: CGPoint(x: 1500, y: 0),
        padding: 100,
        dockSize: 40,
        paddingAboveDock: 30
    )
    try assertEqual(result.x, -1400, "top-left x")
    try assertEqual(result.y, 0, "top-left y")
}

private func testDeadCenterPlacement() throws {
    let result = NotificationGeometry.newPosition(
        currentPosition: .deadCenter,
        windowSize: CGSize(width: 1920, height: 1080),
        notifSize: CGSize(width: 320, height: 80),
        position: CGPoint(x: 1000, y: 0),
        padding: 80,
        dockSize: 40,
        paddingAboveDock: 30
    )
    try assertEqual(result.x, -200, "dead-center x")
    try assertEqual(result.y, 460, "dead-center y")
}

private func testBottomRightPlacement() throws {
    let result = NotificationGeometry.newPosition(
        currentPosition: .bottomRight,
        windowSize: CGSize(width: 1920, height: 1080),
        notifSize: CGSize(width: 300, height: 80),
        position: CGPoint(x: 1500, y: 0),
        padding: 80,
        dockSize: 40,
        paddingAboveDock: 30
    )
    try assertEqual(result.x, 0, "bottom-right x")
    try assertEqual(result.y, 930, "bottom-right y")
}

@main
struct NotificationGeometryTestRunner {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("initial position in bounds", testInitialPositionInBounds),
            ("initial position overflow", testInitialPositionRecomputedWhenOutOfBounds),
            ("top-left placement", testTopLeftPlacement),
            ("dead-center placement", testDeadCenterPlacement),
            ("bottom-right placement", testBottomRightPlacement),
        ]

        do {
            for (_, test) in tests {
                try test()
            }
            print("All \(tests.count) tests passed.")
        } catch let TestFailure.assertionFailed(message) {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        } catch {
            fputs("Unexpected test failure: \(error)\n", stderr)
            exit(1)
        }
    }
}
