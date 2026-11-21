//
//  BeijingHeroHeaderView.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class BeijingHeroHeaderView: NSView {
    private let rootStack = NSStackView()
    private let heroRow = NSStackView()
    private let heroLeftStack = NSStackView()
    private let heroTitleRow = NSStackView()

    private let primaryCityLabel = NSTextField(labelWithString: "")
    private let dayNightLabel = NSTextField(labelWithString: "☀️")
    private let collapseBtn = NSButton(title: "▾", target: nil, action: nil)
    private let primarySubLabel = NSTextField(labelWithString: "")
    private let primaryTimeLabel = NSTextField(labelWithString: "00:00")

    private let secondaryGridStack = NSStackView()
    private let thirdRefLabel = NSTextField(labelWithString: "")
    private let divider = NSView()

    private var secondaryCards: [SecondaryCityCardView] = []
    private var lastSignature = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSizeChanged(_:)),
            name: .sizeDidChange,
            object: nil
        )
        refresh()
    }

    @objc private func handleSizeChanged(_ notification: Notification) {
        refresh()
    }

    @objc private func toggleCollapsed(_ sender: Any?) {
        let d = UserDefaults.standard
        let current = d.bool(forKey: kDualTZWorldClockCollapsed)
        d.set(!current, forKey: kDualTZWorldClockCollapsed)
    }

    func refresh() {
        let defaults = UserDefaults.standard
        let now = Date()
        let sizePref = Sizer.shared().sizePreference
        applyTypography(sizePref: sizePref)

        let snap = TimeZoneService.heroSnapshot(at: now, compactDates: sizePref == .small)
        let flag = WorldClockStore.primaryFlag
        primaryCityLabel.stringValue = "\(flag) \(snap.beijingTitle)"
        dayNightLabel.stringValue = snap.beijingDayNightIcon
        primaryTimeLabel.stringValue = snap.beijingTime

        let showLunar = defaults.bool(forKey: kDualTZShowLunarSolarTerms)
        if showLunar && !snap.beijingLunarText.isEmpty {
            primarySubLabel.stringValue = "\(snap.beijingDateWeekday) · \(snap.beijingLunarText)"
        } else {
            primarySubLabel.stringValue = snap.beijingDateWeekday
        }

        let collapsed = defaults.bool(forKey: kDualTZWorldClockCollapsed)
        collapseBtn.title = collapsed ? "▸" : "▾"
        collapseBtn.contentTintColor = collapsed ? NSColor.controlAccentColor : NSColor.secondaryLabelColor

        let secondary = collapsed ? [] : WorldClockStore.activeSecondarySnapshots(at: now)
        secondaryGridStack.isHidden = secondary.isEmpty

        let sig = "\(collapsed)|\(secondary.map { $0.id }.joined(separator: ","))"
        if sig != lastSignature {
            rebuildSecondaryGrid(snapshots: secondary)
            lastSignature = sig
        } else {
            for (idx, snapItem) in secondary.enumerated() where idx < secondaryCards.count {
                secondaryCards[idx].apply(snapshot: snapItem)
            }
        }

        let showThird = defaults.bool(forKey: kDualTZShowThirdRefTZ) && !collapsed
        thirdRefLabel.stringValue = snap.thirdRefText
        thirdRefLabel.isHidden = !showThird
    }

    private func applyTypography(sizePref: SizePreference) {
        let timeSize: CGFloat
        let titleSize: CGFloat
        let subSize: CGFloat
        switch sizePref {
        case .small:
            timeSize = 22
            titleSize = 14
            subSize = 10.5
        case .medium:
            timeSize = 24
            titleSize = 15
            subSize = 11
        case .large:
            timeSize = 26
            titleSize = 16
            subSize = 11.5
        @unknown default:
            timeSize = 24
            titleSize = 15
            subSize = 11
        }
        primaryCityLabel.font = NSFont.systemFont(ofSize: titleSize, weight: .bold)
        dayNightLabel.font = NSFont.systemFont(ofSize: titleSize - 1)
        primarySubLabel.font = NSFont.systemFont(ofSize: subSize, weight: .medium)
        primaryTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: timeSize, weight: .bold)
    }

    private func setupUI() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        primaryCityLabel.textColor = Theme.currentMonthTextColor
        primaryCityLabel.lineBreakMode = .byTruncatingTail
        primarySubLabel.textColor = Theme.agendaEventDateTextColor
        primarySubLabel.lineBreakMode = .byTruncatingTail
        primaryTimeLabel.textColor = Theme.currentMonthTextColor
        primaryTimeLabel.alignment = .right

        primaryTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        primaryTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        primaryCityLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(850), for: .horizontal)
        primarySubLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(740), for: .horizontal)

        collapseBtn.isBordered = false
        collapseBtn.bezelStyle = .inline
        collapseBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        collapseBtn.target = self
        collapseBtn.action = #selector(toggleCollapsed(_:))
        collapseBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collapseBtn.widthAnchor.constraint(equalToConstant: 18),
            collapseBtn.heightAnchor.constraint(equalToConstant: 18)
        ])

        heroTitleRow.orientation = .horizontal
        heroTitleRow.alignment = .centerY
        heroTitleRow.spacing = 4
        heroTitleRow.addArrangedSubview(primaryCityLabel)
        heroTitleRow.addArrangedSubview(dayNightLabel)
        heroTitleRow.addArrangedSubview(collapseBtn)

        heroLeftStack.orientation = .vertical
        heroLeftStack.alignment = .leading
        heroLeftStack.spacing = 2
        heroLeftStack.addArrangedSubview(heroTitleRow)
        heroLeftStack.addArrangedSubview(primarySubLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        heroRow.orientation = .horizontal
        heroRow.alignment = .centerY
        heroRow.spacing = 8
        heroRow.addArrangedSubview(heroLeftStack)
        heroRow.addArrangedSubview(spacer)
        heroRow.addArrangedSubview(primaryTimeLabel)

        secondaryGridStack.orientation = .vertical
        secondaryGridStack.alignment = .leading
        secondaryGridStack.spacing = 6

        thirdRefLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        thirdRefLabel.textColor = Theme.noncurrentMonthTextColor
        thirdRefLabel.alignment = .left
        thirdRefLabel.isHidden = true

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(heroRow)
        rootStack.addArrangedSubview(secondaryGridStack)
        rootStack.addArrangedSubview(thirdRefLabel)

        heroRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        secondaryGridStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)
        addSubview(divider)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            divider.topAnchor.constraint(equalTo: rootStack.bottomAnchor, constant: 8),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    private func rebuildSecondaryGrid(snapshots: [SecondaryCitySnapshot]) {
        secondaryCards.removeAll()
        secondaryGridStack.arrangedSubviews.forEach { view in
            secondaryGridStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !snapshots.isEmpty else { return }

        var idx = 0
        while idx < snapshots.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6

            let firstCard = SecondaryCityCardView()
            firstCard.apply(snapshot: snapshots[idx])
            secondaryCards.append(firstCard)
            row.addArrangedSubview(firstCard)

            if idx + 1 < snapshots.count {
                let secondCard = SecondaryCityCardView()
                secondCard.apply(snapshot: snapshots[idx + 1])
                secondaryCards.append(secondCard)
                row.addArrangedSubview(secondCard)
            } else {
                let placeholder = NSView()
                row.addArrangedSubview(placeholder)
            }

            secondaryGridStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: secondaryGridStack.widthAnchor).isActive = true
            idx += 2
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        divider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        secondaryCards.forEach { $0.refreshAppearance() }
    }
}

