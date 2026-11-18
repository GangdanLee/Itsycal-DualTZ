//
//  DualTZPrefsVC.swift
//  Itsycal DualTZ
//

import Cocoa
import UniformTypeIdentifiers

final class DualTZPrefsVC: NSViewController, NSTextFieldDelegate {
    private struct FeatureToggle {
        let key: String
        let zh: String
        let en: String
    }

    private let toggles: [FeatureToggle] = [
        FeatureToggle(key: kDualTZShowHeroHeader, zh: "顶部显示醒目北京时间栏", en: "Show Beijing Time hero header"),
        FeatureToggle(key: kDualTZShowDualToday, zh: "月历同时标记北京今日与美西今日", en: "Highlight both Beijing Today & Local Today"),
        FeatureToggle(key: kDualTZShowLunarSolarTerms, zh: "显示农历日期与二十四节气", en: "Show Lunar dates & 24 Solar Terms"),
        FeatureToggle(key: kDualTZShowChinaHolidays, zh: "显示中国法定假日与周末休/班角标", en: "Show China statutory holidays & Off/Work badges"),
        FeatureToggle(key: kDualTZShowUSHolidays, zh: "显示美国联邦假日与黑五/网一节点", en: "Show US federal holidays & Black Friday / Cyber Monday"),
        FeatureToggle(key: kDualTZShowMarketingNodes, zh: "显示欧美与跨境营销节点（情人/母/父/618/万圣/双11）", en: "Show retail & cross-border nodes (618, 11.11, Halloween...)"),
        FeatureToggle(key: kDualTZShowAgendaHolidays, zh: "底部列表展示内置节假日与选中日详情", en: "Show built-in holidays & selected-day summary in Agenda"),
        FeatureToggle(key: kDualTZShowAgendaDualTZ, zh: "日程列表与详情附注美西参考时间", en: "Show US Pacific reference time in Agenda & details"),
        FeatureToggle(key: kDualTZAllowBJEventCreate, zh: "新建日程默认北京时间录入与深夜预警", en: "Default New Event to Beijing Time with late-night warning"),
        FeatureToggle(key: kDualTZShowDSTWarning, zh: "美西夏/冬令时切换提前 7 天提醒", en: "Warn 7 days before US DST transitions"),
        FeatureToggle(key: kDualTZShowUpcomingCountdown, zh: "会前 15 分钟在菜单栏显示轻量倒计时", en: "Show 15-min pre-meeting countdown in menu bar"),
        FeatureToggle(key: kDualTZEnableTimeScrubber, zh: "主面板显示排会时间轴换算按钮（可选）", en: "Show meeting time scrubber button in panel"),
        FeatureToggle(key: kDualTZShowThirdRefTZ, zh: "附带美东 (NY) 与 UTC 时区参考（可选）", en: "Show NY & UTC reference times")
    ]

    private let menuEnabledCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let formatField = NSTextField(string: "")
    private let sameDayPreview = NSTextField(labelWithString: "")
    private let crossDayPreview = NSTextField(labelWithString: "")
    private let iconSegment = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let holidayStatusLabel = NSTextField(labelWithString: "")
    private let syncOnlineBtn = NSButton(title: "", target: nil, action: nil)
    private let importJSONBtn = NSButton(title: "", target: nil, action: nil)
    private var toggleButtons: [String: NSButton] = [:]

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        configureMenubarSection(into: stack)
        addDivider(into: stack)
        configureFeatureToggles(into: stack)
        addDivider(into: stack)
        configureHolidaySyncSection(into: stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncFromDefaults()
    }

