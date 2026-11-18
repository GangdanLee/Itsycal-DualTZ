//
//  DSTWarningBannerView.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class DSTWarningBannerView: NSView {
    private let bgBox = NSView()
    private let iconLabel = NSTextField(labelWithString: "⏱")
    private let textLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private var currentTransitionKey: String?

    var onDismiss: (() -> Void)?
    private(set) var shouldShow: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        refresh()
    }

    static func warningInfo(at date: Date = Date()) -> (key: String, message: String)? {
        let d = UserDefaults.standard
        guard d.bool(forKey: kDualTZShowDSTWarning) else { return nil }

        let laTZ = TimeZoneService.losAngelesTZ
        guard let transition = laTZ.nextDaylightSavingTimeTransition(after: date),
              transition.timeIntervalSince(date) > 0 else {
            return nil
        }
        let calLA = TimeZoneService.gregorianCalendar(in: laTZ)
        let todayStart = calLA.startOfDay(for: date)
        let transStart = calLA.startOfDay(for: transition)
        let daysUntil = calLA.dateComponents([.day], from: todayStart, to: transStart).day ?? 99
        guard (0...7).contains(daysUntil) else { return nil }

        let tc = calLA.dateComponents([.year, .month, .day], from: transition)
        let key = String(format: "%04d-%02d-%02d", tc.year ?? 0, tc.month ?? 1, tc.day ?? 1)
        if d.string(forKey: kDualTZDismissedDSTDate) == key {
            return nil
        }

        let after = transition.addingTimeInterval(3600)
        let gapHours = (TimeZoneService.beijingTZ.secondsFromGMT(for: after) - laTZ.secondsFromGMT(for: after)) / 3600
        let isDST = laTZ.isDaylightSavingTime(for: after)
        let m = tc.month ?? 1, day = tc.day ?? 1
        let msg: String
        if LocalizationService.isChinese {
            let season = isDST ? "夏令时" : "冬令时"
            msg = "美西 \(m)/\(day) 起进入\(season)，北京时差变为 \(gapHours)h"
        } else {
            let kind = isDST ? "DST (PDT)" : "Standard Time (PST)"
            msg = "US Pacific shifts to \(kind) on \(m)/\(day) (Beijing +\(gapHours)h)"
        }
        return (key, msg)
    }

    func refresh() {
        refresh(at: Date())
    }

    func refresh(at date: Date) {
        if let info = Self.warningInfo(at: date) {
            currentTransitionKey = info.key
            textLabel.stringValue = info.message
            shouldShow = true
        } else {
            currentTransitionKey = nil
            shouldShow = false
        }
    }

    private func setupUI() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        bgBox.wantsLayer = true
        bgBox.layer?.cornerRadius = 6
        bgBox.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
        bgBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bgBox)

        iconLabel.font = NSFont.systemFont(ofSize: 10.5)
        iconLabel.textColor = .systemOrange
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        textLabel.textColor = Theme.currentMonthTextColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)

        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissTapped(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        [iconLabel, textLabel, closeButton].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
            bgBox.addSubview($0)
        }
        activateBannerConstraints()
    }

    private func activateBannerConstraints() {
        let hTight = bgBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        hTight.priority = NSLayoutConstraint.Priority(980)
        NSLayoutConstraint.activate([
            bgBox.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            bgBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bgBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bgBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            hTight,

            iconLabel.leadingAnchor.constraint(equalTo: bgBox.leadingAnchor, constant: 7),
            iconLabel.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),

            textLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 4),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),
            textLabel.topAnchor.constraint(equalTo: bgBox.topAnchor, constant: 4),
            textLabel.bottomAnchor.constraint(equalTo: bgBox.bottomAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: bgBox.trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    @objc private func dismissTapped(_ sender: Any) {
        if let key = currentTransitionKey {
            UserDefaults.standard.set(key, forKey: kDualTZDismissedDSTDate)
        }
        refresh()
        onDismiss?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        bgBox.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
        textLabel.textColor = Theme.currentMonthTextColor
    }
}
