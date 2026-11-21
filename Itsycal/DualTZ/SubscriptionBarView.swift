//
//  SubscriptionBarView.swift
//  Itsycal DualTZ
//

import Cocoa

private final class CircularRingView: NSView {
    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()
    private let centerLabel = NSTextField(labelWithString: "")

    private var ringColor: NSColor = .systemBlue
    private var progress: Double = 0.5

    init(diameter: CGFloat, fontSize: CGFloat, lineWidth: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.lineWidth = lineWidth
        layer?.addSublayer(trackLayer)

        arcLayer.fillColor = NSColor.clear.cgColor
        arcLayer.lineWidth = lineWidth
        arcLayer.lineCap = .round
        layer?.addSublayer(arcLayer)

        centerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        centerLabel.alignment = .center
        centerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            centerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(progress: Double, centerText: String, color: NSColor) {
        self.progress = min(1.0, max(0.05, progress))
        self.ringColor = color
        centerLabel.stringValue = centerText
        centerLabel.textColor = color
        needsLayout = true
        refreshColors()
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: trackLayer.lineWidth / 2 + 0.5, dy: trackLayer.lineWidth / 2 + 0.5)
        guard rect.width > 2 && rect.height > 2 else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = CGFloat.pi / 2
        let endAngle = startAngle - CGFloat(progress) * 2 * CGFloat.pi

        let trackPath = CGMutablePath()
        trackPath.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        trackLayer.path = trackPath

        let arcPath = CGMutablePath()
        arcPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        arcLayer.path = arcPath
    }

    private func refreshColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        trackLayer.strokeColor = (isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.11)).cgColor
        arcLayer.strokeColor = ringColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

private final class SubscriptionCompactPill: NSView {
    private let ring = CircularRingView(diameter: 22, fontSize: 8.5, lineWidth: 2.3)
    private let nameLabel = NSTextField(labelWithString: "")

    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = Theme.currentMonthTextColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(730), for: .horizontal)

        let stack = NSStackView(views: [ring, nameLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: SubscriptionScheduleSnapshot) {
        let color: NSColor = snapshot.isUrgent ? .systemOrange : .systemBlue
        ring.update(progress: snapshot.progressRatio, centerText: snapshot.etaShortText, color: color)
        nameLabel.stringValue = snapshot.item.customName
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick?()
        }
    }

    func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.075)
            : NSColor.white.withAlphaComponent(0.48)).cgColor
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}