private final class SecondaryCityCardView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let metaLeftLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let offsetLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        refreshAppearance()

        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = Theme.currentMonthTextColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(740), for: .horizontal)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        timeLabel.textColor = Theme.currentMonthTextColor
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        metaLeftLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        metaLeftLabel.textColor = Theme.agendaEventDateTextColor
        metaLeftLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 2.75
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 5.5),
            statusDot.heightAnchor.constraint(equalToConstant: 5.5)
        ])

        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = Theme.agendaEventDateTextColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(720), for: .horizontal)

        offsetLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        offsetLabel.textColor = Theme.noncurrentMonthTextColor
        offsetLabel.alignment = .right
        offsetLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        offsetLabel.setContentHuggingPriority(.required, for: .horizontal)

        let topRow = NSStackView(views: [nameLabel, timeLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 4

        let statusWrap = NSStackView(views: [metaLeftLabel, statusDot, statusLabel])
        statusWrap.orientation = .horizontal
        statusWrap.alignment = .centerY
        statusWrap.spacing = 3

        let bottomRow = NSStackView(views: [statusWrap, offsetLabel])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 4

        let outer = NSStackView(views: [topRow, bottomRow])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 3
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        topRow.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        bottomRow.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func apply(snapshot: SecondaryCitySnapshot) {
        nameLabel.stringValue = "\(snapshot.flag) \(snapshot.displayName)"
        timeLabel.stringValue = snapshot.formattedTime
        metaLeftLabel.stringValue = "\(snapshot.tzAbbreviation) · \(snapshot.dayLabel) ·"
        offsetLabel.stringValue = snapshot.offsetText

        let statusText = LocalizationService.pick(snapshot.status.labelZH, snapshot.status.labelEN)
        switch snapshot.status {
        case .work:
            statusDot.isHidden = false
            statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            statusLabel.stringValue = statusText
        case .prime:
            statusDot.isHidden = false
            statusDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
            statusLabel.stringValue = statusText
        case .morning:
            statusDot.isHidden = false
            statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusLabel.stringValue = statusText
        case .night:
            statusDot.isHidden = true
            statusLabel.stringValue = "🌙 \(statusText)"
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
