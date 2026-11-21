//
//  DualTZSettingsComponents.swift
//  Itsycal DualTZ
//

import Cocoa

final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

struct SettingsSidebarItem {
    let id: String
    let title: String
    let symbolName: String
    let topColor: NSColor
    let bottomColor: NSColor
}

final class SettingsSidebarButton: NSControl {
    private let badgeView = NSView()
    private let badgeGradient = CAGradientLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    var onClick: (() -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    private var isHovered: Bool = false {
        didSet { updateAppearance() }
    }

    init(item: SettingsSidebarItem) {
        super.init(frame: .zero)
        setup(item: item)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setup(item: SettingsSidebarItem) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 5.5
        badgeView.layer?.cornerCurve = .continuous
        badgeView.layer?.masksToBounds = true

        badgeGradient.colors = [item.topColor.cgColor, item.bottomColor.cgColor]
        badgeGradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        badgeGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        badgeView.layer?.addSublayer(badgeGradient)

        let sym = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold))
        iconView.image = sym
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(iconView)

        titleLabel.stringValue = item.title
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 20),
            badgeView.heightAnchor.constraint(equalToConstant: 20),

            iconView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badgeGradient.frame = badgeView.bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick?()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            titleLabel.textColor = .white
            titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            badgeView.layer?.borderWidth = 1
            badgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        } else {
            let hoverBg = isDark
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.055).cgColor
            layer?.backgroundColor = isHovered ? hoverBg : NSColor.clear.cgColor
            titleLabel.textColor = isHovered ? NSColor.labelColor : NSColor.secondaryLabelColor
            titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
            badgeView.layer?.borderWidth = 0
        }
    }
}

final class SettingsPageHeaderView: NSView {
    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleField.textColor = NSColor.labelColor

        let subField = NSTextField(wrappingLabelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        subField.textColor = NSColor.secondaryLabelColor

        let stack = NSStackView(views: [titleField, subField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class SettingsCardView: NSView {
    private let rowsStack = NSStackView()
    private var rowViews: [NSView] = []
    private var dividers: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
        layer?.masksToBounds = true

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func addRow(_ view: NSView) {
        if !rowViews.isEmpty {
            let line = makeInsetHairline()
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(line)
            NSLayoutConstraint.activate([
                wrap.heightAnchor.constraint(equalToConstant: 1),
                line.topAnchor.constraint(equalTo: wrap.topAnchor),
                line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
                line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
            ])
            dividers.append(line)
            rowsStack.addArrangedSubview(wrap)
            wrap.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
        rowViews.append(view)
        rowsStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
    }

    func clearRows() {
        rowViews.removeAll()
        dividers.removeAll()
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    func clearRowsKeepingFirstRow() {
        guard rowViews.count > 1 else { return }
        rowViews = [rowViews[0]]
        dividers.removeAll()
        let arranged = rowsStack.arrangedSubviews
        for idx in 1..<arranged.count {
            let v = arranged[idx]
            rowsStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    private func makeInsetHairline() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = separatorCGColor()
        return v
    }

    private func separatorCGColor() -> CGColor {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (isDark
            ? NSColor.white.withAlphaComponent(0.11)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
    }

    private func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.065)
            : NSColor.white.withAlphaComponent(0.68)).cgColor
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.085)).cgColor
        let sep = separatorCGColor()
        dividers.forEach { $0.layer?.backgroundColor = sep }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}

final class SettingsSectionView: NSView {
    let card = SettingsCardView()

    init(
        title: String? = nil,
        footer: String? = nil,
        actionTitle: String? = nil,
        actionTarget: AnyObject? = nil,
        actionSelector: Selector? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let title = title, !title.isEmpty {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            label.textColor = NSColor.labelColor.withAlphaComponent(0.78)
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(label)

            if let actionTitle = actionTitle, let sel = actionSelector {
                let btn = NSButton(title: actionTitle, target: actionTarget, action: sel)
                btn.bezelStyle = .rounded
                btn.controlSize = .small
                btn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                btn.translatesAutoresizingMaskIntoConstraints = false
                wrap.addSubview(btn)
                NSLayoutConstraint.activate([
                    label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                    label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: btn.leadingAnchor, constant: -8),
                    btn.topAnchor.constraint(equalTo: wrap.topAnchor),
                    btn.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                    btn.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
                ])
            } else {
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: wrap.topAnchor),
                    label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                    label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -14)
                ])
            }
            stack.addArrangedSubview(wrap)
            wrap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if let footer = footer, !footer.isEmpty {
            let footLabel = NSTextField(wrappingLabelWithString: footer)
            footLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            footLabel.textColor = NSColor.tertiaryLabelColor
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            footLabel.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(footLabel)
            NSLayoutConstraint.activate([
                footLabel.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 2),
                footLabel.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                footLabel.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
                footLabel.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
            ])
            stack.addArrangedSubview(wrap)
            wrap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class SettingsRowView: NSView {
    init(title: String, subtitle: String? = nil, leadingDotColor: NSColor? = nil, accessory: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(740), for: .horizontal)
        textStack.addArrangedSubview(titleField)

        if let subtitle = subtitle, !subtitle.isEmpty {
            let subField = NSTextField(wrappingLabelWithString: subtitle)
            subField.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            subField.textColor = NSColor.secondaryLabelColor
            subField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(730), for: .horizontal)
            textStack.addArrangedSubview(subField)
        }

        var leftViews: [NSView] = []
        if let dotColor = leadingDotColor {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4.5
            dot.layer?.backgroundColor = dotColor.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 9),
                dot.heightAnchor.constraint(equalToConstant: 9)
            ])
            leftViews.append(dot)
        }
        leftViews.append(textStack)

        let leftWrap = NSStackView(views: leftViews)
        leftWrap.orientation = .horizontal
        leftWrap.alignment = .centerY
        leftWrap.spacing = 8
        leftWrap.translatesAutoresizingMaskIntoConstraints = false

        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessory.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(leftWrap)
        addSubview(accessory)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            leftWrap.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 9),
            leftWrap.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            leftWrap.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftWrap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftWrap.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -14),

            accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            accessory.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class SettingsStatusBadge: NSView {
    enum Tone {
        case ok, warn, info
    }

    private let label = NSTextField(labelWithString: "")
    private var tone: Tone = .info

    init(text: String, tone: Tone) {
        super.init(frame: .zero)
        self.tone = tone
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        label.stringValue = text
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3.5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3.5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9)
        ])
        apply(text: text, tone: tone)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func apply(text: String, tone: Tone) {
        self.tone = tone
        label.stringValue = text
        switch tone {
        case .ok:
            label.textColor = NSColor.systemGreen
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.16).cgColor
        case .warn:
            label.textColor = NSColor.systemOrange
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
        case .info:
            label.textColor = NSColor.controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        }
    }
}

final class SettingsTokenPill: NSButton {
    var tokenKey: String = ""
    var isTokenActive: Bool = false {
        didSet { updateStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
        font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        updateStyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 18, height: 24)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    private func updateStyle() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isTokenActive {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
            )
        } else {
            layer?.backgroundColor = (isDark
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.05)).cgColor
            layer?.borderColor = (isDark
                ? NSColor.white.withAlphaComponent(0.14)
                : NSColor.black.withAlphaComponent(0.10)).cgColor
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
    }
}
