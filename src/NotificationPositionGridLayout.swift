import Foundation

enum NotificationPositionGridLayout {
    static let rows: [[NotificationPosition]] = [
        [.topLeft, .topMiddle, .topRight],
        [.middleLeft, .deadCenter, .middleRight],
        [.bottomLeft, .bottomMiddle, .bottomRight],
    ]
    // MacBook Pro 14-inch Liquid Retina XDR display aspect ratio in points.
    static let mainDisplayAspectRatio: CGFloat = 1512.0 / 982.0

    static func position(row: Int, column: Int) -> NotificationPosition? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else {
            return nil
        }
        return rows[row][column]
    }

    static func gridIndex(for position: NotificationPosition) -> (row: Int, column: Int) {
        for (rowIndex, row) in rows.enumerated() {
            if let columnIndex = row.firstIndex(of: position) {
                return (rowIndex, columnIndex)
            }
        }
        return (1, 1)
    }

    static func screenGridSize(forHeight height: CGFloat) -> CGSize {
        CGSize(width: round(height * mainDisplayAspectRatio), height: height)
    }
}
