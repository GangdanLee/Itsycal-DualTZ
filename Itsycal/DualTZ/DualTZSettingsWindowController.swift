//
//  DualTZSettingsWindowController.swift
//  Itsycal DualTZ
//

import Cocoa
import UniformTypeIdentifiers

@objcMembers
final class DualTZSettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private enum TabID: Int, CaseIterable {
        case general = 0
        case clock = 1
        case calendar = 2
        case events = 3
        case quota = 4
        case about = 5
    }

    private weak var eventCenter: EventCenter?
    private var sidebarButtons: [SettingsSidebarButton] = []
    private let scrollView = NSScrollView()
    private let documentRoot = SettingsFlippedView()
    private let contentStack = NSStackView()

    // 当前页内需局部实时刷新而不丢焦点的轻量引用
    private weak var menuMockBarText: NSTextField?
    private weak var menuDayBadgeLabel: NSTextField?
    private weak var menuWidthBadge: SettingsStatusBadge?
    private weak var advPatternContainer: NSView?
    private weak var offsetRefSegmented: NSSegmentedControl?
    private weak var citySearchField: NSTextField?
    private weak var cityRowsCard: SettingsCardView?

    private var citySearchQuery: String = ""
    private var menuAdvancedExpanded: Bool = false
    private var editingSubID: String?
    private var editingAIID: String?
    private var discoveredClaudeServices: [String] = []
    private var aiObserverToken: NSObjectProtocol?
    private var previewTimer: Timer?

    // 订阅内联编辑控件引用
    private weak var edSubNameField: NSTextField?
    private weak var edSubAcctField: NSTextField?
    private weak var edSubRegionPopup: NSPopUpButton?
    private weak var edSubPayField: NSTextField?
    private weak var edSubPriceField: NSTextField?
    private weak var edSubDayField: NSTextField?

    // AI 额度账号内联编辑控件引用
    private weak var edAINameField: NSTextField?
    private weak var edAIProviderPopup: NSPopUpButton?
    private weak var edAIConfigPathField: NSTextField?
    private weak var edAIKeychainPopup: NSPopUpButton?

    @objc var selectedTabIndex: Int = 0

    init(eventCenter: EventCenter?) {
        self.eventCenter = eventCenter
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 688, height: 650),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.contentMinSize = NSSize(width: 688, height: 560)
        panel.contentMaxSize = NSSize(width: 688, height: 920)
        super.init(window: panel)
        panel.delegate = self

        menuAdvancedExpanded = UserDefaults.standard.bool(forKey: kDualTZMenuUseAdvanced)
        setupSplitLayout(in: panel)
        panel.setContentSize(NSSize(width: 688, height: 650))
        panel.center()
        selectTab(at: 0)

        aiObserverToken = NotificationCenter.default.addObserver(
            forName: .dualTZAIQuotaDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.selectedTabIndex == TabID.quota.rawValue,
               self.editingAIID == nil,
               self.editingSubID == nil {
                self.renderSelectedTab()
            }
        }
    }

    deinit {
        stopPreviewTimer()
        if let aiObserverToken {
            NotificationCenter.default.removeObserver(aiObserverToken)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func showPrefs() {
        if selectedTabIndex == TabID.about.rawValue {
            selectTab(at: TabID.general.rawValue)
        } else if selectedTabIndex == TabID.general.rawValue {
            refreshMenubarPreviewWidgets()
        }
        startPreviewTimer()
    }

    @objc func showAbout() {
        selectTab(at: TabID.about.rawValue)
    }

    @objc(selectTabAtIndex:)
    func selectTab(at index: Int) {
        let validIdx = max(0, min(TabID.allCases.count - 1, index))
        selectedTabIndex = validIdx
        for (idx, btn) in sidebarButtons.enumerated() {
            btn.isSelected = (idx == validIdx)
        }
        renderSelectedTab()
    }

    private func setupSplitLayout(in window: NSWindow) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 688, height: 650))
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        // 左侧 Apple 侧边栏毛玻璃
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarBorder = NSView()
        sidebarBorder.wantsLayer = true
        sidebarBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sidebarBorder.translatesAutoresizingMaskIntoConstraints = false

        let brandTitle = NSTextField(labelWithString: "Itsycal DualTZ")
        brandTitle.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        brandTitle.textColor = NSColor.labelColor

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.2"
        let brandSub = NSTextField(labelWithString: LocalizationService.pick("v\(appVersion) 偏好设置", "v\(appVersion) Settings"))
        brandSub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        brandSub.textColor = NSColor.tertiaryLabelColor

        let brandStack = NSStackView(views: [brandTitle, brandSub])
        brandStack.orientation = .vertical
        brandStack.alignment = .leading
        brandStack.spacing = 2
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.alignment = .leading
        navStack.spacing = 3
        navStack.translatesAutoresizingMaskIntoConstraints = false

        let items: [SettingsSidebarItem] = [
            SettingsSidebarItem(
                id: "general",
                title: LocalizationService.pick("通用与菜单栏", "General & Bar"),
                symbolName: "gearshape.fill",
                topColor: NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.58, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.39, green: 0.39, blue: 0.40, alpha: 1)
            ),
            SettingsSidebarItem(
                id: "clock",
                title: LocalizationService.pick("世界时钟", "World Clock"),
                symbolName: "globe",
                topColor: NSColor(calibratedRed: 0.37, green: 0.36, blue: 0.90, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.21, green: 0.20, blue: 0.64, alpha: 1)
            ),
            SettingsSidebarItem(
                id: "calendar",
                title: LocalizationService.pick("日历与节假日", "Calendar"),
                symbolName: "calendar",
                topColor: NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.84, green: 0.0, blue: 0.08, alpha: 1)
            ),
            SettingsSidebarItem(
                id: "events",
                title: LocalizationService.pick("日程与提醒", "Events & Alerts"),
                symbolName: "list.bullet",
                topColor: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.02, alpha: 1)
            ),
            SettingsSidebarItem(
                id: "quota",
                title: LocalizationService.pick("额度与订阅", "Quotas & Subs"),
                symbolName: "gauge.with.dots.needle.bottom.50percent",
                topColor: NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.09, green: 0.64, blue: 0.29, alpha: 1)
            ),
            SettingsSidebarItem(
                id: "about",
                title: LocalizationService.pick("关于", "About"),
                symbolName: "sparkles",
                topColor: NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1),
                bottomColor: NSColor(calibratedRed: 0.0, green: 0.32, blue: 0.84, alpha: 1)
            )
        ]

        sidebarButtons.removeAll()
        for (idx, item) in items.enumerated() {
            let btn = SettingsSidebarButton(item: item)
            btn.onClick = { [weak self] in
                self?.selectTab(at: idx)
            }
            sidebarButtons.append(btn)
            navStack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: navStack.widthAnchor).isActive = true
        }

        sidebar.addSubview(brandStack)
        sidebar.addSubview(navStack)
        sidebar.addSubview(sidebarBorder)

        // 右侧主内容区
        let detailBg = NSVisualEffectView()
        detailBg.material = .windowBackground
        detailBg.blendingMode = .withinWindow
        detailBg.state = .active
        detailBg.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        documentRoot.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentRoot.addSubview(contentStack)
        scrollView.documentView = documentRoot

        detailBg.addSubview(scrollView)
        root.addSubview(sidebar)
        root.addSubview(detailBg)

        let defaultHeightConstraint = root.heightAnchor.constraint(equalToConstant: 650)
        defaultHeightConstraint.priority = NSLayoutConstraint.Priority(250)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 688),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 560),
            defaultHeightConstraint,

            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 168),

            sidebarBorder.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarBorder.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sidebarBorder.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarBorder.widthAnchor.constraint(equalToConstant: 1),

            // 预留左上角系统红绿灯安全高度
            brandStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 38),
            brandStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            brandStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            navStack.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 14),
            navStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            navStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),

            detailBg.topAnchor.constraint(equalTo: root.topAnchor),
            detailBg.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detailBg.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detailBg.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: detailBg.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: detailBg.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: detailBg.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: detailBg.trailingAnchor),

            documentRoot.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: documentRoot.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: documentRoot.leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: documentRoot.trailingAnchor, constant: -26),
            contentStack.bottomAnchor.constraint(equalTo: documentRoot.bottomAnchor, constant: -28)
        ])
    }

    // MARK: - Render Dispatcher

    private func renderSelectedTab() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        switch TabID(rawValue: selectedTabIndex) ?? .general {
        case .general: buildGeneralTab()
        case .clock: buildClockTab()
        case .calendar: buildCalendarTab()
        case .events: buildEventsTab()
        case .quota: buildQuotaTab()
        case .about: buildAboutTab()
        }

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func addPageBlock(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    // MARK: - Tab 1: 通用与菜单栏

    private func buildGeneralTab() {
        let d = UserDefaults.standard
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("通用与菜单栏", "General & Menu Bar"),
            subtitle: LocalizationService.pick("定制液态玻璃材质、语言与顶部菜单栏外观", "Configure Liquid Glass material, language, and menu bar items")
        ))

        let appearanceSec = SettingsSectionView(title: LocalizationService.pick("外观与语言", "Appearance & Language"))

        let glassPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        glassPopup.addItems(withTitles: [
            LocalizationService.pick("液态玻璃 · 标准", "Liquid Glass · Regular"),
            LocalizationService.pick("液态玻璃 · 通透", "Liquid Glass · Clear"),
            LocalizationService.pick("经典高对比磨砂", "Classic Frosted")
        ])
        glassPopup.selectItem(at: max(0, min(2, d.integer(forKey: kDualTZWindowGlassStyle))))
        glassPopup.target = self
        glassPopup.action = #selector(glassStyleChanged(_:))
        appearanceSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("窗口材质", "Window Material"),
            subtitle: LocalizationService.pick("在 macOS 26+ 支持液态玻璃，也可切回经典高对比磨砂", "Liquid Glass on macOS 26+, or switch to Classic Frosted"),
            accessory: glassPopup
        ))

        let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        themePopup.addItems(withTitles: [
            LocalizationService.pick("跟随系统", "System"),
            LocalizationService.pick("浅色 Light", "Light"),
            LocalizationService.pick("深色 Dark", "Dark")
        ])
        themePopup.selectItem(at: max(0, min(2, d.integer(forKey: kThemePreference))))
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        appearanceSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("外观主题", "Appearance"),
            accessory: themePopup
        ))

        let langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        langPopup.addItems(withTitles: [
            LocalizationService.tr("dualtz.lang.zh"),
            LocalizationService.tr("dualtz.lang.en"),
            LocalizationService.tr("dualtz.lang.system")
        ])
        langPopup.selectItem(at: max(0, min(2, d.integer(forKey: kDualTZAppLanguage))))
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))
        appearanceSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("界面语言", "Language"),
            accessory: langPopup
        ))

        if !d.bool(forKey: kDoNotCheckLoginItemStatus) {
            let loginSw = NSSwitch()
            loginSw.controlSize = .small
            loginSw.state = MOIsLoginItemEnabled() ? .on : .off
            loginSw.target = self
            loginSw.action = #selector(loginSwitchToggled(_:))
            appearanceSec.card.addRow(SettingsRowView(
                title: LocalizationService.pick("开机启动", "Launch at Login"),
                accessory: loginSw
            ))
        }

        let shortcutView = MASShortcutView()
        shortcutView.setAssociatedUserDefaultsKey(kKeyboardShortcut, withTransformerName: MASDictionaryTransformerName)
        shortcutView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        appearanceSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("全局快捷键", "Keyboard Shortcut"),
            subtitle: LocalizationService.pick("点击右侧按键录制或清除呼出快捷键", "Click on the right to record or clear hotkey"),
            accessory: shortcutView
        ))

        addPageBlock(appearanceSec)

        // 分组 2：菜单栏
        let menubarSec = SettingsSectionView(
            title: LocalizationService.pick("菜单栏", "Menu Bar"),
            footer: LocalizationService.pick(
                "实时评估刘海屏菜单栏占位；同时启用「美西对照」与「会前倒计时」若偏宽会提示精简积木。",
                "Evaluates MacBook notch clearance in real time and warns when tokens grow too wide."
            )
        )

        menubarSec.card.addRow(buildMenubarPreviewRow())

        let iconSeg = NSSegmentedControl(
            labels: [
                "\(WorldClockStore.primaryDisplayName)\(LocalizationService.pick("日", " Day"))",
                LocalizationService.pick("美西日", "US Day"),
                LocalizationService.pick("隐藏", "Hide")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(menuIconModeChanged(_:))
        )
        iconSeg.segmentStyle = .rounded
        iconSeg.controlSize = .small
        if d.bool(forKey: kHideIcon) {
            iconSeg.selectedSegment = 2
        } else {
            iconSeg.selectedSegment = d.bool(forKey: kDualTZIconFollowsBeijing) ? 0 : 1
        }
        menubarSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("日历图标", "Calendar Icon"),
            accessory: iconSeg
        ))

        menubarSec.card.addRow(buildTokenBuilderRow())
        menubarSec.card.addRow(buildAdvancedPatternRow())

        let countdownSw = makeBoundSwitch(key: kDualTZShowUpcomingCountdown)
        menubarSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("会前倒计时", "Meeting Countdown"),
            subtitle: LocalizationService.pick("开会前 15 分钟轻量提示", "Subtle alert 15m before joinable calls"),
            accessory: countdownSw
        ))

        addPageBlock(menubarSec)
        refreshMenubarPreviewWidgets()
    }

    private func buildMenubarPreviewRow() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let mockPill = NSView()
        mockPill.translatesAutoresizingMaskIntoConstraints = false
        mockPill.wantsLayer = true
        mockPill.layer?.cornerRadius = 7
        mockPill.layer?.cornerCurve = .continuous
        mockPill.layer?.borderWidth = 0.75
        mockPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        mockPill.layer?.borderColor = NSColor.separatorColor.cgColor

        let dayBox = NSTextField(labelWithString: "21")
        dayBox.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        dayBox.textColor = NSColor.windowBackgroundColor
        dayBox.alignment = .center
        dayBox.wantsLayer = true
        dayBox.layer?.backgroundColor = NSColor.labelColor.cgColor
        dayBox.layer?.cornerRadius = 3.5
        dayBox.translatesAutoresizingMaskIntoConstraints = false
        menuDayBadgeLabel = dayBox

        let mockText = NSTextField(labelWithString: "")
        mockText.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        mockText.textColor = NSColor.labelColor
        mockText.lineBreakMode = .byTruncatingTail
        menuMockBarText = mockText

        let pillStack = NSStackView(views: [dayBox, mockText])
        pillStack.orientation = .horizontal
        pillStack.alignment = .centerY
        pillStack.spacing = 6
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        mockPill.addSubview(pillStack)

        let badge = SettingsStatusBadge(text: "", tone: .ok)
        menuWidthBadge = badge

        wrap.addSubview(mockPill)
        wrap.addSubview(badge)

        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 46),
            dayBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            dayBox.heightAnchor.constraint(equalToConstant: 14),
            pillStack.topAnchor.constraint(equalTo: mockPill.topAnchor, constant: 4),
            pillStack.bottomAnchor.constraint(equalTo: mockPill.bottomAnchor, constant: -4),
            pillStack.leadingAnchor.constraint(equalTo: mockPill.leadingAnchor, constant: 8),
            pillStack.trailingAnchor.constraint(equalTo: mockPill.trailingAnchor, constant: -8),

            mockPill.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            mockPill.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            mockPill.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -10),

            badge.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14),
            badge.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)
        ])
        return wrap
    }

    private func buildTokenBuilderRow() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let tk = WorldClockStore.loadMenuTokens()
        let useAdv = UserDefaults.standard.bool(forKey: kDualTZMenuUseAdvanced)
        let cityName = WorldClockStore.primaryDisplayName

        let headerTitle = NSTextField(labelWithString: LocalizationService.pick("显示元素", "Display Tokens"))
        headerTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        headerTitle.textColor = NSColor.labelColor

        let headerRow = NSStackView(views: [headerTitle])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        if useAdv {
            headerRow.addArrangedSubview(SettingsStatusBadge(text: LocalizationService.pick("自定义代码接管中", "Custom Code Active"), tone: .warn))
        }

        let tokenItems: [(key: String, title: String, on: Bool)] = [
            ("showPrefix", "\(tk.showPrefix ? "✓ " : "")\(LocalizationService.pick("主城名", "City")) (\(cityName))", tk.showPrefix),
            ("showDate", "\(tk.showDate ? "✓ " : "")\(LocalizationService.pick("月日", "Date"))", tk.showDate),
            ("showWeekday", "\(tk.showWeekday ? "✓ " : "")\(LocalizationService.pick("星期", "Week"))", tk.showWeekday),
            ("showTime", "\(tk.showTime ? "✓ " : "")\(LocalizationService.pick("时间", "Time"))", tk.showTime),
            ("showUSRef", "\(tk.showUSRef ? "✓ " : "")\(LocalizationService.pick("美西对照", "US Ref"))", tk.showUSRef),
            ("showDayNight", "\(tk.showDayNight ? "✓ " : "")\(LocalizationService.pick("日夜 ☀️", "Day/Night"))", tk.showDayNight)
        ]

        let pillRow1 = NSStackView()
        pillRow1.orientation = .horizontal
        pillRow1.spacing = 6
        let pillRow2 = NSStackView()
        pillRow2.orientation = .horizontal
        pillRow2.spacing = 6

        for (idx, item) in tokenItems.enumerated() {
            let pill = SettingsTokenPill()
            pill.title = item.title
            pill.tokenKey = item.key
            pill.isTokenActive = item.on && !useAdv
            pill.target = self
            pill.action = #selector(tokenPillClicked(_:))
            if idx < 4 {
                pillRow1.addArrangedSubview(pill)
            } else {
                pillRow2.addArrangedSubview(pill)
            }
        }

        let presetRow = NSStackView()
        presetRow.orientation = .horizontal
        presetRow.spacing = 6
        let presets: [(id: String, title: String)] = [
            ("minimal", LocalizationService.pick("极简时间", "Minimal")),
            ("standard", LocalizationService.pick("标准跨境", "Standard")),
            ("dual", LocalizationService.pick("中英双区", "Dual TZ")),
            ("daynight", LocalizationService.pick("日夜图标", "Day/Night"))
        ]
        for p in presets {
            let btn = NSButton(title: p.title, target: self, action: #selector(presetButtonClicked(_:)))
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.identifier = NSUserInterfaceItemIdentifier(p.id)
            presetRow.addArrangedSubview(btn)
        }

        let vStack = NSStackView(views: [headerRow, pillRow1, pillRow2, presetRow])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 7
        vStack.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            vStack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10),
            vStack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            vStack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        return wrap
    }

    private func buildAdvancedPatternRow() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let toggleTitle = (menuAdvancedExpanded ? "▾ " : "▸ ") + LocalizationService.pick("高级：自定义格式代码", "Advanced: Custom Pattern")
        let toggleBtn = NSButton(title: toggleTitle, target: self, action: #selector(toggleAdvPatternClicked(_:)))
        toggleBtn.isBordered = false
        toggleBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        toggleBtn.contentTintColor = NSColor.secondaryLabelColor

        let stack = NSStackView(views: [toggleBtn])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        if menuAdvancedExpanded {
            let d = UserDefaults.standard
            let tpl = d.string(forKey: kDualTZMenuBarFormat) ?? "{CITY} {PRIMARY:MM月dd日} {PRIMARY:EEE} {PRIMARY:HH:mm}"
            let field = NSTextField(string: tpl)
            field.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            field.identifier = NSUserInterfaceItemIdentifier("advMenuTemplate")
            field.delegate = self

            let useAdv = d.bool(forKey: kDualTZMenuUseAdvanced)
            let toggleUseBtn = NSButton(
                title: useAdv ? LocalizationService.pick("切回积木模式", "Use Tokens") : LocalizationService.pick("启用代码模式", "Use Code"),
                target: self,
                action: #selector(toggleUseAdvCodeClicked(_:))
            )
            toggleUseBtn.bezelStyle = .rounded
            toggleUseBtn.controlSize = .small

            let hint = NSTextField(labelWithString: LocalizationService.pick("支持 {CITY} {PRIMARY:HH:mm} {LA:HH:mm} {bj_dn}", "Supports {CITY} {PRIMARY:HH:mm} {LA:HH:mm} {bj_dn}"))
            hint.font = NSFont.systemFont(ofSize: 10.5)
            hint.textColor = NSColor.tertiaryLabelColor

            let footRow = NSStackView(views: [hint, toggleUseBtn])
            footRow.orientation = .horizontal
            footRow.alignment = .centerY
            footRow.distribution = .equalSpacing

            stack.addArrangedSubview(field)
            stack.addArrangedSubview(footRow)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            footRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        advPatternContainer = wrap
        return wrap
    }

    private func refreshMenubarPreviewWidgets() {
        let d = UserDefaults.standard
        let tpl = d.string(forKey: kDualTZMenuBarFormat) ?? ""
        let preview = DualClockFormatter.string(from: Date(), template: tpl)
        menuMockBarText?.stringValue = preview.isEmpty ? "15:40" : preview

        let hideIcon = d.bool(forKey: kHideIcon)
        menuDayBadgeLabel?.isHidden = hideIcon
        let isBj = d.bool(forKey: kDualTZIconFollowsBeijing)
        let tz = isBj ? WorldClockStore.primaryTimeZone : TimeZone.autoupdatingCurrent
        let day = TimeZoneService.gregorianCalendar(in: tz).component(.day, from: Date())
        menuDayBadgeLabel?.stringValue = "\(day)"

        let hasCountdown = d.bool(forKey: kDualTZShowUpcomingCountdown)
        let effectiveLen = preview.count + (hasCountdown ? 6 : 0)
        let isCompact = effectiveLen <= 25
        menuWidthBadge?.apply(
            text: isCompact
                ? LocalizationService.pick("宽度适中 · 不撞刘海", "Compact · Notch Safe")
                : LocalizationService.pick("偏宽 · 建议精简积木", "Wide · Trim Tokens"),
            tone: isCompact ? .ok : .warn
        )
    }

    // MARK: - Tab 2: 世界时钟

    private func buildClockTab() {
        let d = UserDefaults.standard
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("世界时钟", "World Clock"),
            subtitle: LocalizationService.pick("自定义主城与美国业务城市，辅助跨境工作节奏", "Customize primary & US cities to guide cross-border workflows")
        ))

        let primarySec = SettingsSectionView(title: LocalizationService.pick("主城市", "Primary City"))

        let tzPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for opt in WorldClockStore.primaryOptions {
            tzPopup.addItem(withTitle: opt.displayTitle)
        }
        let curTZ = d.string(forKey: kDualTZPrimaryTimeZoneID) ?? "Asia/Shanghai"
        if let idx = WorldClockStore.primaryOptions.firstIndex(where: { $0.identifier == curTZ }) {
            tzPopup.selectItem(at: idx)
        }
        tzPopup.target = self
        tzPopup.action = #selector(primaryTZChanged(_:))
        primarySec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("基准时区", "Base Time Zone"),
            subtitle: LocalizationService.pick("决定日历今日与新建默认时区", "Anchors Calendar Today & New Event default"),
            accessory: tzPopup
        ))

        let aliasField = NSTextField(string: d.string(forKey: kDualTZPrimaryCityAlias) ?? "")
        aliasField.placeholderString = LocalizationService.pick("如：北京 / 深圳总部", "e.g. Beijing / HQ CN")
        aliasField.font = NSFont.systemFont(ofSize: 12)
        aliasField.identifier = NSUserInterfaceItemIdentifier("primaryAlias")
        aliasField.delegate = self
        aliasField.widthAnchor.constraint(equalToConstant: 164).isActive = true
        primarySec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("显示名称", "Display Name"),
            subtitle: LocalizationService.pick("同步主面板标题与菜单栏", "Syncs Hero title & menu bar prefix"),
            accessory: aliasField
        ))

        let pName = WorldClockStore.primaryDisplayName
        let offSeg = NSSegmentedControl(
            labels: [
                LocalizationService.pick("相对\(pName)", "vs \(pName)"),
                LocalizationService.pick("相对本地", "vs Local")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(offsetRefChanged(_:))
        )
        offSeg.controlSize = .small
        offSeg.selectedSegment = max(0, min(1, d.integer(forKey: kDualTZWorldClockOffsetRef)))
        offsetRefSegmented = offSeg
        primarySec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("时差基准", "Offset Reference"),
            accessory: offSeg
        ))

        primarySec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("顶部显示世界时钟栏", "Show World Clock Header"),
            accessory: makeBoundSwitch(key: kDualTZShowHeroHeader)
        ))

        primarySec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("附带 NY / UTC 简参考", "Show NY & UTC Line"),
            accessory: makeBoundSwitch(key: kDualTZShowThirdRefTZ)
        ))

        addPageBlock(primarySec)

        // 分组 2：副城与别名
        let sec2 = SettingsSectionView(
            title: LocalizationService.pick("副城与别名", "Secondary Cities & Aliases"),
            footer: LocalizationService.pick(
                "副城卡片自动识别夏令时（PST/PDT、EST/EDT）并标注当地工作状态（办公中 / 消费高峰 / 深夜）。",
                "Secondary cards handle DST transitions automatically and show local business status."
            )
        )

        let searchWrap = NSView()
        searchWrap.translatesAutoresizingMaskIntoConstraints = false
        let searchField = NSTextField(string: citySearchQuery)
        searchField.placeholderString = LocalizationService.pick("搜索城市或时区缩写（如 伦敦 / Tokyo / EST）...", "Search city or TZ (London / Tokyo / EST)...")
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.identifier = NSUserInterfaceItemIdentifier("citySearch")
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchWrap.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchWrap.heightAnchor.constraint(equalToConstant: 44),
            searchField.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchWrap.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: searchWrap.trailingAnchor, constant: -14)
        ])
        citySearchField = searchField

        sec2.card.addRow(searchWrap)
        cityRowsCard = sec2.card
        populateCityRows(into: sec2.card, skipFirstSearchRow: true)

        addPageBlock(sec2)
    }

    private func populateCityRows(into card: SettingsCardView, skipFirstSearchRow: Bool) {
        if !skipFirstSearchRow, let searchRow = card.subviews.first?.subviews.first {
            // 保留搜索框所在首行，仅重建城市列表部分较麻烦；直接重建全部但保留搜索内容及聚焦态
            _ = searchRow
        }
        let q = citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        let matched = WorldClockStore.cityCatalog.filter { item in
            guard !q.isEmpty else { return true }
            let tz = TimeZone(identifier: item.timeZoneIdentifier)
            let abbr = tz.map { WorldClockStore.dynamicAbbreviation(for: item, at: now, timeZone: $0).lowercased() } ?? ""
            return item.nameZH.contains(q)
                || item.nameEN.lowercased().contains(q)
                || item.id.lowercased().contains(q)
                || abbr.contains(q)
        }

        if matched.isEmpty {
            let emptyLabel = NSTextField(labelWithString: LocalizationService.pick("无匹配城市", "No matching city"))
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = NSColor.tertiaryLabelColor
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 42),
                emptyLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                emptyLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
            card.addRow(row)
            return
        }

        for item in matched {
            let cfg = WorldClockStore.secondaryConfig(for: item.id)
            let cityTZ = TimeZone(identifier: item.timeZoneIdentifier) ?? TimeZone.autoupdatingCurrent
            let abbr = WorldClockStore.dynamicAbbreviation(for: item, at: now, timeZone: cityTZ)
            let utcStr = WorldClockStore.utcOffsetString(for: cityTZ, at: now)

            let sw = NSSwitch()
            sw.controlSize = .small
            sw.state = cfg.enabled ? .on : .off
            sw.identifier = NSUserInterfaceItemIdentifier("city_\(item.id)")
            sw.target = self
            sw.action = #selector(citySwitchToggled(_:))

            let accStack = NSStackView()
            accStack.orientation = .horizontal
            accStack.alignment = .centerY
            accStack.spacing = 8

            if cfg.enabled {
                let aliasInp = NSTextField(string: cfg.alias)
                aliasInp.placeholderString = LocalizationService.pick("自定义别名…", "Alias…")
                aliasInp.font = NSFont.systemFont(ofSize: 11.5)
                aliasInp.identifier = NSUserInterfaceItemIdentifier("alias_\(item.id)")
                aliasInp.delegate = self
                aliasInp.widthAnchor.constraint(equalToConstant: 108).isActive = true
                accStack.addArrangedSubview(aliasInp)
            }
            accStack.addArrangedSubview(sw)

            card.addRow(SettingsRowView(
                title: "\(item.flag) \(LocalizationService.pick(item.nameZH, item.nameEN)) (\(abbr))",
                subtitle: utcStr,
                accessory: accStack
            ))
        }
    }

    // MARK: - Tab 3: 日历与节假日

    private func buildCalendarTab() {
        let d = UserDefaults.standard
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("日历与节假日", "Calendar & Holidays"),
            subtitle: LocalizationService.pick("保留 Itsycal 经典月历特征与中美跨境节假日", "Retain classic Itsycal layout & US/China holiday indicators")
        ))

        let gridSec = SettingsSectionView(title: LocalizationService.pick("月历外观", "Calendar Appearance"))

        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("左侧周数", "Week Numbers"),
            subtitle: LocalizationService.pick("ISO-8601 周序，如 44–49", "ISO-8601 week column"),
            accessory: makeBoundSwitch(key: kShowWeeks)
        ))

        let outlineSw = NSSwitch()
        outlineSw.controlSize = .small
        outlineSw.state = !d.bool(forKey: kDoNotDrawOutlineAroundCurrentMonth) ? .on : .off
        outlineSw.target = self
        outlineSw.action = #selector(monthOutlineToggled(_:))
        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("当月轮廓线", "Month Outline"),
            subtitle: LocalizationService.pick("柔光连续折线区分本月范围", "Continuous border around in-month days"),
            accessory: outlineSw
        ))

        let monSw = NSSwitch()
        monSw.controlSize = .small
        monSw.state = (d.integer(forKey: kWeekStartDOW) == 1) ? .on : .off
        monSw.target = self
        monSw.action = #selector(weekStartMondayToggled(_:))
        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("周一为首日", "Start Week on Monday"),
            accessory: monSw
        ))

        let wkndSw = NSSwitch()
        wkndSw.controlSize = .small
        wkndSw.state = (d.integer(forKey: kHighlightedDOWs) != 0) ? .on : .off
        wkndSw.target = self
        wkndSw.action = #selector(highlightWeekendsToggled(_:))
        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("周末底纹", "Highlight Weekends"),
            accessory: wkndSw
        ))

        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("双今日标记", "Dual Today Mark"),
            subtitle: LocalizationService.pick("跨天时同标主城与美西今日", "Highlight both primary and US local dates"),
            accessory: makeBoundSwitch(key: kDualTZShowDualToday)
        ))

        let sizeSeg = NSSegmentedControl(
            labels: [
                LocalizationService.pick("小", "Small"),
                LocalizationService.pick("中", "Medium"),
                LocalizationService.pick("大", "Large")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(sizePrefChanged(_:))
        )
        sizeSeg.controlSize = .small
        sizeSeg.selectedSegment = max(0, min(2, d.integer(forKey: kSizePreference)))
        gridSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("日历尺寸", "Calendar Size"),
            accessory: sizeSeg
        ))

        addPageBlock(gridSec)

        // 分组 2：农历与节假日
        let holSec = SettingsSectionView(
            title: LocalizationService.pick("农历与节假日", "Lunar & Holidays"),
            footer: LocalizationService.pick(
                "内置离线节假日表与农历引擎，中国调休安排可通过在线同步或导入本地 JSON 更新。",
                "Built-in offline calendar tables with online sync or JSON import for China holiday schedules."
            )
        )

        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("农历与节气", "Lunar & Solar Terms"),
            accessory: makeBoundSwitch(key: kDualTZShowLunarSolarTerms)
        ))
        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("中国法定假日", "China Holidays"),
            subtitle: LocalizationService.pick("含休 / 班调休角标", "Includes Off/Work badges"),
            accessory: makeBoundSwitch(key: kDualTZShowChinaHolidays)
        ))
        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("美国联邦假日", "US Federal & BFCM"),
            subtitle: LocalizationService.pick("含感恩节、黑五、网一", "Thanksgiving, Black Friday, Cyber Monday"),
            accessory: makeBoundSwitch(key: kDualTZShowUSHolidays)
        ))
        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("跨境营销节点", "Retail Nodes"),
            subtitle: LocalizationService.pick("618、双11、万圣节、母亲/父亲节等", "618, 11.11, Halloween"),
            accessory: makeBoundSwitch(key: kDualTZShowMarketingNodes)
        ))
        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("夏令时跳变预警", "US DST Transition Alert"),
            subtitle: LocalizationService.pick("美西冬/夏令时切换前 7 天顶部提示", "Warn 7 days before US DST shift"),
            accessory: makeBoundSwitch(key: kDualTZShowDSTWarning)
        ))

        let syncBtn = NSButton(title: LocalizationService.pick("在线同步", "Sync"), target: self, action: #selector(syncHolidaysClicked(_:)))
        syncBtn.bezelStyle = .rounded
        syncBtn.controlSize = .small
        let importBtn = NSButton(title: LocalizationService.pick("导入 JSON…", "Import…"), target: self, action: #selector(importHolidayJSONClicked(_:)))
        importBtn.bezelStyle = .rounded
        importBtn.controlSize = .small

        let holidayActionRow = NSStackView(views: [syncBtn, importBtn])
        holidayActionRow.orientation = .horizontal
        holidayActionRow.spacing = 6
        holSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("调休数据", "Holiday Table"),
            subtitle: ChinaHolidayStore.shared.statusSummary(),
            accessory: holidayActionRow
        ))

        addPageBlock(holSec)
    }

    // MARK: - Tab 4: 日程与提醒

    private func buildEventsTab() {
        let d = UserDefaults.standard
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("日程与提醒", "Events & Reminders"),
            subtitle: LocalizationService.pick("基于系统日历，全程以主城市时间为第一视角", "Read & create EventKit events anchored in primary time")
        ))

        let permSec = SettingsSectionView(title: LocalizationService.pick("日历权限", "Permissions"))
        let granted = eventCenter?.calendarAccessGranted ?? false
        let permBadge = SettingsStatusBadge(
            text: granted ? LocalizationService.pick("已授权", "Granted") : LocalizationService.pick("未授权", "Denied"),
            tone: granted ? .ok : .warn
        )
        permSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("系统日历访问", "Calendar Access"),
            subtitle: granted
                ? LocalizationService.pick("已读取本地与 iCloud 日历", "Reading local & iCloud calendars")
                : LocalizationService.pick("请在系统隐私设置中开启日历权限", "Enable access in System Settings › Calendars"),
            accessory: permBadge
        ))

        let openPrivacyBtn = NSButton(title: LocalizationService.pick("前往系统设置…", "Open Settings…"), target: self, action: #selector(openPrivacySettingsClicked(_:)))
        openPrivacyBtn.bezelStyle = .rounded
        openPrivacyBtn.controlSize = .small
        permSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("隐私设置", "Privacy Settings"),
            accessory: openPrivacyBtn
        ))

        addPageBlock(permSec)

        let agendaSec = SettingsSectionView(
            title: LocalizationService.pick("日程显示与新建", "Agenda & Creation"),
            footer: LocalizationService.pick(
                "全天日程严格锁定所选公历单日，避免因 16 小时时差产生跨天偏移。",
                "All-day events lock strictly to the selected date to prevent 16h day drift."
            )
        )
        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("附注美西时间", "Dual-TZ Subtitle"),
            subtitle: LocalizationService.pick("在日程副标题显示美西对照", "Show US Pacific ref time below primary hours"),
            accessory: makeBoundSwitch(key: kDualTZShowAgendaDualTZ)
        ))
        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("新建默认主时区", "Default to Primary TZ"),
            subtitle: LocalizationService.pick("新建弹窗优先按北京时间录入", "New Event defaults to primary time zone"),
            accessory: makeBoundSwitch(key: kDualTZAllowBJEventCreate)
        ))
        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("新建深夜预警", "Late-Night Alert"),
            subtitle: LocalizationService.pick("对端 00:00–06:59 自动亮橙提示", "Warns when counterpart falls in 00:00–06:59"),
            accessory: makeBoundSwitch(key: kDualTZWarnLateNight)
        ))
        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("列表显示内置节假日", "Built-in Holidays in Agenda"),
            accessory: makeBoundSwitch(key: kDualTZShowAgendaHolidays)
        ))

        let daysOptions: [(val: Int, label: String)] = [
            (0, LocalizationService.pick("不显示", "No events")),
            (1, LocalizationService.pick("1 天", "1 day")),
            (2, LocalizationService.pick("2 天", "2 days")),
            (3, LocalizationService.pick("3 天", "3 days")),
            (4, LocalizationService.pick("4 天", "4 days")),
            (5, LocalizationService.pick("5 天", "5 days")),
            (6, LocalizationService.pick("6 天", "6 days")),
            (7, LocalizationService.pick("7 天", "7 days")),
            (8, LocalizationService.pick("14 天", "14 days")),
            (9, LocalizationService.pick("31 天", "31 days"))
        ]
        let daysPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for opt in daysOptions {
            daysPopup.addItem(withTitle: opt.label)
            daysPopup.lastItem?.tag = opt.val
        }
        let curDays = d.integer(forKey: kShowEventDays)
        daysPopup.selectItem(withTag: daysOptions.contains(where: { $0.val == curDays }) ? curDays : 4)
        daysPopup.target = self
        daysPopup.action = #selector(previewDaysChanged(_:))
        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("预览天数", "Preview Horizon"),
            accessory: daysPopup
        ))

        agendaSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("显示地点与无日程日", "Locations & Empty Days"),
            subtitle: LocalizationService.pick("显示地点备注并在列表展示空白日期", "Show location text & days with no events"),
            accessory: makeDualSwitchPair(keyA: kShowLocation, keyB: kShowDaysWithNoEventsInAgenda)
        ))

        addPageBlock(agendaSec)

        // 分组 3：系统日历源（原生 Bento 呈现）
        if let ec = eventCenter {
            let items = ec.sourcesAndCalendars() ?? []
            if !items.isEmpty {
                let calSec = SettingsSectionView(title: LocalizationService.pick("系统日历源", "Calendars"))
                for item in items {
                    if let sourceName = item as? String {
                        let headerRow = NSView()
                        headerRow.translatesAutoresizingMaskIntoConstraints = false
                        let lbl = NSTextField(labelWithString: sourceName)
                        lbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
                        lbl.textColor = NSColor.secondaryLabelColor
                        lbl.translatesAutoresizingMaskIntoConstraints = false
                        headerRow.addSubview(lbl)
                        NSLayoutConstraint.activate([
                            headerRow.heightAnchor.constraint(equalToConstant: 28),
                            lbl.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 14),
                            lbl.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor)
                        ])
                        calSec.card.addRow(headerRow)
                    } else if let calInfo = item as? CalendarInfo {
                        let sw = NSSwitch()
                        sw.controlSize = .small
                        sw.state = calInfo.selected ? .on : .off
                        sw.identifier = NSUserInterfaceItemIdentifier("cal_\(calInfo.calendar.calendarIdentifier)")
                        sw.target = self
                        sw.action = #selector(calendarSourceToggled(_:))
                        calSec.card.addRow(SettingsRowView(
                            title: calInfo.calendar.title,
                            leadingDotColor: calInfo.calendar.color,
                            accessory: sw
                        ))
                    }
                }
                if ec.remindersAuthorizationStatus != .fullAccess {
                    let reqBtn = NSButton(title: LocalizationService.pick("授权提醒事项…", "Enable Reminders…"), target: self, action: #selector(requestRemindersClicked(_:)))
                    reqBtn.bezelStyle = .rounded
                    reqBtn.controlSize = .small
                    calSec.card.addRow(SettingsRowView(
                        title: LocalizationService.pick("系统提醒事项", "Reminders"),
                        accessory: reqBtn
                    ))
                }
                addPageBlock(calSec)
            }
        }
    }

    // MARK: - Tab 5: 额度与订阅 (v2.1 离线订阅账本 + v2.2 规划)

    private func buildQuotaTab() {
        let d = UserDefaults.standard
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("额度与订阅", "Quotas & Subscriptions"),
            subtitle: LocalizationService.pick("追踪多账号 AI 额度重置与海外订阅扣费日", "Track multi-account AI quota resets and offline subscriptions")
        ))

        let modSec = SettingsSectionView()
        let showBar = d.bool(forKey: kDualTZShowSubscriptionBar)
        let expandedBar = d.bool(forKey: kDualTZSubscriptionBarExpanded)
        let modSeg = NSSegmentedControl(
            labels: [
                LocalizationService.pick("关闭", "Off"),
                LocalizationService.pick("精简微环", "Mini"),
                LocalizationService.pick("展开总览", "Expanded")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(bottomSubModuleChanged(_:))
        )
        modSeg.controlSize = .small
        modSeg.selectedSegment = !showBar ? 0 : (expandedBar ? 2 : 1)
        modSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("主面板底部模块", "Bottom Panel Module"),
            subtitle: LocalizationService.pick("控制圆环进度条在主弹窗底部的展示形态", "Control progress rings in the main popover"),
            accessory: modSeg
        ))
        modSec.card.addRow(SettingsRowView(
            title: LocalizationService.pick("启用多账号 AI 额度池", "Enable Multi-Account AI Quota Pool"),
            subtitle: LocalizationService.pick("按弹窗打开 5 分钟节流只读刷新，不修改外部登录凭据", "Focus-throttled read-only refresh without mutating external tokens"),
            accessory: makeBoundSwitch(key: kDualTZShowAIQuotaPool)
        ))
        addPageBlock(modSec)

        // 多账号 AI 额度池分组（v2.2.0）
        discoveredClaudeServices = AIQuotaStore.discoverClaudeKeychainServices()
        let aiSec = SettingsSectionView(
            title: LocalizationService.pick("多账号 AI 额度池 (Claude / Gemini / Codex / Cursor)", "AI Quota Pool (Claude / Gemini / Codex / Cursor)"),
            footer: LocalizationService.pick(
                "仅读取官方客户端本地凭据或 Keychain 属性（后台永不弹授权框，绝不覆写外部登录态，不访问浏览器 Cookie）。多号休眠默认零心跳被动同步，点单条 ↻ 可按需安全唤醒。",
                "Reads local client auth read-only (silent Keychain queries, zero browser cookie scraping, never overwrites external logins). Dormant Claude accounts stay passive by default; click row ↻ to wake one safely."
            ),
            actionTitle: LocalizationService.pick("+ 添加账号", "+ Add Account"),
            actionTarget: self,
            actionSelector: #selector(addAIAccountClicked(_:))
        )

        aiSec.card.addRow(buildAIToolbarRow())

        let aiAccounts = AIQuotaStore.loadAccounts()
        let aiSnapshots = AIQuotaStore.loadSnapshots()
        if aiAccounts.isEmpty {
            aiSec.card.addRow(SettingsRowView(
                title: LocalizationService.pick("暂无监控账号", "No AI Accounts"),
                subtitle: LocalizationService.pick("点击「自动发现」或右上角「+ 添加账号」", "Click Auto-Discover or + Add Account"),
                accessory: NSView()
            ))
        } else {
            for acc in aiAccounts {
                aiSec.card.addRow(buildAIAccountRow(account: acc, snapshot: aiSnapshots[acc.id]))
            }
        }
        addPageBlock(aiSec)

        // 订阅账本分组
        let subSec = SettingsSectionView(
            title: LocalizationService.pick("订阅提醒", "Subscriptions"),
            footer: LocalizationService.pick(
                "纯离线本地推算，支持自定义名称与备注付款账号、区域及卡尾号，到期日自动在月历标出橙点。",
                "Offline billing calculator with custom labels, emails, region tags, and card notes; marks due days on calendar."
            ),
            actionTitle: LocalizationService.pick("+ 添加订阅", "+ Add"),
            actionTarget: self,
            actionSelector: #selector(addSubscriptionClicked(_:))
        )

        let subs = SubscriptionStore.loadAll()
        if subs.isEmpty {
            let emptyRow = SettingsRowView(
                title: LocalizationService.pick("暂无订阅记录", "No Subscriptions"),
                subtitle: LocalizationService.pick("点击右上角「+ 添加订阅」创建一条", "Click '+ Add' to track a renewal"),
                accessory: NSView()
            )
            subSec.card.addRow(emptyRow)
        } else {
            for item in subs {
                subSec.card.addRow(buildSubscriptionRow(item: item))
            }
        }
        addPageBlock(subSec)
    }

    private func buildAIToolbarRow() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let discoverBtn = NSButton(
            title: LocalizationService.pick("自动发现本机账号", "Auto-Discover"),
            target: self,
            action: #selector(autoDiscoverAIClicked(_:))
        )
        discoverBtn.bezelStyle = .rounded
        discoverBtn.controlSize = .small

        let refreshAllBtn = NSButton(
            title: LocalizationService.pick("立即刷新全部", "Refresh All"),
            target: self,
            action: #selector(refreshAllAIClicked(_:))
        )
        refreshAllBtn.bezelStyle = .rounded
        refreshAllBtn.controlSize = .small

        let svcCount = discoveredClaudeServices.count
        let hintText = svcCount > 0
            ? LocalizationService.pick("已发现 \(svcCount) 个 Claude Keychain 条目", "Found \(svcCount) Claude Keychain entries")
            : LocalizationService.pick("可手动配置隔离目录与平台", "Add local CLI or IDE accounts")
        let hintLabel = NSTextField(labelWithString: hintText)
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView(views: [discoverBtn, refreshAllBtn, spacer, hintLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        return wrap
    }

    private func buildAIAccountRow(account: AIQuotaAccount, snapshot: AIQuotaSnapshot?) -> NSView {
        let isEditing = (editingAIID == account.id)
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let badge = makeProviderPill(provider: account.provider)

        let nameLabel = NSTextField(labelWithString: account.customName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        let titleGroup = NSStackView(views: [badge, nameLabel])
        titleGroup.orientation = .horizontal
        titleGroup.alignment = .centerY
        titleGroup.spacing = 7

        let pctText: String
        let pctTone: SettingsStatusBadge.Tone
        var pctTooltip = account.provider.displayName
        if let snap = snapshot, let pct = snap.effectiveRemainingPercent {
            pctText = "\(Int(round(pct)))%"
            pctTone = pct >= 50 ? .info : .warn
            if let secPct = snap.secondaryRemainingPercent, let secLbl = snap.secondaryWindowLabel {
                pctTooltip = "\(snap.primaryWindowLabel) \(Int(round(pct)))% · \(secLbl) \(Int(round(secPct)))%"
            } else {
                pctTooltip = "\(snap.primaryWindowLabel) \(Int(round(pct)))%"
            }
        } else {
            pctText = "--"
            pctTone = (snapshot?.state == .needsKeychainPermission || snapshot?.state == .needsLogin || snapshot?.state == .rateLimited) ? .warn : .info
            if let msg = snapshot?.statusMessage {
                pctTooltip = msg
            }
        }
        let pctBadge = SettingsStatusBadge(text: pctText, tone: pctTone)
        pctBadge.toolTip = pctTooltip

        let refreshRowBtn = NSButton(
            title: "↻",
            target: self,
            action: #selector(refreshSingleAIClicked(_:))
        )
        refreshRowBtn.bezelStyle = .rounded
        refreshRowBtn.controlSize = .small
        refreshRowBtn.identifier = NSUserInterfaceItemIdentifier(account.id)
        refreshRowBtn.toolTip = LocalizationService.pick(
            "单条刷新此账号（休眠 Claude 账号将按需安全唤醒，不影响其他号）",
            "Refresh only this account (safely wakes a dormant Claude account via official CLI)"
        )
        if let sym = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
            refreshRowBtn.image = sym.withSymbolConfiguration(cfg)
            refreshRowBtn.imagePosition = .imageOnly
            refreshRowBtn.title = ""
        }

        let editBtn = NSButton(
            title: isEditing ? LocalizationService.pick("收起", "Done") : LocalizationService.pick("编辑", "Edit"),
            target: self,
            action: #selector(toggleEditAIClicked(_:))
        )
        editBtn.bezelStyle = .rounded
        editBtn.controlSize = .small
        editBtn.identifier = NSUserInterfaceItemIdentifier(account.id)

        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = account.enabled ? .on : .off
        sw.identifier = NSUserInterfaceItemIdentifier("aien_\(account.id)")
        sw.target = self
        sw.action = #selector(aiAccountEnableToggled(_:))

        let rightGroup = NSStackView(views: [pctBadge, refreshRowBtn, editBtn, sw])
        rightGroup.orientation = .horizontal
        rightGroup.alignment = .centerY
        rightGroup.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let topLine = NSStackView(views: [titleGroup, spacer, rightGroup])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.spacing = 8

        var subParts: [String] = []
        if let email = snapshot?.accountEmail, !email.isEmpty {
            subParts.append(email)
        } else {
            subParts.append(account.sourceSubtitle)
        }
        if let plan = snapshot?.planLabel, !plan.isEmpty {
            subParts.append(plan)
        }
        if let snap = snapshot {
            if snap.state == .cached, let msg = snap.statusMessage, !msg.isEmpty {
                subParts.append(msg)
            } else if let resetText = snap.formattedResetText() {
                subParts.append(resetText)
            } else if snap.state == .live {
                if let secPct = snap.secondaryRemainingPercent, let secLbl = snap.secondaryWindowLabel {
                    subParts.append(LocalizationService.pick("\(secLbl) \(Int(round(secPct)))% · 满额待用", "\(secLbl) \(Int(round(secPct)))% · Ready"))
                } else {
                    subParts.append(LocalizationService.pick("满额待用 · 实时", "Full · Live"))
                }
            } else if let msg = snap.statusMessage, !msg.isEmpty {
                subParts.append(msg)
            } else {
                subParts.append(LocalizationService.pick("尚未刷新 · 点右侧同步", "Pending sync"))
            }
        } else {
            subParts.append(LocalizationService.pick("尚未刷新 · 点右侧同步", "Pending sync"))
        }

        let subLabel = NSTextField(labelWithString: subParts.joined(separator: " · "))
        subLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = NSColor.secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [topLine, subLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        topLine.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        subLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if isEditing {
            let form = buildAIEditForm(account: account)
            stack.addArrangedSubview(form)
            form.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        return wrap
    }

    private func makeProviderPill(provider: AIQuotaProvider) -> NSView {
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 5
        pill.layer?.cornerCurve = .continuous
        pill.layer?.backgroundColor = provider.accentColor.withAlphaComponent(0.18).cgColor

        let lbl = NSTextField(labelWithString: provider.badgeText)
        lbl.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        lbl.textColor = provider.accentColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2.5),
            lbl.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2.5),
            lbl.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            lbl.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6)
        ])
        return pill
    }

    private func buildAIEditForm(account: AIQuotaAccount) -> NSView {
        let box = makeInlineEditBox()

        let nameField = NSTextField(string: account.customName)
        edAINameField = nameField

        let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for p in AIQuotaProvider.allCases {
            providerPopup.addItem(withTitle: p.displayName)
            providerPopup.lastItem?.representedObject = p.rawValue
        }
        if let idx = AIQuotaProvider.allCases.firstIndex(of: account.provider) {
            providerPopup.selectItem(at: idx)
        }
        providerPopup.target = self
        providerPopup.action = #selector(aiProviderPopupChanged(_:))
        edAIProviderPopup = providerPopup

        let pathField = NSTextField(string: account.configPath)
        pathField.placeholderString = LocalizationService.pick("可留空 (~/.claude-work)", "Optional (~/.claude-work)")
        edAIConfigPathField = pathField

        let kcPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        kcPopup.addItem(withTitle: LocalizationService.pick("自动按目录计算", "Auto by Directory"))
        kcPopup.lastItem?.representedObject = ""
        for svc in discoveredClaudeServices {
            kcPopup.addItem(withTitle: svc)
            kcPopup.lastItem?.representedObject = svc
        }
        if !account.keychainService.isEmpty && !discoveredClaudeServices.contains(account.keychainService) {
            kcPopup.addItem(withTitle: account.keychainService)
            kcPopup.lastItem?.representedObject = account.keychainService
        }
        let targetSvc = account.keychainService
        if let idx = kcPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == targetSvc }) {
            kcPopup.selectItem(at: idx)
        }
        kcPopup.isEnabled = (account.provider == .claude)
        edAIKeychainPopup = kcPopup

        let r1 = makeFormRow(
            leftLabel: LocalizationService.pick("自定义账号名称", "Custom Account Name"), leftControl: nameField,
            rightLabel: LocalizationService.pick("AI 平台类型", "AI Provider"), rightControl: providerPopup
        )
        let r2 = makeFormRow(
            leftLabel: LocalizationService.pick("隔离配置目录 / DB 路径", "Config Dir / DB Path"), leftControl: pathField,
            rightLabel: LocalizationService.pick("Claude Keychain 条目", "Claude Keychain Service"), rightControl: kcPopup
        )

        let refreshOneBtn = NSButton(
            title: LocalizationService.pick("单条刷新 / 授权", "Refresh / Auth"),
            target: self,
            action: #selector(refreshSingleAIClicked(_:))
        )
        refreshOneBtn.bezelStyle = .rounded
        refreshOneBtn.controlSize = .small
        refreshOneBtn.identifier = NSUserInterfaceItemIdentifier(account.id)

        let delBtn = NSButton(title: LocalizationService.pick("删除", "Delete"), target: self, action: #selector(deleteAIClicked(_:)))
        delBtn.isBordered = false
        delBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        delBtn.contentTintColor = NSColor.systemRed
        delBtn.identifier = NSUserInterfaceItemIdentifier(account.id)

        let cancelBtn = NSButton(title: LocalizationService.pick("取消", "Cancel"), target: self, action: #selector(cancelEditAIClicked(_:)))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .small

        let saveBtn = NSButton(title: LocalizationService.pick("保存更新", "Save"), target: self, action: #selector(saveEditAIClicked(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .small
        saveBtn.keyEquivalent = "\r"
        saveBtn.identifier = NSUserInterfaceItemIdentifier(account.id)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let actions = NSStackView(views: [refreshOneBtn, delBtn, spacer, cancelBtn, saveBtn])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        let stack = NSStackView(views: [r1, r2, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        [r1, r2, actions].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])
        return box
    }

    private func makeInlineEditBox() -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.cornerCurve = .continuous
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        box.layer?.borderWidth = 0.75
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        return box
    }

    private func buildSubscriptionRow(item: SubscriptionItem) -> NSView {
        let snap = SubscriptionStore.snapshot(for: item)
        let isEditing = (editingSubID == item.id)

        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: item.customName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        let regionTag = SettingsStatusBadge(text: item.region.localizedLabel, tone: .info)

        let titleGroup = NSStackView(views: [nameLabel, regionTag])
        titleGroup.orientation = .horizontal
        titleGroup.alignment = .centerY
        titleGroup.spacing = 6

        let priceLabel = NSTextField(labelWithString: item.priceText)
        priceLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        priceLabel.textColor = NSColor.secondaryLabelColor

        let etaBadge = SettingsStatusBadge(text: snap.etaLongText, tone: snap.isUrgent ? .warn : .ok)

        let editBtn = NSButton(
            title: isEditing ? LocalizationService.pick("收起", "Done") : LocalizationService.pick("编辑", "Edit"),
            target: self,
            action: #selector(toggleEditSubscriptionClicked(_:))
        )
        editBtn.bezelStyle = .rounded
        editBtn.controlSize = .small
        editBtn.identifier = NSUserInterfaceItemIdentifier(item.id)

        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = item.enabled ? .on : .off
        sw.identifier = NSUserInterfaceItemIdentifier("suben_\(item.id)")
        sw.target = self
        sw.action = #selector(subscriptionEnableToggled(_:))

        let rightGroup = NSStackView(views: [priceLabel, etaBadge, editBtn, sw])
        rightGroup.orientation = .horizontal
        rightGroup.alignment = .centerY
        rightGroup.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let topLine = NSStackView(views: [titleGroup, spacer, rightGroup])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.spacing = 8

        let metaLine = NSStackView(views: [
            makeMetaChip(symbol: "person", text: item.accountEmail),
            makeMetaChip(symbol: "creditcard", text: item.paymentMethod),
            makeMetaChip(symbol: "clock", text: snap.dueDetailText)
        ])
        metaLine.orientation = .horizontal
        metaLine.alignment = .centerY
        metaLine.spacing = 10

        let stack = NSStackView(views: [topLine, metaLine])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        topLine.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if isEditing {
            let form = buildSubscriptionEditForm(item: item)
            stack.addArrangedSubview(form)
            form.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -11),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        return wrap
    }

    private func makeMetaChip(symbol: String, text: String) -> NSView {
        let imgView = NSImageView()
        imgView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .regular))
        imgView.contentTintColor = NSColor.tertiaryLabelColor

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [imgView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        return row
    }

    private func buildSubscriptionEditForm(item: SubscriptionItem) -> NSView {
        let box = makeInlineEditBox()

        let nameField = NSTextField(string: item.customName)
        edSubNameField = nameField
        let acctField = NSTextField(string: item.accountEmail)
        edSubAcctField = acctField

        let regPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for reg in SubscriptionRegion.allCases {
            regPopup.addItem(withTitle: reg.localizedLabel)
            regPopup.lastItem?.representedObject = reg.rawValue
        }
        if let idx = SubscriptionRegion.allCases.firstIndex(of: item.region) {
            regPopup.selectItem(at: idx)
        }
        edSubRegionPopup = regPopup

        let payField = NSTextField(string: item.paymentMethod)
        edSubPayField = payField
        let priceField = NSTextField(string: item.priceText)
        edSubPriceField = priceField
        let dayField = NSTextField(string: "\(item.billingDay)")
        edSubDayField = dayField

        let r1 = makeFormRow(
            leftLabel: LocalizationService.pick("自定义名称", "Custom Name"), leftControl: nameField,
            rightLabel: LocalizationService.pick("扣费账号 / 邮箱", "Account / Email"), rightControl: acctField
        )
        let r2 = makeFormRow(
            leftLabel: LocalizationService.pick("国家 / 区域", "Region"), leftControl: regPopup,
            rightLabel: LocalizationService.pick("付款方式 / 卡尾号", "Payment Method"), rightControl: payField
        )
        let r3 = makeFormRow(
            leftLabel: LocalizationService.pick("扣费金额", "Price"), leftControl: priceField,
            rightLabel: LocalizationService.pick("每月扣费日 (1–31)", "Billing Day (1–31)"), rightControl: dayField
        )

        let delBtn = NSButton(title: LocalizationService.pick("删除此订阅", "Delete"), target: self, action: #selector(deleteSubscriptionClicked(_:)))
        delBtn.isBordered = false
        delBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        delBtn.contentTintColor = NSColor.systemRed
        delBtn.identifier = NSUserInterfaceItemIdentifier(item.id)

        let cancelBtn = NSButton(title: LocalizationService.pick("取消", "Cancel"), target: self, action: #selector(cancelEditSubscriptionClicked(_:)))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .small

        let saveBtn = NSButton(title: LocalizationService.pick("保存更新", "Save"), target: self, action: #selector(saveEditSubscriptionClicked(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .small
        saveBtn.keyEquivalent = "\r"
        saveBtn.identifier = NSUserInterfaceItemIdentifier(item.id)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let actions = NSStackView(views: [delBtn, spacer, cancelBtn, saveBtn])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        let stack = NSStackView(views: [r1, r2, r3, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        [r1, r2, r3, actions].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])
        return box
    }

    private func makeFormRow(leftLabel: String, leftControl: NSView, rightLabel: String, rightControl: NSView) -> NSView {
        func col(title: String, ctrl: NSView) -> NSStackView {
            let lbl = NSTextField(labelWithString: title)
            lbl.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            lbl.textColor = NSColor.secondaryLabelColor
            if let tf = ctrl as? NSTextField {
                tf.font = NSFont.systemFont(ofSize: 11.5)
            }
            let st = NSStackView(views: [lbl, ctrl])
            st.orientation = .vertical
            st.alignment = .leading
            st.spacing = 3
            ctrl.widthAnchor.constraint(equalTo: st.widthAnchor).isActive = true
            return st
        }
        let row = NSStackView(views: [col(title: leftLabel, ctrl: leftControl), col(title: rightLabel, ctrl: rightControl)])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 10
        return row
    }

    // MARK: - Tab 6: 关于

    private func buildAboutTab() {
        addPageBlock(SettingsPageHeaderView(
            title: LocalizationService.pick("关于", "About"),
            subtitle: LocalizationService.pick("基于 sfsam/Itsycal MIT 开源协议深度重构", "Built upon sfsam/Itsycal under the MIT License")
        ))

        let brandSec = SettingsSectionView(
            footer: "© 2026 Morgan Lee (GangdanLee) · MIT License · Zero Telemetry"
        )

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.2"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2202"
        brandSec.card.addRow(SettingsRowView(
            title: "Itsycal DualTZ",
            subtitle: LocalizationService.tr("dualtz.about.tagline"),
            accessory: SettingsStatusBadge(text: "v\(version) (\(build))", tone: .info)
        ))

        let ghBtn = makeLinkButton(title: "GangdanLee/Itsycal-DualTZ ↗", action: #selector(openGitHubRepo))
        brandSec.card.addRow(SettingsRowView(
            title: LocalizationService.tr("dualtz.about.github"),
            accessory: ghBtn
        ))

        let relBtn = makeLinkButton(title: "Releases ↗", action: #selector(openReleases))
        brandSec.card.addRow(SettingsRowView(
            title: LocalizationService.tr("dualtz.about.releases"),
            accessory: relBtn
        ))

        let upBtn = makeLinkButton(title: "sfsam/Itsycal ↗", action: #selector(openUpstreamRepo))
        brandSec.card.addRow(SettingsRowView(
            title: LocalizationService.tr("dualtz.about.upstream"),
            subtitle: LocalizationService.tr("dualtz.about.upstream_copy"),
            accessory: upBtn
        ))

        addPageBlock(brandSec)
    }

    // MARK: - Controls Helpers & Actions

    private func makeBoundSwitch(key: String) -> NSSwitch {
        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        sw.identifier = NSUserInterfaceItemIdentifier("bool_\(key)")
        sw.target = self
        sw.action = #selector(boundSwitchToggled(_:))
        return sw
    }

    private func makeDualSwitchPair(keyA: String, keyB: String) -> NSView {
        let swA = makeBoundSwitch(key: keyA)
        let swB = makeBoundSwitch(key: keyB)
        let stack = NSStackView(views: [swA, swB])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func makeLinkButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        btn.contentTintColor = NSColor.controlAccentColor
        return btn
    }

    @objc private func boundSwitchToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("bool_") else { return }
        let key = String(raw.dropFirst(5))
        UserDefaults.standard.set(sender.state == .on, forKey: key)
        if key == kDualTZShowUpcomingCountdown {
            refreshMenubarPreviewWidgets()
        }
    }

    @objc private func glassStyleChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: kDualTZWindowGlassStyle)
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: kThemePreference)
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: kDualTZAppLanguage)
    }

    @objc private func loginSwitchToggled(_ sender: NSSwitch) {
        MOEnableLoginItem(sender.state == .on)
    }

    @objc private func menuIconModeChanged(_ sender: NSSegmentedControl) {
        let d = UserDefaults.standard
        switch sender.selectedSegment {
        case 0:
            d.set(false, forKey: kHideIcon)
            d.set(true, forKey: kDualTZIconFollowsBeijing)
        case 1:
            d.set(false, forKey: kHideIcon)
            d.set(false, forKey: kDualTZIconFollowsBeijing)
        default:
            d.set(true, forKey: kHideIcon)
        }
        refreshMenubarPreviewWidgets()
    }

    @objc private func tokenPillClicked(_ sender: SettingsTokenPill) {
        UserDefaults.standard.set(false, forKey: kDualTZMenuUseAdvanced)
        var tk = WorldClockStore.loadMenuTokens()
        switch sender.tokenKey {
        case "showPrefix": tk.showPrefix.toggle()
        case "showDate": tk.showDate.toggle()
        case "showWeekday": tk.showWeekday.toggle()
        case "showTime": tk.showTime.toggle()
        case "showUSRef": tk.showUSRef.toggle()
        case "showDayNight": tk.showDayNight.toggle()
        default: break
        }
        WorldClockStore.saveMenuTokens(tk, syncTemplate: true)
        renderSelectedTab()
    }

    @objc private func presetButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(false, forKey: kDualTZMenuUseAdvanced)
        let pid = sender.identifier?.rawValue ?? ""
        var tk = MenuBarTokenConfig()
        switch pid {
        case "minimal":
            tk = MenuBarTokenConfig(showPrefix: false, showDate: false, showWeekday: false, showTime: true, showUSRef: false, showDayNight: false)
        case "dual":
            tk = MenuBarTokenConfig(showPrefix: true, showDate: false, showWeekday: false, showTime: true, showUSRef: true, showDayNight: false)
        case "daynight":
            tk = MenuBarTokenConfig(showPrefix: true, showDate: false, showWeekday: true, showTime: true, showUSRef: false, showDayNight: true)
        default:
            tk = MenuBarTokenConfig(showPrefix: true, showDate: true, showWeekday: true, showTime: true, showUSRef: false, showDayNight: false)
        }
        WorldClockStore.saveMenuTokens(tk, syncTemplate: true)
        renderSelectedTab()
    }

    @objc private func toggleAdvPatternClicked(_ sender: Any?) {
        menuAdvancedExpanded.toggle()
        renderSelectedTab()
    }

    @objc private func toggleUseAdvCodeClicked(_ sender: Any?) {
        let d = UserDefaults.standard
        let next = !d.bool(forKey: kDualTZMenuUseAdvanced)
        d.set(next, forKey: kDualTZMenuUseAdvanced)
        if !next {
            WorldClockStore.syncMenuTemplateFromTokensIfNeeded()
        }
        renderSelectedTab()
    }

    @objc private func primaryTZChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < WorldClockStore.primaryOptions.count else { return }
        UserDefaults.standard.set(WorldClockStore.primaryOptions[idx].identifier, forKey: kDualTZPrimaryTimeZoneID)
        renderSelectedTab()
    }

    @objc private func offsetRefChanged(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment, forKey: kDualTZWorldClockOffsetRef)
    }

    @objc private func citySwitchToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("city_") else { return }
        let cid = String(raw.dropFirst(5))
        WorldClockStore.setSecondaryCity(id: cid, enabled: sender.state == .on)
        renderSelectedTab()
    }

    @objc private func monthOutlineToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state != .on, forKey: kDoNotDrawOutlineAroundCurrentMonth)
    }

    @objc private func weekStartMondayToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on ? 1 : 0, forKey: kWeekStartDOW)
    }

    @objc private func highlightWeekendsToggled(_ sender: NSSwitch) {
        // 周六(位0: 1) + 周日(位6: 64) = 65（遵循 MoCalendar 位掩码约定，或 1<<0 | 1<<6）
        UserDefaults.standard.set(sender.state == .on ? 65 : 0, forKey: kHighlightedDOWs)
    }

    @objc private func sizePrefChanged(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment, forKey: kSizePreference)
    }

    @objc private func syncHolidaysClicked(_ sender: NSButton) {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        sender.isEnabled = false
        ChinaHolidayStore.shared.syncOnline(year: year) { [weak self, weak sender] result in
            sender?.isEnabled = true
            switch result {
            case .success:
                self?.renderSelectedTab()
            case .failure(let error):
                if let window = self?.window {
                    let alert = NSAlert()
                    alert.messageText = LocalizationService.pick("调休表同步提示", "Holiday Sync")
                    alert.informativeText = error.localizedDescription
                    alert.beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    @objc private func importHolidayJSONClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ChinaHolidayStore.shared.importLocalFile(url: url)
            renderSelectedTab()
        } catch {
            if let window = self.window {
                let alert = NSAlert()
                alert.messageText = LocalizationService.pick("导入失败", "Import Failed")
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc private func openPrivacySettingsClicked(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func previewDaysChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        UserDefaults.standard.set(tag, forKey: kShowEventDays)
    }

    @objc private func calendarSourceToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("cal_") else { return }
        let calID = String(raw.dropFirst(4))
        eventCenter?.updateSelectedCalendars(forIdentifier: calID, selected: sender.state == .on)
    }

    @objc private func requestRemindersClicked(_ sender: Any?) {
        eventCenter?.requestRemindersAccess { [weak self] in
            self?.renderSelectedTab()
        }
    }

    @objc private func bottomSubModuleChanged(_ sender: NSSegmentedControl) {
        let d = UserDefaults.standard
        switch sender.selectedSegment {
        case 0:
            d.set(false, forKey: kDualTZShowSubscriptionBar)
            d.set(false, forKey: kDualTZSubscriptionBarExpanded)
        case 1:
            d.set(true, forKey: kDualTZShowSubscriptionBar)
            d.set(false, forKey: kDualTZSubscriptionBarExpanded)
        default:
            d.set(true, forKey: kDualTZShowSubscriptionBar)
            d.set(true, forKey: kDualTZSubscriptionBarExpanded)
        }
    }

    @objc private func addSubscriptionClicked(_ sender: Any?) {
        let nid = "sub_\(UUID().uuidString.prefix(8))"
        let newItem = SubscriptionItem(
            id: nid,
            customName: LocalizationService.pick("Claude Max · 副号", "Claude Max · Alt"),
            accountEmail: "ops@brand.co",
            regionCode: "us",
            paymentMethod: LocalizationService.pick("美卡 Mastercard ••8819", "US MC ••8819"),
            priceText: "$100/mo",
            billingDay: 28,
            billingTimeZoneID: "America/Los_Angeles",
            enabled: true
        )
        SubscriptionStore.add(newItem)
        editingSubID = nid
        renderSelectedTab()
    }

    @objc private func toggleEditSubscriptionClicked(_ sender: NSButton) {
        guard let sid = sender.identifier?.rawValue else { return }
        editingSubID = (editingSubID == sid) ? nil : sid
        renderSelectedTab()
    }

    @objc private func subscriptionEnableToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("suben_") else { return }
        let sid = String(raw.dropFirst(6))
        guard var item = SubscriptionStore.loadAll().first(where: { $0.id == sid }) else { return }
        item.enabled = (sender.state == .on)
        SubscriptionStore.update(item)
    }

    @objc private func cancelEditSubscriptionClicked(_ sender: Any?) {
        editingSubID = nil
        renderSelectedTab()
    }

    @objc private func deleteSubscriptionClicked(_ sender: NSButton) {
        guard let sid = sender.identifier?.rawValue else { return }
        SubscriptionStore.delete(id: sid)
        editingSubID = nil
        renderSelectedTab()
    }

    @objc private func saveEditSubscriptionClicked(_ sender: NSButton) {
        guard let sid = sender.identifier?.rawValue,
              var item = SubscriptionStore.loadAll().first(where: { $0.id == sid }) else { return }
        let nameVal = edSubNameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let acctVal = edSubAcctField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payVal = edSubPayField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let priceVal = edSubPriceField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dayVal = Int(edSubDayField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? item.billingDay
        let regRaw = (edSubRegionPopup?.selectedItem?.representedObject as? String) ?? item.regionCode
        let reg = SubscriptionRegion(rawValue: regRaw) ?? .us

        if !nameVal.isEmpty { item.customName = nameVal }
        if !acctVal.isEmpty { item.accountEmail = acctVal }
        if !payVal.isEmpty { item.paymentMethod = payVal }
        if !priceVal.isEmpty { item.priceText = priceVal }
        item.regionCode = reg.rawValue
        item.billingTimeZoneID = reg.defaultTimeZoneID
        item.billingDay = max(1, min(31, dayVal))

        SubscriptionStore.update(item)
        editingSubID = nil
        renderSelectedTab()
    }

    // MARK: - AI 额度池管理 Actions

    @objc private func autoDiscoverAIClicked(_ sender: Any?) {
        discoveredClaudeServices = AIQuotaStore.discoverClaudeKeychainServices()
        _ = AIQuotaStore.mergeDiscoveredAccounts()
        renderSelectedTab()
    }

    @objc private func refreshAllAIClicked(_ sender: Any?) {
        AIQuotaEngine.shared.refreshAll(interactive: true) { [weak self] in
            self?.renderSelectedTab()
        }
    }

    @objc private func addAIAccountClicked(_ sender: Any?) {
        let nid = "ai_\(UUID().uuidString.prefix(8))"
        let count = AIQuotaStore.loadAccounts().count + 1
        let item = AIQuotaAccount(
            id: nid,
            provider: .claude,
            customName: LocalizationService.pick("Claude 账号 #\(count)", "Claude #\(count)"),
            configPath: "",
            keychainService: "",
            enabled: true
        )
        AIQuotaStore.add(item)
        editingAIID = nid
        editingSubID = nil
        renderSelectedTab()
    }

    @objc private func toggleEditAIClicked(_ sender: NSButton) {
        guard let aid = sender.identifier?.rawValue else { return }
        editingAIID = (editingAIID == aid) ? nil : aid
        renderSelectedTab()
    }

    @objc private func aiAccountEnableToggled(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("aien_") else { return }
        let aid = String(raw.dropFirst(5))
        guard var acc = AIQuotaStore.loadAccounts().first(where: { $0.id == aid }) else { return }
        acc.enabled = (sender.state == .on)
        AIQuotaStore.update(acc)
    }

    @objc private func aiProviderPopupChanged(_ sender: NSPopUpButton) {
        let raw = (sender.selectedItem?.representedObject as? String) ?? "claude"
        let provider = AIQuotaProvider(rawValue: raw) ?? .claude
        edAIKeychainPopup?.isEnabled = (provider == .claude)
    }

    @objc private func refreshSingleAIClicked(_ sender: NSButton) {
        guard let aid = sender.identifier?.rawValue else { return }
        AIQuotaEngine.shared.refreshAccount(id: aid, interactive: true) { [weak self] _ in
            self?.renderSelectedTab()
        }
    }

    @objc private func deleteAIClicked(_ sender: NSButton) {
        guard let aid = sender.identifier?.rawValue else { return }
        AIQuotaStore.delete(id: aid)
        editingAIID = nil
        renderSelectedTab()
    }

    @objc private func cancelEditAIClicked(_ sender: Any?) {
        editingAIID = nil
        renderSelectedTab()
    }

    @objc private func saveEditAIClicked(_ sender: NSButton) {
        guard let aid = sender.identifier?.rawValue,
              var acc = AIQuotaStore.loadAccounts().first(where: { $0.id == aid }) else { return }
        let nameVal = edAINameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pathVal = edAIConfigPathField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provRaw = (edAIProviderPopup?.selectedItem?.representedObject as? String) ?? acc.provider.rawValue
        let provider = AIQuotaProvider(rawValue: provRaw) ?? acc.provider
        let kcVal = (edAIKeychainPopup?.selectedItem?.representedObject as? String) ?? ""

        if !nameVal.isEmpty { acc.customName = nameVal }
        acc.provider = provider
        acc.configPath = pathVal
        acc.keychainService = (provider == .claude) ? kcVal : ""

        AIQuotaStore.update(acc)
        editingAIID = nil
        renderSelectedTab()
    }

    @objc private func openGitHubRepo() {
        if let url = URL(string: "https://github.com/GangdanLee/Itsycal-DualTZ") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openReleases() {
        if let url = URL(string: "https://github.com/GangdanLee/Itsycal-DualTZ/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openUpstreamRepo() {
        if let url = URL(string: "https://github.com/sfsam/Itsycal") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - NSTextFieldDelegate (无闪烁实时输入)

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }

        if id == "primaryAlias" {
            UserDefaults.standard.set(field.stringValue, forKey: kDualTZPrimaryCityAlias)
            let pName = WorldClockStore.primaryDisplayName
            offsetRefSegmented?.setLabel(LocalizationService.pick("相对\(pName)", "vs \(pName)"), forSegment: 0)
        } else if id == "advMenuTemplate" {
            UserDefaults.standard.set(true, forKey: kDualTZMenuUseAdvanced)
            UserDefaults.standard.set(field.stringValue, forKey: kDualTZMenuBarFormat)
            refreshMenubarPreviewWidgets()
        } else if id.hasPrefix("alias_") {
            let cid = String(id.dropFirst(6))
            WorldClockStore.setSecondaryCity(id: cid, alias: field.stringValue)
        } else if id == "citySearch" {
            citySearchQuery = field.stringValue
            if let card = cityRowsCard {
                card.clearRowsKeepingFirstRow()
                populateCityRows(into: card, skipFirstSearchRow: true)
            }
        }
    }

    // MARK: - 菜单栏预览定时刷新 & NSWindowDelegate

    private func startPreviewTimer() {
        guard previewTimer == nil else { return }
        let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.window?.isVisible == true,
                  self.selectedTabIndex == TabID.general.rawValue else { return }
            self.refreshMenubarPreviewWidgets()
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func stopPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        startPreviewTimer()
        if selectedTabIndex == TabID.general.rawValue {
            refreshMenubarPreviewWidgets()
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopPreviewTimer()
    }
}
