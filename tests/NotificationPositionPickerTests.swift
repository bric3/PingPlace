import CoreGraphics
import Foundation

func testGridLayoutReturnsExpectedPositionForTopLeftCell() throws {
    try assertEqual(
        NotificationPositionGridLayout.position(row: 0, column: 0),
        .topLeft,
        "grid top-left cell should map to top left"
    )
}

func testGridLayoutReturnsExpectedPositionForCenterCell() throws {
    try assertEqual(
        NotificationPositionGridLayout.position(row: 1, column: 1),
        .deadCenter,
        "grid center cell should map to middle"
    )
}

func testGridLayoutReturnsExpectedPositionForBottomRightCell() throws {
    try assertEqual(
        NotificationPositionGridLayout.position(row: 2, column: 2),
        .bottomRight,
        "grid bottom-right cell should map to bottom right"
    )
}

func testGridLayoutReturnsNilForOutOfBoundsCell() throws {
    try assertEqual(
        NotificationPositionGridLayout.position(row: 9, column: 9),
        nil,
        "out-of-bounds grid cell should return nil"
    )
}

func testGridLayoutReturnsExpectedGridIndexForMiddleRight() throws {
    let gridIndex = NotificationPositionGridLayout.gridIndex(for: .middleRight)
    try assertEqual(gridIndex.row, 1, "middle-right row")
    try assertEqual(gridIndex.column, 2, "middle-right column")
}

func testGridLayoutUsesScreenLikeAspectRatio() throws {
    let gridSize = NotificationPositionGridLayout.screenGridSize(forHeight: 144)

    try assertEqual(gridSize.height, 144, "screen grid height should match requested height")
    if !(gridSize.width > gridSize.height) {
        throw TestFailure.assertionFailed("screen grid should be wider than tall")
    }
    try assertEqual(
        gridSize.width,
        round(144 * NotificationPositionGridLayout.mainDisplayAspectRatio),
        "screen grid width should follow main display aspect ratio"
    )
}

func testGridLayoutUsesMacBookMainDisplayAspectRatio() throws {
    try assertEqual(
        NotificationPositionGridLayout.mainDisplayAspectRatio,
        1512.0 / 982.0,
        "grid should use the MacBook Pro 14-inch display aspect ratio"
    )
}
