enum NotificationPositionGridLayout {
    static let rows: [[NotificationPosition]] = [
        [.topLeft, .topMiddle, .topRight],
        [.middleLeft, .deadCenter, .middleRight],
        [.bottomLeft, .bottomMiddle, .bottomRight],
    ]

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
}
