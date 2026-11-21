//
//  DualTZBridge.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class DualTZBridge: NSObject {
    private static let upstreamBundleID = "com.mowglii.ItsycalApp"
    private static let safeUpstreamKeys = [
        kWeekStartDOW, kHighlightedDOWs, kShowWeeks, kSizePreference,
        kThemePreference, kMenuBarIconType, kShowMonthInIcon,
        kShowDayOfWeekInIcon, kHideIcon, kShowEventDays, kShowLocation,
        kShowEventDots, kUseColoredDots, kDoNotDrawOutlineAroundCurrentMonth,
        kWindowPosition, "SelectedCalendars"
    ]

    static func registerDefaultPreferences() {
        UserDefaults.standard.register(defaults: [
            kDualTZAppLanguage: 0,
            kDualTZMenuBarEnabled: true,
            kDualTZMenuBarFormat: "{CITY} {PRIMARY:MM月dd日} {PRIMARY:EEE} {PRIMARY:HH:mm}",
            kDualTZIconFollowsBeijing: true,
            kDualTZShowHeroHeader: true,
            kDualTZShowDualToday: true,
            kDualTZShowLunarSolarTerms: true,
            kDualTZShowChinaHolidays: true,
            kDualTZShowUSHolidays: true,
            kDualTZShowMarketingNodes: true,
            kDualTZShowAgendaDualTZ: true,
            kDualTZShowAgendaHolidays: true,
            kDualTZAllowBJEventCreate: true,
            kDualTZEnableTimeScrubber: false,
            kDualTZTimeScrubberExpanded: false,
            kDualTZShowThirdRefTZ: false,
            kDualTZShowDSTWarning: true,
            kDualTZShowUpcomingCountdown: true,
            kDualTZDismissedDSTDate: "",
            kDualTZHasImportedUpstreamPrefs: false,
            kDualTZHasMigratedAgendaPreview: false,
            kDualTZWindowGlassStyle: 0,
            kDualTZPrimaryTimeZoneID: "Asia/Shanghai",
            kDualTZPrimaryCityAlias: "",
            kDualTZWorldClockOffsetRef: 0,
            kDualTZWorldClockCollapsed: false,
            kDualTZWarnLateNight: true,
            kDualTZMenuUseAdvanced: false,
            kDualTZShowSubscriptionBar: true,
            kDualTZSubscriptionBarExpanded: false
        ])
    }

    static func localizedString(forKey key: String, defaultValue: String?) -> String {
        return LocalizationService.tr(key, default: defaultValue)
    }

    static func isChineseLanguage() -> Bool {
        return LocalizationService.isChinese
    }

    static func effectiveLocale() -> Locale {
        return LocalizationService.effectiveLocale
    }

    static func effectivePickerLocale() -> Locale {
        return LocalizationService.effectivePickerLocale
    }

    static func languageDidChangeNotificationName() -> NSNotification.Name {
        return .dualTZLanguageDidChange
    }

    static func importUpstreamPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: kDualTZHasImportedUpstreamPrefs) {
            if let upstream = defaults.persistentDomain(forName: upstreamBundleID) {
                for key in safeUpstreamKeys {
                    if let val = upstream[key] {
                        defaults.set(val, forKey: key)
                    }
                }
            }
            defaults.set(true, forKey: kDualTZHasImportedUpstreamPrefs)
        }
        // 将已从原版导入的单日预览一次性升级为 4 天，便于跨日连看节假日与大促节点
        if !defaults.bool(forKey: kDualTZHasMigratedAgendaPreview) {
            if defaults.integer(forKey: kShowEventDays) == 1 {
                defaults.set(4, forKey: kShowEventDays)
            }
            defaults.set(true, forKey: kDualTZHasMigratedAgendaPreview)
        }
    }

    static func beijingTodayMoDate() -> MoDate {
        return TimeZoneService.beijingTodayMoDate()
    }

    static func beijingCalendar() -> NSCalendar {
        let cal = NSCalendar(calendarIdentifier: .gregorian)!
        cal.timeZone = TimeZoneService.beijingTZ
        return cal
    }

    static func formatMenubarClock(_ template: String, at date: Date) -> String {
        return DualClockFormatter.string(from: date, template: template)
    }

    static func templateUsesTime(_ template: String) -> Bool {
        return DualClockFormatter.usesTime(template)
    }

    static func templateUsesSeconds(_ template: String) -> Bool {
        return DualClockFormatter.usesSeconds(template)
    }

    static func makeHeroHeaderView() -> BeijingHeroHeaderView {
        return BeijingHeroHeaderView(frame: .zero)
    }

    static func makePrefsViewController() -> NSViewController {
        let vc = DualTZPrefsVC()
        vc.title = LocalizationService.tr("dualtz.tab.title")
        return vc
    }

    static func makeSettingsWindowController(eventCenter: EventCenter) -> NSWindowController {
        return DualTZSettingsWindowController(eventCenter: eventCenter)
    }

    static func makeSubscriptionBarView() -> SubscriptionBarView {
        return SubscriptionBarView(frame: .zero)
    }

    static func hasSubscriptionDue(onDate date: MoDate) -> Bool {
        return SubscriptionStore.hasSubscriptionDue(on: date)
    }

    static func syncMenuTemplateFromTokens() {
        WorldClockStore.syncMenuTemplateFromTokensIfNeeded()
    }

    static func attributedAgendaDuration(
        beijingText: String,
        startDate: Date?,
        endDate: Date?,
        isStartOnly: Bool,
        isEndOnly: Bool,
        font: NSFont,
        beijingColor: NSColor,
        secondaryColor: NSColor
    ) -> NSAttributedString {
        return TimeZoneService.attributedAgendaDuration(
            beijingText: beijingText,
            startDate: startDate,
            endDate: endDate,
            isStartOnly: isStartOnly,
            isEndOnly: isEndOnly,
            font: font,
            beijingColor: beijingColor,
            secondaryColor: secondaryColor
        )
    }

    static func attributedPopoverDuration(
        beijingDuration: String,
        startDate: Date,
        endDate: Date?,
        font: NSFont,
        beijingColor: NSColor,
        localColor: NSColor
    ) -> NSAttributedString {
        return TimeZoneService.attributedPopoverDuration(
            beijingDuration: beijingDuration,
            startDate: startDate,
            endDate: endDate,
            font: font,
            beijingColor: beijingColor,
            localColor: localColor
        )
    }

    static func cellAnnotation(forDate date: MoDate) -> DualTZCellAnnotation {
        return HolidayLunarService.annotation(for: date)
    }

    static func tooltipHolidaySummary(forDate date: MoDate) -> String? {
        return HolidayLunarService.tooltipSummary(for: date)
    }

    static func hasSpecialDayDetail(forDate date: MoDate) -> Bool {
        return HolidayLunarService.hasSpecialDayDetail(for: date)
    }

    static func virtualAgendaItems(forDate date: MoDate) -> [DualTZVirtualAgendaItem] {
        return AgendaHolidayBuilder.items(for: date)
    }

    static func agendaDateLeftTitle(for date: Date, calendar: NSCalendar, includeLunar: Bool) -> String {
        return AgendaHolidayBuilder.dateHeaderTitle(for: date, calendar: calendar as Calendar, includeLunar: includeLunar)
    }

    static func agendaDateRightTag(for date: Date, calendar: NSCalendar) -> String {
        return AgendaHolidayBuilder.dateHeaderRightTag(for: date, calendar: calendar as Calendar)
    }

    static func reanchorDate(_ date: Date, fromTimeZone: NSTimeZone, toTimeZone: NSTimeZone) -> Date {
        return TimeZoneService.reanchorDate(date, fromTimeZone: fromTimeZone as TimeZone, toTimeZone: toTimeZone as TimeZone)
    }

    static func eventTimeZoneEchoResult(startDate: Date, endDate: Date, isAllDay: Bool, isBeijingInput: Bool) -> DualTZEchoResult {
        return DualTZInviteFormatter.echoResult(
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            isBeijingInput: isBeijingInput
        )
    }

    static func dualTZInviteText(
        title: String,
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool,
        location: String?,
        meetingURL: URL?
    ) -> String {
        return DualTZInviteFormatter.inviteText(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            meetingURL: meetingURL
        )
    }

    static func chinaHolidayStatusSummary() -> String {
        return ChinaHolidayStore.shared.statusSummary()
    }

    static func makeDSTWarningBannerView() -> DSTWarningBannerView {
        return DSTWarningBannerView(frame: .zero)
    }

    static func makeTimeScrubberView() -> TimeScrubberView {
        return TimeScrubberView(frame: .zero)
    }

    static func holidaysDidChangeNotificationName() -> NSNotification.Name {
        return .dualTZHolidaysDidChange
    }
}
