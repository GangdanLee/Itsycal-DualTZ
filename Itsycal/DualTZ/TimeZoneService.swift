//
//  TimeZoneService.swift
//  Itsycal DualTZ
//

import Cocoa

struct HeroTimeSnapshot {
    let beijingTitle: String
    let beijingTime: String
    let beijingDateWeekday: String
    let beijingDayNightIcon: String
    let beijingLunarText: String
    let localTitle: String
    let localTime: String
    let localDateWeekday: String
    let thirdRefText: String
}

enum TimeZoneService {
    static var beijingTZ: TimeZone { WorldClockStore.primaryTimeZone }
    static let standardBeijingTZ = TimeZone(identifier: "Asia/Shanghai")!
    static let losAngelesTZ = TimeZone(identifier: "America/Los_Angeles")!
    static let newYorkTZ = TimeZone(identifier: "America/New_York")!
    static let utcTZ = TimeZone(secondsFromGMT: 0)!

    private static let weekdayZh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let weekdayEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthEn = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let lunarMonths = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]
    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    static func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    static func beijingTodayMoDate(at date: Date = Date()) -> MoDate {
        return MakeDateWithNSDate(date, gregorianCalendar(in: beijingTZ))
    }

    static func dayDeltaFromLocalToBeijing(at date: Date, localTZ: TimeZone = .autoupdatingCurrent) -> Int {
        let localDay = gregorianCalendar(in: localTZ).dateComponents([.year, .month, .day], from: date)
        let bjDay = gregorianCalendar(in: beijingTZ).dateComponents([.year, .month, .day], from: date)
        guard let d1 = gregorianCalendar(in: utcTZ).date(from: localDay),
              let d2 = gregorianCalendar(in: utcTZ).date(from: bjDay) else { return 0 }
        return Int(round(d2.timeIntervalSince(d1) / 86400.0))
    }

    static func weekdayText(for date: Date, in timeZone: TimeZone) -> String {
        let wd = gregorianCalendar(in: timeZone).component(.weekday, from: date)
        let idx = max(0, min(6, wd - 1))
        return LocalizationService.isChinese ? weekdayZh[idx] : weekdayEn[idx]
    }

    static func weekdayChinese(for date: Date, in timeZone: TimeZone) -> String {
        let wd = gregorianCalendar(in: timeZone).component(.weekday, from: date)
        return weekdayZh[max(0, min(6, wd - 1))]
    }

    static func formatDate(_ date: Date, pattern: String, in timeZone: TimeZone, localeID: String? = nil) -> String {
        let fmt = DateFormatter()
        fmt.calendar = gregorianCalendar(in: timeZone)
        fmt.timeZone = timeZone
        fmt.locale = localeID.map { Locale(identifier: $0) } ?? LocalizationService.effectiveLocale
        fmt.dateFormat = pattern
        return fmt.string(from: date)
    }

    static func chineseLunarSummary(for date: Date, in timeZone: TimeZone = beijingTZ) -> String {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = timeZone
        let comp = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let m = comp.month, let d = comp.day, m >= 1, m <= 12, d >= 1, d <= 30 else { return "" }
        if LocalizationService.isChinese {
            let leapPrefix = (comp.isLeapMonth == true) ? "闰" : ""
            return "农历\(leapPrefix)\(lunarMonths[m - 1])\(lunarDays[d - 1])"
        }
        let leap = (comp.isLeapMonth == true) ? "Leap " : ""
        return "Lunar \(leap)\(m)/\(d)"
    }

    static func localTimeZoneLabel(at date: Date, localTZ: TimeZone = .autoupdatingCurrent) -> String {
        if localTZ.identifier == losAngelesTZ.identifier {
            let dst = localTZ.isDaylightSavingTime(for: date) ? "PDT" : "PST"
            return LocalizationService.pick("美西 \(dst)", "LA \(dst)")
        }
        return localTZ.abbreviation(for: date) ?? LocalizationService.pick("本地", "Local")
    }

    static func heroSnapshot(at date: Date = Date(), localTZ: TimeZone = .autoupdatingCurrent, compactDates: Bool = false) -> HeroTimeSnapshot {
        let bjComp = gregorianCalendar(in: beijingTZ).dateComponents([.month, .day, .hour], from: date)
        let localComp = gregorianCalendar(in: localTZ).dateComponents([.month, .day], from: date)
        let bjHour = bjComp.hour ?? 0
        let bjWD = weekdayText(for: date, in: beijingTZ)
        let localWD = weekdayText(for: date, in: localTZ)

        return HeroTimeSnapshot(
            beijingTitle: WorldClockStore.primaryDisplayName,
            beijingTime: formatDate(date, pattern: "HH:mm", in: beijingTZ),
            beijingDateWeekday: formatDateWeekday(bjComp, weekday: bjWD, compact: compactDates),
            beijingDayNightIcon: (bjHour >= 7 && bjHour < 20) ? "☀️" : "🌙",
            beijingLunarText: chineseLunarSummary(for: date, in: beijingTZ),
            localTitle: localTimeZoneLabel(at: date, localTZ: localTZ),
            localTime: formatDate(date, pattern: "HH:mm", in: localTZ),
            localDateWeekday: formatDateWeekday(localComp, weekday: localWD, compact: compactDates),
            thirdRefText: "NY \(formatDate(date, pattern: "HH:mm", in: newYorkTZ)) · UTC \(formatDate(date, pattern: "HH:mm", in: utcTZ))"
        )
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
        let anchor = isEndOnly ? endDate : startDate
        guard let anchorDate = anchor else {
            return NSAttributedString(string: beijingText, attributes: [.font: font, .foregroundColor: beijingColor])
        }
        let localTZ = TimeZone.autoupdatingCurrent
        let bjDay = gregorianCalendar(in: beijingTZ).dateComponents([.year, .month, .day], from: anchorDate)
        let localCal = gregorianCalendar(in: localTZ)
        let localDay = localCal.dateComponents([.year, .month, .day], from: anchorDate)
        let tag = DualTZInviteFormatter.shortLocalTag(at: anchorDate, localTZ: localTZ)
        let datePart = (bjDay == localDay) ? "" : "\(weekdayText(for: anchorDate, in: localTZ))(\(localDay.month ?? 1)/\(localDay.day ?? 1)) "

        let timePart: String
        if isStartOnly || isEndOnly || endDate == nil || startDate == endDate {
            timePart = formatDate(anchorDate, pattern: "HH:mm", in: localTZ)
        } else if let s = startDate, let e = endDate {
            timePart = "\(formatDate(s, pattern: "HH:mm", in: localTZ))–\(formatDate(e, pattern: "HH:mm", in: localTZ))"
        } else {
            timePart = ""
        }

        let result = NSMutableAttributedString(string: beijingText, attributes: [.font: font, .foregroundColor: beijingColor])
        guard !timePart.isEmpty else { return result }
        let appendText = " · \(tag) \(datePart)\(timePart)"
        result.append(NSAttributedString(string: appendText, attributes: [.font: font, .foregroundColor: secondaryColor]))
        return result
    }

    static func attributedPopoverDuration(
        beijingDuration: String,
        startDate: Date,
        endDate: Date?,
        font: NSFont,
        beijingColor: NSColor,
        localColor: NSColor
    ) -> NSAttributedString {
        let localTZ = TimeZone.autoupdatingCurrent
        let localCal = gregorianCalendar(in: localTZ)
        let lc = localCal.dateComponents([.month, .day], from: startDate)
        let wd = weekdayText(for: startDate, in: localTZ)
        let startTime = formatDate(startDate, pattern: "HH:mm", in: localTZ)
        let timeRange = (endDate != nil && endDate! > startDate)
            ? "\(startTime)–\(formatDate(endDate!, pattern: "HH:mm", in: localTZ))"
            : startTime
        let localDateStr = LocalizationService.isChinese
            ? "\(lc.month ?? 1)月\(lc.day ?? 1)日(\(wd))"
            : "\(monthEn[max(0, min(11, (lc.month ?? 1) - 1))]) \(lc.day ?? 1) (\(wd))"
        let laLabel = localTimeZoneLabel(at: startDate, localTZ: localTZ)

        let bjPrefix = LocalizationService.pick("北京时间  ", "Beijing  ")
        let result = NSMutableAttributedString(string: "\(bjPrefix)\(beijingDuration)", attributes: [.font: font, .foregroundColor: beijingColor])
        let smallFont = NSFont.systemFont(ofSize: max(10, font.pointSize - 1))
        result.append(NSAttributedString(string: "\n\(laLabel)  \(localDateStr) \(timeRange)", attributes: [.font: smallFont, .foregroundColor: localColor]))
        return result
    }

    static func reanchorDate(_ date: Date, fromTimeZone: TimeZone, toTimeZone: TimeZone) -> Date {
        let comps = gregorianCalendar(in: fromTimeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return gregorianCalendar(in: toTimeZone).date(from: comps) ?? date
    }

    private static func formatDateWeekday(_ comp: DateComponents, weekday: String, compact: Bool) -> String {
        let m = comp.month ?? 1, d = comp.day ?? 1
        if compact { return "\(m)/\(d) \(weekday)" }
        if LocalizationService.isChinese { return "\(m)月\(d)日 \(weekday)" }
        return "\(monthEn[max(0, min(11, m - 1))]) \(d) \(weekday)"
    }
}