private final class SubscriptionGridCard: NSView {
    private let ring = CircularRingView(diameter: 28, fontSize: 9.5, lineWidth: 2.6)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    var subscriptionID: String = ""
    var onSelect: ((String) -> Void)?
    var isFocusedCard: Bool = false {
        didSet { refreshAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Theme.currentMonthTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(730), for: .horizontal)

        subLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        subLabel.textColor = Theme.agendaEventDateTextColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(720), for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1.5

        let row = NSStackView(views: [ring, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: SubscriptionScheduleSnapshot, isSelected: Bool) {
        subscriptionID = snapshot.item.id
        isFocusedCard = isSelected
        let color: NSColor = snapshot.isUrgent ? .systemOrange : .systemBlue
        ring.update(progress: snapshot.progressRatio, centerText: snapshot.etaShortText, color: color)
        titleLabel.stringValue = snapshot.item.customName
        subLabel.stringValue = "\(snapshot.item.region.flag) \(snapshot.item.priceText) · \(snapshot.dueShortDateText)"
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onSelect?(subscriptionID)
        }
    }

    func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isFocusedCard {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.16 : 0.10).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        } else {
            layer?.backgroundColor = (isDark
                ? NSColor.white.withAlphaComponent(0.065)
                : NSColor.white.withAlphaComponent(0.46)).cgColor
            layer?.borderColor = (isDark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}

@objcMembers
final class SubscriptionBarView: NSView {
    private let topDivider = NSView()
    private let rootStack = NSStackView()
    private let compactRow = NSStackView()
    private let compactPillsStack = NSStackView()
    private let expandBtn = NSButton(title: "", target: nil, action: nil)

    private let expandedHeaderRow = NSStackView()
    private let expandedTitleLabel = NSTextField(labelWithString: "")
    private let collapseBtn = NSButton(title: "", target: nil, action: nil)
    private let expandedGridStack = NSStackView()

    private let detailBar = NSView()
    private let detailDot = NSView()
    private let detailLabel = NSTextField(labelWithString: "")

    private var focusedSubID: String?
    private var compactPills: [SubscriptionCompactPill] = []
    private var gridCards: [SubscriptionGridCard] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        refresh()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        // 紧凑微环行
        compactPillsStack.orientation = .horizontal
        compactPillsStack.spacing = 6
        compactPillsStack.alignment = .centerY

        expandBtn.bezelStyle = .rounded
        expandBtn.controlSize = .small
        expandBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        expandBtn.target = self
        expandBtn.action = #selector(toggleExpand(_:))

        let compactSpacer = NSView()
        compactSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        compactSpacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        compactRow.orientation = .horizontal
        compactRow.alignment = .centerY
        compactRow.spacing = 6
        compactRow.addArrangedSubview(compactPillsStack)
        compactRow.addArrangedSubview(compactSpacer)
        compactRow.addArrangedSubview(expandBtn)

        // 展开态标题行
        expandedTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        expandedTitleLabel.textColor = Theme.agendaEventDateTextColor

        collapseBtn.bezelStyle = .rounded
        collapseBtn.controlSize = .small
        collapseBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        collapseBtn.target = self
        collapseBtn.action = #selector(toggleExpand(_:))

        let expSpacer = NSView()
        expSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        expSpacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        expandedHeaderRow.orientation = .horizontal
        expandedHeaderRow.alignment = .centerY
        expandedHeaderRow.addArrangedSubview(expandedTitleLabel)
        expandedHeaderRow.addArrangedSubview(expSpacer)
        expandedHeaderRow.addArrangedSubview(collapseBtn)

        expandedGridStack.orientation = .vertical
        expandedGridStack.alignment = .leading
        expandedGridStack.spacing = 6

        // 渐进披露单行详情条
        detailBar.wantsLayer = true
        detailBar.layer?.cornerRadius = 7
        detailBar.layer?.cornerCurve = .continuous

        detailDot.wantsLayer = true
        detailDot.layer?.cornerRadius = 3
        detailDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            detailDot.widthAnchor.constraint(equalToConstant: 6),
            detailDot.heightAnchor.constraint(equalToConstant: 6)
        ])

        detailLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        detailLabel.textColor = Theme.agendaEventDateTextColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(720), for: .horizontal)

        let detailRow = NSStackView(views: [detailDot, detailLabel])
        detailRow.orientation = .horizontal
        detailRow.alignment = .centerY
        detailRow.spacing = 6
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        detailBar.addSubview(detailRow)
        NSLayoutConstraint.activate([
            detailRow.topAnchor.constraint(equalTo: detailBar.topAnchor, constant: 5),
            detailRow.bottomAnchor.constraint(equalTo: detailBar.bottomAnchor, constant: -5),
            detailRow.leadingAnchor.constraint(equalTo: detailBar.leadingAnchor, constant: 8),
            detailRow.trailingAnchor.constraint(equalTo: detailBar.trailingAnchor, constant: -8)
        ])

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(compactRow)
        rootStack.addArrangedSubview(expandedHeaderRow)
        rootStack.addArrangedSubview(expandedGridStack)
        rootStack.addArrangedSubview(detailBar)

        compactRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        expandedHeaderRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        expandedGridStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        detailBar.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        addSubview(topDivider)
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            rootStack.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 7),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        refreshAppearance()
    }

    @objc private func toggleExpand(_ sender: Any?) {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: kDualTZSubscriptionBarExpanded), forKey: kDualTZSubscriptionBarExpanded)
    }

    func refresh() {
        let snaps = SubscriptionStore.activeSnapshots()
        let expanded = UserDefaults.standard.bool(forKey: kDualTZSubscriptionBarExpanded)

        expandBtn.title = LocalizationService.pick("展开 ▾", "More ▾")
        collapseBtn.title = LocalizationService.pick("收起 ▴", "Less ▴")
        expandedTitleLabel.stringValue = LocalizationService.pick("订阅扣费追踪", "Subscriptions")

        if snaps.isEmpty {
            compactRow.isHidden = false
            expandedHeaderRow.isHidden = true
            expandedGridStack.isHidden = true
            detailBar.isHidden = true
            rebuildCompactPills(with: [])
            expandBtn.isHidden = true
            return
        }

        expandBtn.isHidden = false
        if focusedSubID == nil || !snaps.contains(where: { $0.item.id == focusedSubID }) {
            focusedSubID = snaps.first?.item.id
        }

        compactRow.isHidden = expanded
        expandedHeaderRow.isHidden = !expanded
        expandedGridStack.isHidden = !expanded
        detailBar.isHidden = !expanded

        if expanded {
            rebuildGrid(with: snaps)
            updateDetailBar(with: snaps)
        } else {
            rebuildCompactPills(with: Array(snaps.prefix(2)))
        }
    }

    private func rebuildCompactPills(with snaps: [SubscriptionScheduleSnapshot]) {
        compactPills.removeAll()
        compactPillsStack.arrangedSubviews.forEach {
            compactPillsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if snaps.isEmpty {
            let emptyLabel = NSTextField(labelWithString: LocalizationService.pick("尚未添加订阅（可在设置页管理）", "No active subscriptions"))
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = Theme.noncurrentMonthTextColor
            compactPillsStack.addArrangedSubview(emptyLabel)
            return
        }
        for snap in snaps {
            let pill = SubscriptionCompactPill()
            pill.apply(snapshot: snap)
            pill.onClick = { [weak self] in
                self?.focusedSubID = snap.item.id
                UserDefaults.standard.set(true, forKey: kDualTZSubscriptionBarExpanded)
            }
            compactPills.append(pill)
            compactPillsStack.addArrangedSubview(pill)
        }
    }

    private func rebuildGrid(with snaps: [SubscriptionScheduleSnapshot]) {
        gridCards.removeAll()
        expandedGridStack.arrangedSubviews.forEach {
            expandedGridStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var idx = 0
        while idx < snaps.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6

            let c1 = SubscriptionGridCard()
            c1.apply(snapshot: snaps[idx], isSelected: snaps[idx].item.id == focusedSubID)
            c1.onSelect = { [weak self] sid in
                self?.focusedSubID = sid
                self?.refreshFocusOnly(snaps: snaps)
            }
            gridCards.append(c1)
            row.addArrangedSubview(c1)

            if idx + 1 < snaps.count {
                let c2 = SubscriptionGridCard()
                c2.apply(snapshot: snaps[idx + 1], isSelected: snaps[idx + 1].item.id == focusedSubID)
                c2.onSelect = { [weak self] sid in
                    self?.focusedSubID = sid
                    self?.refreshFocusOnly(snaps: snaps)
                }
                gridCards.append(c2)
                row.addArrangedSubview(c2)
            } else {
                row.addArrangedSubview(NSView())
            }
            expandedGridStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: expandedGridStack.widthAnchor).isActive = true
            idx += 2
        }
    }

    private func refreshFocusOnly(snaps: [SubscriptionScheduleSnapshot]) {
        for card in gridCards {
            card.isFocusedCard = (card.subscriptionID == focusedSubID)
        }
        updateDetailBar(with: snaps)
    }

    private func updateDetailBar(with snaps: [SubscriptionScheduleSnapshot]) {
        guard let focused = snaps.first(where: { $0.item.id == focusedSubID }) ?? snaps.first else {
            detailBar.isHidden = true
            return
        }
        detailDot.layer?.backgroundColor = (focused.isUrgent ? NSColor.systemOrange : NSColor.systemBlue).cgColor
        detailLabel.stringValue = "\(focused.item.customName) · \(focused.item.accountEmail) · \(focused.item.paymentMethod) · \(focused.dueDetailText)"
    }

    private func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        topDivider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        detailBar.layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.055)
            : NSColor.black.withAlphaComponent(0.04)).cgColor
        compactPills.forEach { $0.refreshAppearance() }
        gridCards.forEach { $0.refreshAppearance() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}
