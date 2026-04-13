import Cocoa

final class NotificationPositionPickerView: NSView {
    private enum Metrics {
        static let contentInsets = NSEdgeInsets(top: 14, left: 22, bottom: 16, right: 0)
        static let titleHeight: CGFloat = 18
        static let statusHeight: CGFloat = 16
        static let verticalSpacing: CGFloat = 8
        static let gridHeight: CGFloat = 144
        static let gridSize = NotificationPositionGridLayout.screenGridSize(forHeight: gridHeight)
        static let cellSpacing: CGFloat = 6
        static let preferredSize = CGSize(
            width: contentInsets.left + gridSize.width + 12,
            height: 230
        )
        static let screenCornerRadius: CGFloat = 8
        static let zoneCornerRadius: CGFloat = screenCornerRadius
        static let indicatorSize = CGSize(width: 28, height: 13)
        static let indicatorInset: CGFloat = 8
    }

    private let onSelect: (NotificationPosition) -> Void
    private var trackingAreasByPosition: [NSTrackingArea] = []
    private var previousAcceptsMouseMovedEvents: Bool?
    private(set) var hoveredPosition: NotificationPosition?

    var selectedPosition: NotificationPosition {
        didSet {
            needsDisplay = true
        }
    }

    init(selectedPosition: NotificationPosition, onSelect: @escaping (NotificationPosition) -> Void) {
        self.selectedPosition = selectedPosition
        self.onSelect = onSelect
        super.init(frame: CGRect(origin: .zero, size: Metrics.preferredSize))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Metrics.preferredSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window {
            if previousAcceptsMouseMovedEvents == nil {
                previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
            }
            window.acceptsMouseMovedEvents = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for existingTrackingArea in trackingAreasByPosition {
            removeTrackingArea(existingTrackingArea)
        }
        trackingAreasByPosition.removeAll()

        for row in 0 ..< NotificationPositionGridLayout.rows.count {
            for column in 0 ..< NotificationPositionGridLayout.rows[row].count {
                guard let position = NotificationPositionGridLayout.position(row: row, column: column) else {
                    continue
                }
                let area = NSTrackingArea(
                    rect: cellRect(row: row, column: column),
                    options: [.activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag],
                    owner: self,
                    userInfo: ["position": position.rawValue]
                )
                addTrackingArea(area)
                trackingAreasByPosition.append(area)
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hoveredPosition = position(from: event.trackingArea?.userInfo)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !gridFrame.contains(point) else {
            return
        }
        hoveredPosition = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let position = position(at: point) else {
            return
        }

        selectedPosition = position
        hoveredPosition = position
        onSelect(position)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        drawTitle()
        drawStatusText()
        drawGrid()
    }

    private func drawTitle() {
        let titleRect = CGRect(
            x: Metrics.contentInsets.left,
            y: bounds.height - Metrics.contentInsets.top - Metrics.titleHeight,
            width: bounds.width - Metrics.contentInsets.left - Metrics.contentInsets.right,
            height: Metrics.titleHeight
        )

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let title = NSString(string: "Position on the Main Display")
        title.draw(in: titleRect, withAttributes: titleAttributes)
    }

    private func drawStatusText() {
        let statusRect = CGRect(
            x: Metrics.contentInsets.left,
            y: Metrics.contentInsets.bottom,
            width: bounds.width - Metrics.contentInsets.left - Metrics.contentInsets.right,
            height: Metrics.statusHeight
        )

        let label: String
        if let hoveredPosition {
            label = "Change to \(hoveredPosition.displayName)"
        } else {
            label = "Current: \(selectedPosition.displayName)"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: hoveredPosition == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        NSString(string: label).draw(in: statusRect, withAttributes: attributes)
    }

    private func drawGrid() {
        drawScreenBackground()

        for row in 0 ..< NotificationPositionGridLayout.rows.count {
            for column in 0 ..< NotificationPositionGridLayout.rows[row].count {
                guard let position = NotificationPositionGridLayout.position(row: row, column: column) else {
                    continue
                }
                drawCell(atRow: row, column: column, position: position)
            }
        }
    }

    private func drawScreenBackground() {
        let screenPath = NSBezierPath(
            roundedRect: gridFrame,
            xRadius: Metrics.screenCornerRadius,
            yRadius: Metrics.screenCornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        screenPath.addClip()

        let gradient = NSGradient(colors: screenWallpaperColors())!
        gradient.draw(in: gridFrame, angle: 135)

        NSGraphicsContext.restoreGraphicsState()

        screenBorderColor().setStroke()
        screenPath.lineWidth = 1
        screenPath.stroke()
    }

    private func drawCell(atRow row: Int, column: Int, position: NotificationPosition) {
        let cellRect = self.cellRect(row: row, column: column)
        let cellPath = NSBezierPath(
            roundedRect: cellRect,
            xRadius: Metrics.zoneCornerRadius,
            yRadius: Metrics.zoneCornerRadius
        )

        let isSelected = position == selectedPosition
        let isHovered = position == hoveredPosition

        let fillColor: NSColor
        if isSelected {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.13)
        } else if isHovered {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.22)
        } else {
            fillColor = zoneFillColor()
        }

        fillColor.setFill()
        cellPath.fill()

        let strokeColor: NSColor = isSelected ? .controlAccentColor : zoneBorderColor()
        strokeColor.setStroke()
        cellPath.lineWidth = isSelected ? 1.5 : 1
        cellPath.stroke()

        if indicatorPosition == position {
            let indicatorRect = self.indicatorRect(in: cellRect, position: position)
            let indicatorPath = NSBezierPath(roundedRect: indicatorRect, xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
            indicatorPath.fill()
        }
    }

    private var gridFrame: CGRect {
        CGRect(
            x: Metrics.contentInsets.left,
            y: Metrics.contentInsets.bottom + Metrics.statusHeight + Metrics.verticalSpacing,
            width: Metrics.gridSize.width,
            height: Metrics.gridSize.height
        )
    }

    private var indicatorPosition: NotificationPosition? {
        hoveredPosition ?? selectedPosition
    }

    private func cellRect(row: Int, column: Int) -> CGRect {
        let totalSpacing = Metrics.cellSpacing * 2
        let cellWidth = (Metrics.gridSize.width - totalSpacing) / 3
        let cellHeight = (Metrics.gridSize.height - totalSpacing) / 3
        let x = gridFrame.minX + CGFloat(column) * (cellWidth + Metrics.cellSpacing)
        let y = gridFrame.maxY - cellHeight - CGFloat(row) * (cellHeight + Metrics.cellSpacing)
        return CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
    }

    private func position(at point: CGPoint) -> NotificationPosition? {
        for row in 0 ..< NotificationPositionGridLayout.rows.count {
            for column in 0 ..< NotificationPositionGridLayout.rows[row].count {
                let rect = cellRect(row: row, column: column)
                if rect.contains(point) {
                    return NotificationPositionGridLayout.position(row: row, column: column)
                }
            }
        }
        return nil
    }

    private func position(from userInfo: [AnyHashable: Any]?) -> NotificationPosition? {
        guard let rawValue = userInfo?["position"] as? String else {
            return nil
        }
        return NotificationPosition(rawValue: rawValue)
    }

    private func indicatorRect(in cellRect: CGRect, position: NotificationPosition) -> CGRect {
        let gridIndex = NotificationPositionGridLayout.gridIndex(for: position)

        let originX: CGFloat
        switch gridIndex.column {
        case 0:
            originX = cellRect.minX + Metrics.indicatorInset
        case 1:
            originX = cellRect.midX - Metrics.indicatorSize.width / 2
        default:
            originX = cellRect.maxX - Metrics.indicatorInset - Metrics.indicatorSize.width
        }

        let originY: CGFloat
        switch gridIndex.row {
        case 0:
            originY = cellRect.maxY - Metrics.indicatorInset - Metrics.indicatorSize.height
        case 1:
            originY = cellRect.midY - Metrics.indicatorSize.height / 2
        default:
            originY = cellRect.minY + Metrics.indicatorInset
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: Metrics.indicatorSize)
    }

    private func screenWallpaperColors() -> [NSColor] {
        if isDarkAppearance {
            return [
                NSColor(calibratedRed: 0.15, green: 0.21, blue: 0.34, alpha: 1),
                NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.28, alpha: 1),
                NSColor(calibratedRed: 0.21, green: 0.11, blue: 0.27, alpha: 1),
            ]
        }

        return [
            NSColor(calibratedRed: 0.78, green: 0.87, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.60, green: 0.79, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.71, blue: 0.84, alpha: 1),
        ]
    }

    private func screenBorderColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.14)
        }
        return NSColor.black.withAlphaComponent(0.10)
    }

    private func zoneFillColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.04)
        }
        return NSColor.white.withAlphaComponent(0.18)
    }

    private func zoneBorderColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.10)
        }
        return NSColor.black.withAlphaComponent(0.08)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
