//
//  BeijingHeroHeaderView.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class BeijingHeroHeaderView: NSView {
    private let bjTitleLabel = NSTextField(labelWithString: "北京时间")
    private let bjIconLabel = NSTextField(labelWithString: "☀️")
    private let bjTimeLabel = NSTextField(labelWithString: "00:00")
    private let bjDateLabel = NSTextField(labelWithString: "")
    private let lunarLabel = NSTextField(labelWithString: "")

    private let localTitleLabel = NSTextField(labelWithString: "美西 PST")
    private let localTimeLabel = NSTextField(labelWithString: "00:00")
    private let localDateLabel = NSTextField(labelWithString: "")
    private let thirdRefLabel = NSTextField(labelWithString: "")
    private let divider = NSView()

    private var bjMainRow: NSStackView?
    private var leftCol: NSStackView?
    private var rightCol: NSStackView?

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

    func refresh() {
        let defaults = UserDefaults.standard
        let useCompact = shouldUseCompactTypography()
        applyResponsiveTypography(compact: useCompact)

        let snap = TimeZoneService.heroSnapshot(at: Date(), compactDates: useCompact)
        bjTitleLabel.stringValue = snap.beijingTitle
        bjIconLabel.stringValue = snap.beijingDayNightIcon
        bjTimeLabel.stringValue = snap.beijingTime
        bjDateLabel.stringValue = snap.beijingDateWeekday
        lunarLabel.stringValue = snap.beijingLunarText
        lunarLabel.isHidden = !defaults.bool(forKey: kDualTZShowLunarSolarTerms)

        localTitleLabel.stringValue = snap.localTitle
        localTimeLabel.stringValue = snap.localTime
        localDateLabel.stringValue = snap.localDateWeekday
        thirdRefLabel.stringValue = snap.thirdRefText
        thirdRefLabel.isHidden = !defaults.bool(forKey: kDualTZShowThirdRefTZ)
    }

    @objc private func handleSizeChanged(_ notification: Notification) {
        refresh()
    }

    private func shouldUseCompactTypography() -> Bool {
        let d = UserDefaults.standard
        let hasSubtitles = d.bool(forKey: kDualTZShowLunarSolarTerms)
            || d.bool(forKey: kDualTZShowChinaHolidays)
            || d.bool(forKey: kDualTZShowUSHolidays)
        let sizePref = Sizer.shared().sizePreference
        return sizePref == .small || (sizePref == .medium && !hasSubtitles)
    }

    private func applyResponsiveTypography(compact: Bool) {
        let sizePref = Sizer.shared().sizePreference
        let bjSize: CGFloat
        let localSize: CGFloat
        let dateSize: CGFloat
        switch sizePref {
        case .small:
            bjSize = compact ? 18 : 19
            localSize = 12.5
            dateSize = 10
        case .medium:
            bjSize = compact ? 20 : 22
            localSize = compact ? 13 : 14
            dateSize = compact ? 10.5 : 11.5
        case .large:
            bjSize = 24
            localSize = 15
            dateSize = 12
        @unknown default:
            bjSize = 21
            localSize = 14
            dateSize = 11
        }
        bjTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: bjSize, weight: .semibold)
        bjDateLabel.font = NSFont.systemFont(ofSize: dateSize, weight: .medium)
        localTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: localSize, weight: .semibold)
        localDateLabel.font = NSFont.systemFont(ofSize: max(10, dateSize - 0.5), weight: .regular)
        bjMainRow?.spacing = compact ? 4 : 6
    }

    private func setupUI() {
        configureLabels()
        let left = buildLeftColumn()
        let right = buildRightColumn()
        leftCol = left
        rightCol = right

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(left)
        addSubview(right)
        addSubview(divider)
        activateRigidConstraints(left: left, right: right)
    }

    private func configureLabels() {
        bjTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        bjTitleLabel.textColor = Theme.todayCellColor
        bjIconLabel.font = NSFont.systemFont(ofSize: 11)
        bjTimeLabel.textColor = Theme.currentMonthTextColor
        bjDateLabel.textColor = Theme.currentMonthTextColor
        bjDateLabel.lineBreakMode = .byTruncatingTail
        lunarLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        lunarLabel.textColor = Theme.agendaEventDateTextColor
        lunarLabel.lineBreakMode = .byTruncatingTail

        localTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        localTitleLabel.textColor = Theme.agendaEventDateTextColor
        localTitleLabel.alignment = .right
        localTimeLabel.textColor = Theme.currentMonthTextColor
        localTimeLabel.alignment = .right
        localDateLabel.textColor = Theme.agendaEventDateTextColor
        localDateLabel.alignment = .right
        localDateLabel.lineBreakMode = .byTruncatingTail
        thirdRefLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        thirdRefLabel.textColor = Theme.noncurrentMonthTextColor
        thirdRefLabel.alignment = .right
        thirdRefLabel.lineBreakMode = .byTruncatingTail

        // 时间数字禁止被窄窗裁断；日期/农历允许略微收敛以免反推撑宽日历网格
        [bjTimeLabel, localTimeLabel].forEach {
            $0.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(999), for: .horizontal)
            $0.setContentHuggingPriority(NSLayoutConstraint.Priority(999), for: .horizontal)
        }
        [bjTitleLabel, bjIconLabel, localTitleLabel].forEach {
            $0.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(900), for: .horizontal)
        }
        [bjDateLabel, lunarLabel, localDateLabel, thirdRefLabel].forEach {
            $0.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(740), for: .horizontal)
        }
        [bjTitleLabel, bjIconLabel, bjTimeLabel, bjDateLabel, lunarLabel,
         localTitleLabel, localTimeLabel, localDateLabel, thirdRefLabel].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    private func buildLeftColumn() -> NSStackView {
        let topRow = NSStackView.dualTZLocked([bjTitleLabel, bjIconLabel], orientation: .horizontal, alignment: .centerY, spacing: 4)
        let mainRow = NSStackView.dualTZLocked([bjTimeLabel, bjDateLabel], orientation: .horizontal, alignment: .firstBaseline, spacing: 5)
        NSLayoutConstraint.activate([
            bjTimeLabel.topAnchor.constraint(equalTo: mainRow.topAnchor),
            bjTimeLabel.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor)
        ])
        bjMainRow = mainRow
        return NSStackView.dualTZLocked([topRow, mainRow, lunarLabel], orientation: .vertical, alignment: .leading, spacing: 2)
    }

    private func buildRightColumn() -> NSStackView {
        return NSStackView.dualTZLocked(
            [localTitleLabel, localTimeLabel, localDateLabel, thirdRefLabel],
            orientation: .vertical,
            alignment: .trailing,
            spacing: 1.5
        )
    }

    private func activateRigidConstraints(left: NSStackView, right: NSStackView) {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        // 垂直紧贴优先级必须高于 NSLayoutPriorityWindowSizeStayPut (500)，防止下拉手柄缩回时顶部留白
        let snapLeft = divider.topAnchor.constraint(equalTo: left.bottomAnchor, constant: 7)
        snapLeft.priority = NSLayoutConstraint.Priority(950)
        let snapRight = divider.topAnchor.constraint(equalTo: right.bottomAnchor, constant: 7)
        snapRight.priority = NSLayoutConstraint.Priority(940)

        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            right.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -6),

            divider.topAnchor.constraint(greaterThanOrEqualTo: left.bottomAnchor, constant: 7),
            divider.topAnchor.constraint(greaterThanOrEqualTo: right.bottomAnchor, constant: 7),
            snapLeft,
            snapRight,
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        divider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
    }
}
