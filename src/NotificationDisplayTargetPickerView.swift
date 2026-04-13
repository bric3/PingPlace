import Cocoa

final class NotificationDisplayTargetPickerView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 22
        static let contentInsets = NSEdgeInsets(top: 2, left: horizontalInset, bottom: 4, right: horizontalInset)
        static let controlHeight: CGFloat = 28
        static let preferredSize = CGSize(width: NotificationPositionPickerView.preferredMenuWidth, height: 34)
    }

    private let onSelect: (NotificationDisplayTarget) -> Void
    private let segmentedControl: NSSegmentedControl

    var selectedTarget: NotificationDisplayTarget {
        didSet {
            updateSelection()
        }
    }

    init(selectedTarget: NotificationDisplayTarget, onSelect: @escaping (NotificationDisplayTarget) -> Void) {
        self.selectedTarget = selectedTarget
        self.onSelect = onSelect
        segmentedControl = NSSegmentedControl(
            labels: NotificationDisplayTarget.allCases.map(\.displayName),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )

        super.init(frame: CGRect(origin: .zero, size: Metrics.preferredSize))

        segmentedControl.target = self
        segmentedControl.action = #selector(segmentedControlChanged(_:))
        segmentedControl.segmentStyle = .rounded
        segmentedControl.setWidth(92, forSegment: 0)
        segmentedControl.setWidth(112, forSegment: 1)
        addSubview(segmentedControl)
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Metrics.preferredSize
    }

    override func layout() {
        super.layout()

        segmentedControl.frame = CGRect(
            x: Metrics.contentInsets.left,
            y: Metrics.contentInsets.bottom,
            width: bounds.width - Metrics.contentInsets.left - Metrics.contentInsets.right,
            height: Metrics.controlHeight
        )
    }

    @objc private func segmentedControlChanged(_ sender: NSSegmentedControl) {
        let target = NotificationDisplayTarget.allCases[sender.selectedSegment]
        selectedTarget = target
        onSelect(target)
    }

    private func updateSelection() {
        segmentedControl.selectedSegment = NotificationDisplayTarget.allCases.firstIndex(of: selectedTarget) ?? 0
    }
}
