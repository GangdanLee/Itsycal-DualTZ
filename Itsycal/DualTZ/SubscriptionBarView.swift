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
    private var progress: Double = 0.0
    private let baseFontSize: CGFloat

    init(diameter: CGFloat, fontSize: CGFloat, lineWidth: CGFloat) {
        self.baseFontSize = fontSize
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

    func update(progress: Double?, centerText: String, color: NSColor) {
        if let progress {
            self.progress = min(1.0, max(0.04, progress))
        } else {
            self.progress = 0.0
        }
        self.ringColor = color
        let fittedFontSize = centerText.count >= 3 ? max(7.0, baseFontSize - 1.5) : baseFontSize
        centerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: fittedFontSize, weight: .bold)
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
        let trackPath = CGMutablePath()
        trackPath.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        trackLayer.path = trackPath

        if progress > 0.001 {
            let startAngle = CGFloat.pi / 2
            let endAngle = startAngle - CGFloat(progress) * 2 * CGFloat.pi
            let arcPath = CGMutablePath()
            arcPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            arcLayer.path = arcPath
        } else {
            arcLayer.path = nil
        }
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

private enum BarFocusedTarget: Equatable {
    case ai(String)
    case subscription(String)

    var rawID: String {
        switch self {
        case .ai(let id): return "ai:\(id)"
        case .subscription(let id): return "sub:\(id)"
        }
    }
}

private final class CompactRingPill: NSView {
    private let ring = CircularRingView(diameter: 22, fontSize: 8.5, lineWidth: 2.3)
    private let nameLabel = NSTextField(labelWithString: "")

    var onClick: (() -> Void)?
    private var didMouseDownInside = false

    convenience init(fixedWidth: CGFloat? = nil) {
        self.init(frame: .zero, fixedWidth: fixedWidth)
    }

    init(frame frameRect: NSRect, fixedWidth: CGFloat? = nil) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        nameLabel.font = NSFont.systemFont(ofSize: 9.0, weight: .medium)
        nameLabel.textColor = Theme.currentMonthTextColor
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let stack = NSStackView(views: [ring, nameLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ]
        if let fixedWidth {
            constraints.append(widthAnchor.constraint(equalToConstant: fixedWidth))
        } else {
            constraints.append(widthAnchor.constraint(greaterThanOrEqualToConstant: 42))
            setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        }
        NSLayoutConstraint.activate(constraints)
        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: SubscriptionScheduleSnapshot) {
        let color: NSColor = snapshot.isUrgent ? .systemOrange : .systemBlue
        ring.update(progress: snapshot.progressRatio, centerText: snapshot.etaShortText, color: color)
        nameLabel.stringValue = snapshot.item.customName
        nameLabel.textColor = Theme.currentMonthTextColor
        toolTip = "\(snapshot.item.customName) · \(snapshot.item.region.flag) \(snapshot.item.priceText) · \(snapshot.dueShortDateText) (\(snapshot.etaShortText))"
    }

    func apply(account: AIQuotaAccount, snapshot: AIQuotaSnapshot?) {
        var tipParts: [String] = ["\(account.customName) (\(account.provider.displayName))"]
        if let snap = snapshot {
            let dName = snap.accountDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = snap.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dName, !dName.isEmpty, let email, !email.isEmpty {
                tipParts.append("\(dName) (\(email))")
            } else if let email, !email.isEmpty {
                tipParts.append(email)
            } else if let dName, !dName.isEmpty {
                tipParts.append(dName)
            }
        }
        if let pct = snapshot?.displayRemainingPercent(for: account.provider) {
            let color = snapshot?.displayRingColor(provider: account.provider) ?? account.provider.accentColor
            ring.update(progress: pct / 100.0, centerText: "\(Int(round(pct)))", color: color)
            nameLabel.textColor = Theme.currentMonthTextColor
            if let snap = snapshot {
                if let dual = snap.dualWindowSummaryText() {
                    tipParts.append(LocalizationService.pick("剩余 \(dual)", "Left \(dual)"))
                } else {
                    tipParts.append(LocalizationService.pick("剩余 \(snap.primaryWindowLabel) \(Int(round(pct)))%", "Left \(snap.primaryWindowLabel) \(Int(round(pct)))%"))
                }
                if let reset = snap.formattedResetText(for: account.provider, includeTimeZoneName: true) {
                    tipParts.append(reset)
                }
            }
        } else {
            ring.update(progress: nil, centerText: "--", color: .secondaryLabelColor)
            nameLabel.textColor = Theme.agendaEventDateTextColor
            if let msg = snapshot?.statusMessage, !msg.isEmpty {
                tipParts.append(msg)
            } else {
                tipParts.append(LocalizationService.pick("点击查看详情或刷新", "Click to view details"))
            }
        }
        nameLabel.stringValue = account.customName
        toolTip = tipParts.joined(separator: " · ")
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        didMouseDownInside = bounds.contains(pt)
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let shouldFire = didMouseDownInside && bounds.contains(pt)
        didMouseDownInside = false
        if shouldFire {
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

private final class BentoGridCard: NSView {
    private let ring: CircularRingView
    private let dotBadge = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    var target: BarFocusedTarget?
    var onSelect: ((BarFocusedTarget) -> Void)?
    private var didMouseDownInside = false
    var isFocusedCard: Bool = false {
        didSet { refreshAppearance() }
    }

    init(ringDiameter: CGFloat = 28) {
        self.ring = CircularRingView(diameter: ringDiameter, fontSize: 9.5, lineWidth: 2.6)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75

        dotBadge.wantsLayer = true
        dotBadge.layer?.cornerRadius = 2.5
        dotBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotBadge.widthAnchor.constraint(equalToConstant: 5),
            dotBadge.heightAnchor.constraint(equalToConstant: 5)
        ])

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Theme.currentMonthTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        titleLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(240), for: .horizontal)

        let titleRow = NSStackView(views: [dotBadge, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 4

        subLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        subLabel.textColor = Theme.agendaEventDateTextColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        subLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(240), for: .horizontal)

        let textStack = NSStackView(views: [titleRow, subLabel])
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

    func apply(subscription snapshot: SubscriptionScheduleSnapshot, isSelected: Bool) {
        target = .subscription(snapshot.item.id)
        isFocusedCard = isSelected
        dotBadge.isHidden = true
        let color: NSColor = snapshot.isUrgent ? .systemOrange : .systemBlue
        ring.update(progress: snapshot.progressRatio, centerText: snapshot.etaShortText, color: color)
        titleLabel.stringValue = snapshot.item.customName
        subLabel.stringValue = "\(snapshot.item.region.flag) \(snapshot.item.priceText) · \(snapshot.dueShortDateText)"
    }

    func apply(account: AIQuotaAccount, snapshot: AIQuotaSnapshot?, isSelected: Bool) {
        target = .ai(account.id)
        isFocusedCard = isSelected
        dotBadge.isHidden = false
        dotBadge.layer?.backgroundColor = account.provider.accentColor.cgColor

        if let snap = snapshot, let pct = snap.displayRemainingPercent(for: account.provider) {
            let color = snap.displayRingColor(provider: account.provider)
            ring.update(progress: pct / 100.0, centerText: "\(Int(round(pct)))", color: color)
            if let dual = snap.dualWindowSummaryText() {
                subLabel.stringValue = dual
            } else if snap.state == .cached {
                subLabel.stringValue = snap.statusMessage ?? LocalizationService.pick("缓存 · \(Int(round(pct)))%", "Cached · \(Int(round(pct)))%")
            } else if let resetText = snap.formattedResetText(for: account.provider) {
                subLabel.stringValue = resetText
            } else {
                subLabel.stringValue = "\(snap.primaryWindowLabel) \(Int(round(pct)))%"
            }
        } else {
            ring.update(progress: nil, centerText: "--", color: .secondaryLabelColor)
            if let snap = snapshot, let msg = snap.statusMessage, !msg.isEmpty {
                subLabel.stringValue = msg
            } else if let snap = snapshot, snap.isExpiredCycleCache {
                subLabel.stringValue = LocalizationService.pick("周期已过 · 待同步", "Cycle passed · Sync")
            } else {
                subLabel.stringValue = LocalizationService.pick("待刷新", "Tap refresh")
            }
        }
        titleLabel.stringValue = account.customName
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        didMouseDownInside = bounds.contains(pt)
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let shouldFire = didMouseDownInside && bounds.contains(pt)
        didMouseDownInside = false
        if shouldFire, let target {
            onSelect?(target)
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
    private let compactRow = NSView()
    private let compactPillsStack = NSStackView()
    private let compactActionsStack = NSStackView()
    private var compactPillsFillConstraint: NSLayoutConstraint?
    private var compactPillsLeftConstraint: NSLayoutConstraint?
    private let compactRefreshBtn = NSButton(title: "", target: nil, action: nil)
    private let expandBtn = NSButton(title: "", target: nil, action: nil)

    private let expandedHeaderRow = NSStackView()
    private let expandedTitleLabel = NSTextField(labelWithString: "")
    private let expandedUpdatedLabel = NSTextField(labelWithString: "")
    private let expandedRefreshBtn = NSButton(title: "", target: nil, action: nil)
    private let collapseBtn = NSButton(title: "", target: nil, action: nil)
    private let expandedGridStack = NSStackView()

    private let detailBar = NSView()
    private let detailDot = NSView()
    private let detailLabel = NSTextField(labelWithString: "")

    private var focusedTarget: BarFocusedTarget?
    private var compactPills: [CompactRingPill] = []
    private var gridCards: [BentoGridCard] = []

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

        compactRow.translatesAutoresizingMaskIntoConstraints = false
        compactPillsStack.translatesAutoresizingMaskIntoConstraints = false
        compactActionsStack.translatesAutoresizingMaskIntoConstraints = false

        compactPillsStack.orientation = .vertical
        compactPillsStack.spacing = 4
        compactPillsStack.alignment = .leading
        compactPillsStack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        configureRefreshButton(compactRefreshBtn)
        configureRefreshButton(expandedRefreshBtn)

        expandBtn.bezelStyle = .rounded
        expandBtn.controlSize = .small
        expandBtn.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        expandBtn.target = self
        expandBtn.action = #selector(toggleExpand(_:))
        expandBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        expandBtn.setContentHuggingPriority(.required, for: .horizontal)
        expandBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        compactActionsStack.orientation = .vertical
        compactActionsStack.alignment = .centerX
        compactActionsStack.spacing = 5
        compactActionsStack.setContentHuggingPriority(.required, for: .horizontal)
        compactActionsStack.addArrangedSubview(expandBtn)
        compactActionsStack.addArrangedSubview(compactRefreshBtn)
        compactActionsStack.widthAnchor.constraint(equalTo: expandBtn.widthAnchor).isActive = true
        compactRefreshBtn.widthAnchor.constraint(equalTo: expandBtn.widthAnchor).isActive = true

        compactRow.addSubview(compactPillsStack)
        compactRow.addSubview(compactActionsStack)

        let pillsTop = compactPillsStack.topAnchor.constraint(equalTo: compactRow.topAnchor)
        pillsTop.priority = NSLayoutConstraint.Priority(750)
        let pillsBottom = compactPillsStack.bottomAnchor.constraint(equalTo: compactRow.bottomAnchor)
        pillsBottom.priority = NSLayoutConstraint.Priority(750)

        let fillConstraint = compactPillsStack.trailingAnchor.constraint(equalTo: compactActionsStack.leadingAnchor, constant: -8)
        let leftConstraint = compactPillsStack.trailingAnchor.constraint(lessThanOrEqualTo: compactActionsStack.leadingAnchor, constant: -8)
        compactPillsFillConstraint = fillConstraint
        compactPillsLeftConstraint = leftConstraint

        NSLayoutConstraint.activate([
            compactPillsStack.leadingAnchor.constraint(equalTo: compactRow.leadingAnchor),
            compactPillsStack.centerYAnchor.constraint(equalTo: compactRow.centerYAnchor),
            compactPillsStack.topAnchor.constraint(greaterThanOrEqualTo: compactRow.topAnchor),
            compactPillsStack.bottomAnchor.constraint(lessThanOrEqualTo: compactRow.bottomAnchor),
            pillsTop,
            pillsBottom,

            compactActionsStack.trailingAnchor.constraint(equalTo: compactRow.trailingAnchor),
            compactActionsStack.centerYAnchor.constraint(equalTo: compactRow.centerYAnchor),
            compactActionsStack.topAnchor.constraint(greaterThanOrEqualTo: compactRow.topAnchor),
            compactActionsStack.bottomAnchor.constraint(lessThanOrEqualTo: compactRow.bottomAnchor),

            leftConstraint
        ])

        expandedTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        expandedTitleLabel.textColor = Theme.agendaEventDateTextColor

        expandedUpdatedLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        expandedUpdatedLabel.textColor = Theme.noncurrentMonthTextColor

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
        expandedHeaderRow.spacing = 6
        expandedHeaderRow.addArrangedSubview(expandedTitleLabel)
        expandedHeaderRow.addArrangedSubview(expandedUpdatedLabel)
        expandedHeaderRow.addArrangedSubview(expSpacer)
        expandedHeaderRow.addArrangedSubview(expandedRefreshBtn)
        expandedHeaderRow.addArrangedSubview(collapseBtn)

        expandedGridStack.orientation = .vertical
        expandedGridStack.alignment = .leading
        expandedGridStack.spacing = 6

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
        detailLabel.usesSingleLineMode = false
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.cell?.truncatesLastVisibleLine = true
        detailLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)

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

    private func configureRefreshButton(_ btn: NSButton) {
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.target = self
        btn.action = #selector(refreshQuotaClicked(_:))
        if let sym = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            btn.image = sym.withSymbolConfiguration(cfg)
            btn.imagePosition = .imageOnly
            btn.title = ""
        } else {
            btn.title = "↻"
        }
    }

    @objc private func toggleExpand(_ sender: Any?) {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: kDualTZSubscriptionBarExpanded), forKey: kDualTZSubscriptionBarExpanded)
    }

    @objc private func refreshQuotaClicked(_ sender: Any?) {
        expandedUpdatedLabel.stringValue = LocalizationService.pick("刷新中...", "Syncing...")
        AIQuotaEngine.shared.refreshAll(interactive: true)
    }

    func refresh() {
        let d = UserDefaults.standard
        let showAI = d.bool(forKey: kDualTZShowAIQuotaPool)
        let aiAccounts = showAI ? AIQuotaStore.loadAccounts().filter { $0.enabled } : []
        let aiSnaps = AIQuotaStore.loadSnapshots()
        let subSnaps = SubscriptionStore.activeSnapshots()
        let expanded = d.bool(forKey: kDualTZSubscriptionBarExpanded)

        expandBtn.title = LocalizationService.pick("展开 ▾", "More ▾")
        collapseBtn.title = LocalizationService.pick("收起 ▴", "Less ▴")

        if !aiAccounts.isEmpty && !subSnaps.isEmpty {
            expandedTitleLabel.stringValue = LocalizationService.pick("AI 额度与订阅", "AI Quotas & Subs")
        } else if !aiAccounts.isEmpty {
            expandedTitleLabel.stringValue = LocalizationService.pick("AI 额度追踪", "AI Quotas")
        } else {
            expandedTitleLabel.stringValue = LocalizationService.pick("订阅扣费追踪", "Subscriptions")
        }

        let showRefresh = !aiAccounts.isEmpty
        compactRefreshBtn.isHidden = !showRefresh
        expandedRefreshBtn.isHidden = !showRefresh
        let claudePasswordless = ClaudeStatusLineSync.currentStatus().isEnabled
        expandedRefreshBtn.toolTip = claudePasswordless
            ? LocalizationService.pick(
                "刷新全部额度（Claude 免密自动同步；如需立即查询请点设置页单条 ↻）",
                "Refresh quotas (Claude stays password-free; use row ↻ in Settings to force fetch)"
            )
            : LocalizationService.pick("立即刷新 AI 额度", "Refresh AI quotas")
        compactRefreshBtn.toolTip = expandedRefreshBtn.toolTip

        updateSyncedTimestampLabel(aiAccounts: aiAccounts, aiSnaps: aiSnaps)

        if aiAccounts.isEmpty && subSnaps.isEmpty {
            compactRow.isHidden = false
            expandedHeaderRow.isHidden = true
            expandedGridStack.isHidden = true
            detailBar.isHidden = true
            rebuildCompactPills(aiAccounts: [], aiSnaps: [:], subSnaps: [])
            expandBtn.isHidden = true
            return
        }

        expandBtn.isHidden = false
        validateFocusedTarget(aiAccounts: aiAccounts, subSnaps: subSnaps)

        compactRow.isHidden = expanded
        expandedHeaderRow.isHidden = !expanded
        expandedGridStack.isHidden = !expanded
        detailBar.isHidden = !expanded

        if expanded {
            rebuildExpandedGrid(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
            updateDetailBar(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
        } else {
            rebuildCompactPills(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
        }
    }

    private func updateSyncedTimestampLabel(aiAccounts: [AIQuotaAccount], aiSnaps: [String: AIQuotaSnapshot]) {
        guard !aiAccounts.isEmpty else {
            expandedUpdatedLabel.stringValue = ""
            return
        }
        if AIQuotaEngine.shared.isBusy {
            expandedUpdatedLabel.stringValue = LocalizationService.pick("刷新中...", "Syncing...")
            return
        }
        if let latestDate = aiAccounts.compactMap({ aiSnaps[$0.id]?.updatedAt }).max() {
            let cal = TimeZoneService.gregorianCalendar(in: WorldClockStore.primaryTimeZone)
            let c = cal.dateComponents([.hour, .minute], from: latestDate)
            let hm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            expandedUpdatedLabel.stringValue = LocalizationService.pick("\(hm) 同步", "Synced \(hm)")
        } else {
            expandedUpdatedLabel.stringValue = ""
        }
    }

    private func validateFocusedTarget(aiAccounts: [AIQuotaAccount], subSnaps: [SubscriptionScheduleSnapshot]) {
        if let current = focusedTarget {
            switch current {
            case .ai(let id):
                if aiAccounts.contains(where: { $0.id == id }) { return }
            case .subscription(let id):
                if subSnaps.contains(where: { $0.item.id == id }) { return }
            }
        }
        if let firstAI = aiAccounts.first {
            focusedTarget = .ai(firstAI.id)
        } else if let firstSub = subSnaps.first {
            focusedTarget = .subscription(firstSub.item.id)
        } else {
            focusedTarget = nil
        }
    }

    private func rebuildCompactPills(
        aiAccounts: [AIQuotaAccount],
        aiSnaps: [String: AIQuotaSnapshot],
        subSnaps: [SubscriptionScheduleSnapshot]
    ) {
        compactPills.removeAll()
        compactPillsStack.arrangedSubviews.forEach {
            compactPillsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if aiAccounts.isEmpty && subSnaps.isEmpty {
            compactPillsFillConstraint?.isActive = false
            compactPillsLeftConstraint?.isActive = true
            let emptyLabel = NSTextField(labelWithString: LocalizationService.pick("尚未添加账号或订阅（可在设置页管理）", "No active quotas or subscriptions"))
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = Theme.noncurrentMonthTextColor
            compactPillsStack.addArrangedSubview(emptyLabel)
            return
        }

        let maxPerRow = 5
        // 收起态专注显示全部已启用 AI 账号用量；仅当未启用任何 AI 账号时兜底展示订阅
        let itemCount = !aiAccounts.isEmpty ? aiAccounts.count : subSnaps.count
        let fillFullRow = (itemCount >= maxPerRow)
        let fixedWidth: CGFloat? = fillFullRow ? nil : 50

        if fillFullRow {
            compactPillsLeftConstraint?.isActive = false
            compactPillsFillConstraint?.isActive = true
        } else {
            compactPillsFillConstraint?.isActive = false
            compactPillsLeftConstraint?.isActive = true
        }

        var allPills: [CompactRingPill] = []
        if !aiAccounts.isEmpty {
            for acc in aiAccounts {
                let pill = CompactRingPill(fixedWidth: fixedWidth)
                pill.apply(account: acc, snapshot: aiSnaps[acc.id])
                pill.onClick = { [weak self] in
                    self?.focusedTarget = .ai(acc.id)
                    UserDefaults.standard.set(true, forKey: kDualTZSubscriptionBarExpanded)
                }
                allPills.append(pill)
            }
        } else {
            for snap in subSnaps {
                let pill = CompactRingPill(fixedWidth: fixedWidth)
                pill.apply(snapshot: snap)
                pill.onClick = { [weak self] in
                    self?.focusedTarget = .subscription(snap.item.id)
                    UserDefaults.standard.set(true, forKey: kDualTZSubscriptionBarExpanded)
                }
                allPills.append(pill)
            }
        }

        compactPills = allPills
        for startIdx in stride(from: 0, to: allPills.count, by: maxPerRow) {
            let endIdx = min(startIdx + maxPerRow, allPills.count)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            for pill in allPills[startIdx..<endIdx] {
                row.addArrangedSubview(pill)
            }
            if fillFullRow {
                row.distribution = .fillEqually
                let missing = maxPerRow - (endIdx - startIdx)
                for _ in 0..<missing {
                    let placeholder = NSView()
                    placeholder.translatesAutoresizingMaskIntoConstraints = false
                    row.addArrangedSubview(placeholder)
                }
                compactPillsStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: compactPillsStack.widthAnchor).isActive = true
                if let first = row.arrangedSubviews.first {
                    for sub in row.arrangedSubviews.dropFirst() {
                        sub.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
                    }
                }
            } else {
                compactPillsStack.addArrangedSubview(row)
            }
        }
    }

    private func rebuildExpandedGrid(
        aiAccounts: [AIQuotaAccount],
        aiSnaps: [String: AIQuotaSnapshot],
        subSnaps: [SubscriptionScheduleSnapshot]
    ) {
        gridCards.removeAll()
        expandedGridStack.arrangedSubviews.forEach {
            expandedGridStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if !aiAccounts.isEmpty {
            appendTwoColumnRows(count: aiAccounts.count, makeCard: { idx in
                let acc = aiAccounts[idx]
                let card = BentoGridCard(ringDiameter: 30)
                let selected = (focusedTarget == .ai(acc.id))
                card.apply(account: acc, snapshot: aiSnaps[acc.id], isSelected: selected)
                card.onSelect = { [weak self] tgt in
                    self?.focusedTarget = tgt
                    self?.refreshFocusOnly(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
                }
                return card
            })
        }

        if !subSnaps.isEmpty {
            if !aiAccounts.isEmpty {
                let secLbl = NSTextField(labelWithString: LocalizationService.pick("订阅扣费追踪", "Subscriptions"))
                secLbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                secLbl.textColor = Theme.noncurrentMonthTextColor
                expandedGridStack.addArrangedSubview(secLbl)
            }
            appendTwoColumnRows(count: subSnaps.count, makeCard: { idx in
                let snap = subSnaps[idx]
                let card = BentoGridCard(ringDiameter: 28)
                let selected = (focusedTarget == .subscription(snap.item.id))
                card.apply(subscription: snap, isSelected: selected)
                card.onSelect = { [weak self] tgt in
                    self?.focusedTarget = tgt
                    self?.refreshFocusOnly(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
                }
                return card
            })
        }
    }

    private func appendTwoColumnRows(count: Int, makeCard: (Int) -> BentoGridCard) {
        var idx = 0
        while idx < count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6

            let c1 = makeCard(idx)
            gridCards.append(c1)
            row.addArrangedSubview(c1)

            let rightView: NSView
            if idx + 1 < count {
                let c2 = makeCard(idx + 1)
                gridCards.append(c2)
                rightView = c2
            } else {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                rightView = spacer
            }
            row.addArrangedSubview(rightView)
            c1.widthAnchor.constraint(equalTo: rightView.widthAnchor).isActive = true

            expandedGridStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: expandedGridStack.widthAnchor).isActive = true
            idx += 2
        }
    }

    private func refreshFocusOnly(
        aiAccounts: [AIQuotaAccount],
        aiSnaps: [String: AIQuotaSnapshot],
        subSnaps: [SubscriptionScheduleSnapshot]
    ) {
        for card in gridCards {
            card.isFocusedCard = (card.target == focusedTarget)
        }
        updateDetailBar(aiAccounts: aiAccounts, aiSnaps: aiSnaps, subSnaps: subSnaps)
    }

    private func updateDetailBar(
        aiAccounts: [AIQuotaAccount],
        aiSnaps: [String: AIQuotaSnapshot],
        subSnaps: [SubscriptionScheduleSnapshot]
    ) {
        guard let focusedTarget else {
            detailBar.isHidden = true
            return
        }
        switch focusedTarget {
        case .ai(let id):
            guard let acc = aiAccounts.first(where: { $0.id == id }) else {
                detailBar.isHidden = true
                return
            }
            let snap = aiSnaps[id]
            detailDot.layer?.backgroundColor = (snap?.displayRingColor(provider: acc.provider) ?? acc.provider.accentColor).cgColor
            var parts: [String] = [acc.customName]
            if let dName = snap?.accountDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !dName.isEmpty,
               dName.caseInsensitiveCompare(acc.customName.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                parts.append(dName)
            }
            let duplicatePeers = AIQuotaStore.duplicateClaudePeerNames(accounts: aiAccounts, snapshots: aiSnaps)[acc.id] ?? []
            if !duplicatePeers.isEmpty {
                parts.append(LocalizationService.pick("⚠️ 与「\(duplicatePeers[0])」同号", "⚠️ Same as \(duplicatePeers[0])"))
            }

            if let snap {
                if let pct = snap.displayRemainingPercent(for: acc.provider) {
                    if let dual = snap.dualWindowSummaryText() {
                        parts.append(LocalizationService.pick("剩余 \(dual)", "Left \(dual)"))
                    } else {
                        parts.append(LocalizationService.pick("剩余 \(snap.primaryWindowLabel) \(Int(round(pct)))%", "Left \(snap.primaryWindowLabel) \(Int(round(pct)))%"))
                    }
                }
                if let reset = snap.formattedResetText(for: acc.provider, includeTimeZoneName: true) {
                    parts.append(reset)
                }
                if let email = snap.accountEmail, !email.isEmpty {
                    parts.append(AIQuotaStore.compactDisplayEmail(email))
                } else if acc.provider != .antigravity, !acc.sourceSubtitle.isEmpty {
                    parts.append(acc.sourceSubtitle)
                }
                if acc.provider == .antigravity, let plan = snap.planLabel, !plan.isEmpty {
                    parts.append(plan)
                }
                switch snap.state {
                case .live:
                    parts.append(LocalizationService.pick("实时", "Live"))
                case .cached:
                    parts.append(snap.statusMessage ?? LocalizationService.pick("离线缓存", "Cached"))
                case .needsKeychainPermission:
                    parts.append(LocalizationService.pick("待授权刷新", "Needs auth"))
                case .needsLogin:
                    parts.append(LocalizationService.pick("需登录", "Sign-in needed"))
                case .rateLimited:
                    parts.append(snap.statusMessage ?? LocalizationService.pick("限流冷却中", "Rate limited"))
                case .unavailable:
                    parts.append(snap.statusMessage ?? LocalizationService.pick("等待同步", "Pending"))
                }
            } else {
                if !acc.sourceSubtitle.isEmpty { parts.append(acc.sourceSubtitle) }
                parts.append(LocalizationService.pick("尚未刷新 · 点击右上角同步", "Tap refresh to sync"))
            }
            detailLabel.stringValue = parts.joined(separator: " · ")
            detailLabel.toolTip = snap?.accountEmail?.isEmpty == false
                ? "\(acc.customName) · \(snap!.accountEmail!) · \(parts.dropFirst().joined(separator: " · "))"
                : detailLabel.stringValue

        case .subscription(let id):
            guard let focused = subSnaps.first(where: { $0.item.id == id }) else {
                detailBar.isHidden = true
                return
            }
            detailDot.layer?.backgroundColor = (focused.isUrgent ? NSColor.systemOrange : NSColor.systemBlue).cgColor
            detailLabel.stringValue = "\(focused.item.customName) · \(focused.item.accountEmail) · \(focused.item.paymentMethod) · \(focused.dueDetailText)"
        }
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
