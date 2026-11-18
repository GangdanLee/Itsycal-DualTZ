//
//  TimeScrubberView.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class TimeScrubberView: NSView {
    private let topDivider = NSView()
    private let bjTitleLabel = NSTextField(labelWithString: "北京时间")
    private let bjValueLabel = NSTextField(labelWithString: "")
    private let laTitleLabel = NSTextField(labelWithString: "美西 PST")
    private let laValueLabel = NSTextField(labelWithString: "")
    private let overlapLabel = NSTextField(labelWithString: "")
    private let thirdRefLabel = NSTextField(labelWithString: "")
    private let trackView = ScrubberTrackView()
    private let slider = NSSlider(value: 40, minValue: 0, maxValue: 95, target: nil, action: nil)
    private let copyBtn = NSButton(title: "复制", target: nil, action: nil)
    private var nowBtn: NSButton?

    private var anchorDate: Date = Date()
    private var lastRenderedDate: Date = Date()
    private var slotDates: [Date] = []
    private var overlapToThirdConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        setAnchorDate(Date(), preferredSlot: currentBeijingQuarterSlot(for: Date()))
    }

    func setAnchorMoDate(_ moDate: MoDate) {
        let bjCal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        let comp = DateComponents(year: moDate.year, month: moDate.month + 1, day: moDate.day, hour: 0, minute: 0)
        let targetStart = bjCal.date(from: comp) ?? Date()
        let isSameBJToday = bjCal.isDate(targetStart, inSameDayAs: Date())
        let slot = isSameBJToday ? currentBeijingQuarterSlot(for: Date()) : Int(slider.integerValue)
        setAnchorDate(targetStart, preferredSlot: slot)
    }

    func setQuarterSlot(_ slot: Int) {
        let clamped = max(0, min(max(0, slotDates.count - 1), slot))
        slider.integerValue = clamped
        updateDisplayForSelectedSlot()
    }

    func refreshAppearanceAndRef() {
        bjTitleLabel.stringValue = LocalizationService.pick("北京时间", "Beijing")
        nowBtn?.title = LocalizationService.pick("此刻", "Now")
        copyBtn.title = LocalizationService.pick("复制", "Copy")
        updateDisplayForSelectedSlot()
    }

    private func setAnchorDate(_ base: Date, preferredSlot: Int) {
        let bjCal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        anchorDate = bjCal.startOfDay(for: base)
        var dates: [Date] = []
        var colors: [NSColor] = []
        for idx in 0..<96 {
            let dt = bjCal.date(byAdding: .minute, value: idx * 15, to: anchorDate) ?? anchorDate
            dates.append(dt)
            colors.append(DualTZOverlapHelper.tier(for: dt).color)
        }
        slotDates = dates
        trackView.slotColors = colors
        setQuarterSlot(preferredSlot)
    }

    private func currentBeijingQuarterSlot(for date: Date) -> Int {
        let cal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        let comp = cal.dateComponents([.hour, .minute], from: date)
        let mins = (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
        return max(0, min(95, Int(round(Double(mins) / 15.0))))
    }

    private func updateDisplayForSelectedSlot() {
        let idx = max(0, min(slotDates.count - 1, slider.integerValue))
        guard slotDates.indices.contains(idx) else { return }
        let dt = slotDates[idx]
        lastRenderedDate = dt

        let localTZ = TimeZone.autoupdatingCurrent
        let bjComp = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ).dateComponents([.month, .day], from: dt)
        let laComp = TimeZoneService.gregorianCalendar(in: localTZ).dateComponents([.month, .day], from: dt)
        let bjWD = TimeZoneService.weekdayText(for: dt, in: TimeZoneService.beijingTZ)
        let laWD = TimeZoneService.weekdayText(for: dt, in: localTZ)

        bjTitleLabel.stringValue = LocalizationService.pick("北京时间", "Beijing")
        bjValueLabel.stringValue = "\(bjComp.month ?? 1)/\(bjComp.day ?? 1) \(bjWD) \(TimeZoneService.formatDate(dt, pattern: "HH:mm", in: TimeZoneService.beijingTZ))"
        laTitleLabel.stringValue = TimeZoneService.localTimeZoneLabel(at: dt, localTZ: localTZ)
        laValueLabel.stringValue = "\(laComp.month ?? 1)/\(laComp.day ?? 1) \(laWD) \(TimeZoneService.formatDate(dt, pattern: "HH:mm", in: localTZ))"

        let gapHours = (TimeZoneService.beijingTZ.secondsFromGMT(for: dt) - localTZ.secondsFromGMT(for: dt)) / 3600
        let tier = DualTZOverlapHelper.tier(for: dt, localTZ: localTZ)
        let gapPrefix = LocalizationService.pick("差", "Gap")
        overlapLabel.stringValue = "\(tier.prefixLabel) · \(gapPrefix) \(gapHours)h"

        let showThird = UserDefaults.standard.bool(forKey: kDualTZShowThirdRefTZ)
        thirdRefLabel.isHidden = !showThird
        overlapToThirdConstraint?.isActive = showThird
        if showThird {
            let ny = TimeZoneService.formatDate(dt, pattern: "HH:mm", in: TimeZoneService.newYorkTZ)
            let utc = TimeZoneService.formatDate(dt, pattern: "HH:mm", in: TimeZoneService.utcTZ)
            thirdRefLabel.stringValue = "NY \(ny) · UTC \(utc)"
        } else {
            thirdRefLabel.stringValue = ""
        }
    }

    private func setupUI() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        configureReadoutLabels()

        let bjCol = NSStackView.dualTZLocked([bjTitleLabel, bjValueLabel], orientation: .vertical, alignment: .leading, spacing: 1)
        let laCol = NSStackView.dualTZLocked([laTitleLabel, laValueLabel], orientation: .vertical, alignment: .trailing, spacing: 1)
        overlapLabel.translatesAutoresizingMaskIntoConstraints = false
        thirdRefLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.translatesAutoresizingMaskIntoConstraints = false
        trackView.translatesAutoresizingMaskIntoConstraints = false

        let presetsRow = buildPresetsRow()
        [topDivider, bjCol, laCol, overlapLabel, thirdRefLabel, trackView, slider, presetsRow].forEach { addSubview($0) }

        activateConstraints(bjCol: bjCol, laCol: laCol, presetsRow: presetsRow)
    }

    private func configureReadoutLabels() {
        bjTitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        bjTitleLabel.textColor = Theme.todayCellColor
        bjValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        bjValueLabel.textColor = Theme.currentMonthTextColor

        laTitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        laTitleLabel.textColor = Theme.agendaEventDateTextColor
        laTitleLabel.alignment = .right
        laValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        laValueLabel.textColor = Theme.currentMonthTextColor
        laValueLabel.alignment = .right

        overlapLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        overlapLabel.textColor = Theme.agendaEventDateTextColor
        thirdRefLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        thirdRefLabel.textColor = Theme.noncurrentMonthTextColor
        thirdRefLabel.alignment = .right

        [bjTitleLabel, bjValueLabel, laTitleLabel, laValueLabel, overlapLabel, thirdRefLabel].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(740), for: .horizontal)
        }
    }

    private func buildPresetsRow() -> NSStackView {
        let defs: [(String, Selector, Int)] = [
            (LocalizationService.pick("此刻", "Now"), #selector(nowTapped(_:)), 0),
            ("10:00", #selector(slotPresetTapped(_:)), 10 * 4),
            ("14:00", #selector(slotPresetTapped(_:)), 14 * 4),
            ("21:00", #selector(slotPresetTapped(_:)), 21 * 4)
        ]
        var views: [NSView] = defs.enumerated().map { idx, item in
            let b = NSButton(title: item.0, target: self, action: item.1)
            b.bezelStyle = .rounded
            b.controlSize = .mini
            b.tag = item.2
            b.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(700), for: .horizontal)
            if idx == 0 { self.nowBtn = b }
            return b
        }
        copyBtn.title = LocalizationService.pick("复制", "Copy")
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .mini
        copyBtn.target = self
        copyBtn.action = #selector(copyTapped(_:))
        copyBtn.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(900), for: .horizontal)
        views.append(copyBtn)
        return NSStackView.dualTZLocked(views, orientation: .horizontal, alignment: .centerY, spacing: 4)
    }

    private func activateConstraints(bjCol: NSStackView, laCol: NSStackView, presetsRow: NSStackView) {
        let snapStatus = overlapLabel.topAnchor.constraint(equalTo: bjCol.bottomAnchor, constant: 4)
        snapStatus.priority = NSLayoutConstraint.Priority(960)
        let thirdGap = overlapLabel.trailingAnchor.constraint(lessThanOrEqualTo: thirdRefLabel.leadingAnchor, constant: -4)
        overlapToThirdConstraint = thirdGap
        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            bjCol.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 6),
            bjCol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            laCol.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 6),
            laCol.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            bjCol.trailingAnchor.constraint(lessThanOrEqualTo: laCol.leadingAnchor, constant: -6),

            overlapLabel.topAnchor.constraint(greaterThanOrEqualTo: bjCol.bottomAnchor, constant: 4),
            overlapLabel.topAnchor.constraint(greaterThanOrEqualTo: laCol.bottomAnchor, constant: 4),
            snapStatus,
            overlapLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            overlapLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -9),
            thirdRefLabel.firstBaselineAnchor.constraint(equalTo: overlapLabel.firstBaselineAnchor),
            thirdRefLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            thirdGap,

            slider.topAnchor.constraint(equalTo: overlapLabel.bottomAnchor, constant: 5),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            trackView.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            trackView.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 12),

            presetsRow.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 5),
            presetsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            presetsRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            presetsRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateDisplayForSelectedSlot()
    }

    @objc private func nowTapped(_ sender: NSButton) {
        let now = Date()
        setAnchorDate(now, preferredSlot: currentBeijingQuarterSlot(for: now))
    }

    @objc private func slotPresetTapped(_ sender: NSButton) {
        setQuarterSlot(sender.tag)
    }

    @objc private func copyTapped(_ sender: NSButton) {
        let text = formattedPasteboardSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyBtn.title = LocalizationService.pick("已复制 ✓", "Copied ✓")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copyBtn.title = LocalizationService.pick("复制", "Copy")
        }
    }

    func formattedPasteboardSummary() -> String {
        let bj = bjValueLabel.stringValue
        let laTitle = laTitleLabel.stringValue
        let la = laValueLabel.stringValue
        let bjLabel = LocalizationService.pick("北京时间", "Beijing")
        var summary = "\(bjLabel) \(bj) / \(laTitle) \(la)"
        if UserDefaults.standard.bool(forKey: kDualTZShowThirdRefTZ), !thirdRefLabel.stringValue.isEmpty {
            summary += " (\(thirdRefLabel.stringValue))"
        }
        return summary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        topDivider.layer?.backgroundColor = Theme.agendaDividerColor.cgColor
    }
}