    private func addDivider(into stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func configureMenubarSection(into stack: NSStackView) {
        menuEnabledCheckbox.title = LocalizationService.pick("启用自定义多时区菜单栏模板", "Enable custom Dual-TZ menu bar template")
        menuEnabledCheckbox.target = self
        menuEnabledCheckbox.action = #selector(menuEnabledChanged(_:))
        stack.addArrangedSubview(menuEnabledCheckbox)

        formatField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        formatField.placeholderString = "{BJ:EEE HH:mm}"
        formatField.delegate = self
        stack.addArrangedSubview(formatField)
        formatField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(buildPresetsRow())

        let helper = NSTextField(labelWithString: LocalizationService.pick(
            "占位符：{BJ:...} 北京 · {NY:...} 美东 · {UTC:...} · {diff} 跨天+1d · {bj_dn} ☀️/🌙",
            "Tokens: {BJ:...} Beijing · {NY:...} Eastern · {UTC:...} · {diff} +1d · {bj_dn} ☀️/🌙"
        ))
        helper.font = NSFont.systemFont(ofSize: 10.5)
        helper.textColor = .secondaryLabelColor
        stack.addArrangedSubview(helper)

        [sameDayPreview, crossDayPreview].forEach {
            $0.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            $0.textColor = .secondaryLabelColor
            stack.addArrangedSubview($0)
        }

        [LocalizationService.pick("北京日期", "Beijing Day"),
         LocalizationService.pick("美西日期", "Local Day"),
         LocalizationService.pick("隐藏", "Hide")].enumerated().forEach { idx, title in
            iconSegment.setLabel(title, forSegment: idx)
        }
        iconSegment.target = self
        iconSegment.action = #selector(iconModeChanged(_:))
        iconSegment.controlSize = .small
        let iconLabel = NSTextField(labelWithString: LocalizationService.pick("菜单栏图标日期：", "Menu Bar Icon Date:"))
        let iconRow = NSStackView(views: [iconLabel, iconSegment])
        iconRow.orientation = .horizontal
        iconRow.spacing = 8
        stack.addArrangedSubview(iconRow)
    }

    private func buildPresetsRow() -> NSStackView {
        let presets: [(String, String)] = [
            (LocalizationService.pick("极简北京", "Beijing Minimal"), "{BJ:EEE HH:mm}"),
            (LocalizationService.pick("日夜图标", "Day/Night"), "{bj_dn} {BJ:HH:mm}"),
            (LocalizationService.pick("带月日", "Month/Day"), "{BJ:M/d HH:mm}"),
            (LocalizationService.pick("双时区", "Dual TZ"), "HH:mm · {BJ:EEE HH:mm}")
        ]
        let presetRow = NSStackView()
        presetRow.orientation = .horizontal
        presetRow.spacing = 6
        for (idx, item) in presets.enumerated() {
            let btn = NSButton(title: item.0, target: self, action: #selector(presetTapped(_:)))
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.tag = idx
            btn.toolTip = item.1
            presetRow.addArrangedSubview(btn)
        }
        return presetRow
    }

    private func configureFeatureToggles(into stack: NSStackView) {
        let header = NSTextField(labelWithString: LocalizationService.pick("功能模块开关（可随时隐藏不常用功能）", "Feature Switches"))
        header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(header)

        let toggleStack = NSStackView()
        toggleStack.orientation = .vertical
        toggleStack.alignment = .leading
        toggleStack.spacing = 4
        for item in toggles {
            let btn = NSButton(checkboxWithTitle: LocalizationService.pick(item.zh, item.en), target: self, action: #selector(featureToggleChanged(_:)))
            btn.identifier = NSUserInterfaceItemIdentifier(item.key)
            toggleButtons[item.key] = btn
            toggleStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(toggleStack)
    }

    private func configureHolidaySyncSection(into stack: NSStackView) {
        let header = NSTextField(labelWithString: LocalizationService.pick("中国法定假日与周末调休数据", "China Holidays & Makeup Workdays"))
        header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(header)

        holidayStatusLabel.font = NSFont.systemFont(ofSize: 11)
        holidayStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(holidayStatusLabel)

        syncOnlineBtn.title = LocalizationService.pick("在线同步最新调休", "Sync Online")
        syncOnlineBtn.bezelStyle = .rounded
        syncOnlineBtn.controlSize = .small
        syncOnlineBtn.target = self
        syncOnlineBtn.action = #selector(syncOnlineTapped(_:))

        importJSONBtn.title = LocalizationService.pick("导入本地 JSON…", "Import JSON…")
        importJSONBtn.bezelStyle = .rounded
        importJSONBtn.controlSize = .small
        importJSONBtn.target = self
        importJSONBtn.action = #selector(importJSONTapped(_:))

        let btnRow = NSStackView(views: [syncOnlineBtn, importJSONBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        stack.addArrangedSubview(btnRow)
    }

    private func syncFromDefaults() {
        let d = UserDefaults.standard
        menuEnabledCheckbox.state = d.bool(forKey: kDualTZMenuBarEnabled) ? .on : .off
        formatField.stringValue = d.string(forKey: kDualTZMenuBarFormat) ?? "{BJ:EEE HH:mm}"
        iconSegment.selectedSegment = d.bool(forKey: kHideIcon) ? 2 : (d.bool(forKey: kDualTZIconFollowsBeijing) ? 0 : 1)
        for item in toggles { toggleButtons[item.key]?.state = d.bool(forKey: item.key) ? .on : .off }
        holidayStatusLabel.textColor = .secondaryLabelColor
        holidayStatusLabel.stringValue = ChinaHolidayStore.shared.statusSummary()
        refreshPreviews()
    }

    private func refreshPreviews() {
        let pattern = formatField.stringValue
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZoneService.losAngelesTZ
        let sameDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 6, minute: 30)) ?? Date()
        let crossDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 18, minute: 6)) ?? Date()
        let sameText = DualClockFormatter.string(from: sameDate, template: pattern, localTZ: TimeZoneService.losAngelesTZ)
        let crossText = DualClockFormatter.string(from: crossDate, template: pattern, localTZ: TimeZoneService.losAngelesTZ)
        sameDayPreview.stringValue = LocalizationService.pick("同日预览 (LA 06:30)：\(sameText)", "Same-day (LA 06:30): \(sameText)")
        crossDayPreview.stringValue = LocalizationService.pick("跨天预览 (LA 18:06)：\(crossText)", "Cross-day (LA 18:06): \(crossText)")
    }

    func controlTextDidChange(_ obj: Notification) {
        UserDefaults.standard.set(formatField.stringValue, forKey: kDualTZMenuBarFormat)
        refreshPreviews()
    }

    @objc private func menuEnabledChanged(_ sender: NSButton) { UserDefaults.standard.set(sender.state == .on, forKey: kDualTZMenuBarEnabled) }

    @objc private func presetTapped(_ sender: NSButton) {
        guard let pat = sender.toolTip else { return }
        formatField.stringValue = pat
        UserDefaults.standard.set(pat, forKey: kDualTZMenuBarFormat)
        refreshPreviews()
    }

    @objc private func iconModeChanged(_ sender: NSSegmentedControl) {
        let d = UserDefaults.standard
        if sender.selectedSegment == 2 { d.set(true, forKey: kHideIcon); return }
        d.set(false, forKey: kHideIcon)
        d.set(sender.selectedSegment == 0, forKey: kDualTZIconFollowsBeijing)
    }

    @objc private func featureToggleChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
    }

    @objc private func syncOnlineTapped(_ sender: NSButton) {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        syncOnlineBtn.isEnabled = false
        holidayStatusLabel.textColor = .secondaryLabelColor
        holidayStatusLabel.stringValue = LocalizationService.pick("正在同步 \(year) 年国务院调休 JSON…", "Syncing \(year) China holidays JSON…")

        ChinaHolidayStore.shared.syncOnline(year: year) { [weak self] result in
            guard let self = self else { return }
            self.syncOnlineBtn.isEnabled = true
            switch result {
            case .success(let count):
                self.holidayStatusLabel.textColor = .systemGreen
                self.holidayStatusLabel.stringValue = LocalizationService.pick(
                    "同步成功：更新 \(year) 年共 \(count) 条（\(ChinaHolidayStore.shared.statusSummary())）",
                    "Synced \(count) entries for \(year)"
                )
            case .failure(let error):
                self.holidayStatusLabel.textColor = .systemRed
                self.holidayStatusLabel.stringValue = LocalizationService.pick("同步失败：\(error.localizedDescription)", "Sync failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func importJSONTapped(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = LocalizationService.pick("选择符合 holiday-cn 格式的中国节假日调休 JSON 文件", "Select a holiday-cn JSON file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try ChinaHolidayStore.shared.importLocalFile(url: url)
            holidayStatusLabel.textColor = .systemGreen
            holidayStatusLabel.stringValue = LocalizationService.pick("导入成功：加载 \(count) 条（\(ChinaHolidayStore.shared.statusSummary())）", "Imported \(count) entries")
        } catch {
            holidayStatusLabel.textColor = .systemRed
            holidayStatusLabel.stringValue = LocalizationService.pick("导入失败：\(error.localizedDescription)", "Import failed: \(error.localizedDescription)")
        }
    }
}
