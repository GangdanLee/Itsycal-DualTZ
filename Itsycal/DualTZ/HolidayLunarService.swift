//
//  HolidayLunarService.swift
//  Itsycal DualTZ
//

import Foundation

@objcMembers
final class DualTZCellAnnotation: NSObject {
    let subtitleText: String
    let subtitleStyle: Int // 0=农历灰, 1=节气蓝, 2=中国节日红, 3=美假/跨境琥珀
    let badgeText: String    // "", "休", "班", "US", "Off", "Wk"
    let badgeStyle: Int    // 0=US, 1=休, 2=班

    init(subtitleText: String, subtitleStyle: Int, badgeText: String, badgeStyle: Int) {
        self.subtitleText = subtitleText
        self.subtitleStyle = subtitleStyle
        self.badgeText = badgeText
        self.badgeStyle = badgeStyle
    }
}

enum HolidayLunarService {
    private static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]
    private static let solarTermShortEn = [
        "LtCold", "MjCold", "SprBeg", "RainWtr", "WkInsct", "SprEqx",
        "Qingmg", "GrnRain", "SumBeg", "GrnFull", "GrnEar", "SumSol",
        "LtHeat", "MjHeat", "AutBeg", "EndHeat", "WhtDew", "AutEqx",
        "CldDew", "FrstDsc", "WinBeg", "LtSnow", "MjSnow", "WinSol"
    ]
    private static let solarTermC21: [Double] = [
        5.4055, 20.12, 3.87, 18.73, 5.63, 20.646,
        4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
        7.108, 22.83, 7.5, 23.13, 7.646, 23.042,
        8.318, 23.438, 7.438, 22.36, 7.18, 21.94
    ]
    private static let lunarMonths = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]
    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    static func annotation(for moDate: MoDate) -> DualTZCellAnnotation {
        let d = UserDefaults.standard
        let showLunar = d.bool(forKey: kDualTZShowLunarSolarTerms)
        let showCN = d.bool(forKey: kDualTZShowChinaHolidays)
        let y = moDate.year, m = moDate.month + 1, day = moDate.day

        let cnEntry = showCN ? ChinaHolidayStore.shared.entry(forDateKey: dateKey(y, m, day)) : nil
        let usInfo = USCrossBorderService.primaryCellNode(year: y, month: m, day: day)
        let rawTerm = solarTermName(year: y, month: m, day: day)
        let cnFest = showCN ? chineseFestivalTitle(year: y, month: m, day: day, solarTerm: rawTerm) : nil
        let lunarShort = showLunar ? shortLunarDay(year: y, month: m, day: day) : nil
        let termLabel = showLunar ? localizedSolarTerm(year: y, month: m, day: day) : nil

        let (subText, subStyle) = resolveSubtitle(cnFestival: cnFest, usTitle: usInfo?.shortTitle, solarTerm: termLabel, lunarDay: lunarShort)
        let (badgeText, badgeStyle) = resolveBadge(cnEntry: cnEntry, isUSFederal: usInfo?.isFederal ?? false)
        return DualTZCellAnnotation(subtitleText: subText, subtitleStyle: subStyle, badgeText: badgeText, badgeStyle: badgeStyle)
    }

    static func tooltipSummary(for moDate: MoDate) -> String? {
        let d = UserDefaults.standard
        let showLunar = d.bool(forKey: kDualTZShowLunarSolarTerms)
        let showCN = d.bool(forKey: kDualTZShowChinaHolidays)
        let y = moDate.year, m = moDate.month + 1, day = moDate.day
        var parts: [String] = []

        if showLunar, let date = noonBeijingDate(y, m, day) {
            parts.append(TimeZoneService.chineseLunarSummary(for: date))
            if let term = localizedSolarTerm(year: y, month: m, day: day) { parts.append(term) }
        }
        if showCN, let entry = ChinaHolidayStore.shared.entry(forDateKey: dateKey(y, m, day)) {
            let name = ChinaHolidayStore.displayName(entry.name)
            parts.append(entry.isOffDay
                ? LocalizationService.pick("\(name)休假（休）", "\(name) (CN Off)")
                : LocalizationService.pick("\(name)补班（班）", "\(name) (CN Workday)"))
        }
        for us in USCrossBorderService.allNodes(year: y, month: m, day: day) {
            parts.append(us.isFederal ? LocalizationService.pick("\(us.fullTitle)（美国休假）", "\(us.fullTitle) (US Off)") : us.fullTitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func hasSpecialDayDetail(for moDate: MoDate) -> Bool {
        let d = UserDefaults.standard
        let y = moDate.year, m = moDate.month + 1, day = moDate.day
        let rawTerm = solarTermName(year: y, month: m, day: day)
        if d.bool(forKey: kDualTZShowLunarSolarTerms) && rawTerm != nil { return true }
        if !USCrossBorderService.allNodes(year: y, month: m, day: day).isEmpty { return true }
        if d.bool(forKey: kDualTZShowChinaHolidays) {
            if ChinaHolidayStore.shared.entry(forDateKey: dateKey(y, m, day)) != nil { return true }
            if chineseFestivalTitle(year: y, month: m, day: day, solarTerm: rawTerm) != nil { return true }
        }
        return false
    }

    static func localizedSolarTerm(year: Int, month: Int, day: Int) -> String? {
        guard (2001...2099).contains(year), (1...12).contains(month) else { return nil }
        let startIndex = (month - 1) * 2
        for offset in 0...1 {
            let idx = startIndex + offset
            if solarTermDay(year: year, index: idx) == day {
                return LocalizationService.isChinese ? solarTermNames[idx] : solarTermShortEn[idx]
            }
        }
        return nil
    }

    static func solarTermName(year: Int, month: Int, day: Int) -> String? {
        guard (2001...2099).contains(year), (1...12).contains(month) else { return nil }
        let startIndex = (month - 1) * 2
        for offset in 0...1 {
            let idx = startIndex + offset
            if solarTermDay(year: year, index: idx) == day { return solarTermNames[idx] }
        }
        return nil
    }

    static func chineseFestivalTitle(year: Int, month: Int, day: Int, solarTerm: String?) -> String? {
        let zh = LocalizationService.isChinese
        if month == 1 && day == 1 { return zh ? "元旦" : "NewYear" }
        if month == 5 && day == 1 { return zh ? "劳动节" : "Labor" }
        if month == 10 && day == 1 { return zh ? "国庆节" : "NatDay" }
        if solarTerm == "清明" { return zh ? "清明" : "Qingmg" }

        guard let date = noonBeijingDate(year, month, day) else { return nil }
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = TimeZoneService.beijingTZ
        let lc = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        if lc.isLeapMonth != true {
            if lc.month == 1 && lc.day == 1 { return zh ? "春节" : "SprFest" }
            if lc.month == 1 && lc.day == 15 { return zh ? "元宵" : "Lantern" }
            if lc.month == 5 && lc.day == 5 { return zh ? "端午" : "DragonB" }
            if lc.month == 7 && lc.day == 7 { return zh ? "七夕" : "Qixi" }
            if lc.month == 8 && lc.day == 15 { return zh ? "中秋" : "MidAut" }
            if lc.month == 9 && lc.day == 9 { return zh ? "重阳" : "Dbl9th" }
        }
        let tc = cal.dateComponents([.month, .day, .isLeapMonth], from: date.addingTimeInterval(86400))
        if tc.isLeapMonth != true && tc.month == 1 && tc.day == 1 { return zh ? "除夕" : "CNY Eve" }
        return nil
    }

    static func dateKey(_ y: Int, _ m: Int, _ d: Int) -> String {
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func noonBeijingDate(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        let cal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    private static func resolveSubtitle(cnFestival: String?, usTitle: String?, solarTerm: String?, lunarDay: String?) -> (String, Int) {
        if let cnFestival = cnFestival { return (cnFestival, 2) }
        if let usTitle = usTitle { return (usTitle, 3) }
        if let solarTerm = solarTerm { return (solarTerm, 1) }
        if let lunarDay = lunarDay { return (lunarDay, 0) }
        return ("", 0)
    }

    private static func resolveBadge(cnEntry: ChinaHolidayEntry?, isUSFederal: Bool) -> (String, Int) {
        if let cnEntry = cnEntry {
            if cnEntry.isOffDay { return (LocalizationService.pick("休", "Off"), 1) }
            return (LocalizationService.pick("班", "Wk"), 2)
        }
        return isUSFederal ? ("US", 0) : ("", 0)
    }

    private static func solarTermDay(year: Int, index: Int) -> Int {
        let y = year % 100
        let leap = (index <= 3) ? ((y - 1) / 4) : (y / 4)
        var day = Int(Double(y) * 0.2422 + solarTermC21[index]) - leap
        let adjustments: [Int: Int] = [
            2019 * 100 + 0: -1, 2082 * 100 + 1: 1, 2084 * 100 + 5: 1,
            2008 * 100 + 9: 1, 2002 * 100 + 14: 1, 2026 * 100 + 3: -1, 2021 * 100 + 23: -1
        ]
        day += adjustments[year * 100 + index] ?? 0
        return day
    }

    private static func shortLunarDay(year: Int, month: Int, day: Int) -> String? {
        guard let date = noonBeijingDate(year, month, day) else { return nil }
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = TimeZoneService.beijingTZ
        let lc = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let lm = lc.month, let ld = lc.day, (1...12).contains(lm), (1...30).contains(ld) else { return nil }
        if !LocalizationService.isChinese {
            let prefix = (lc.isLeapMonth == true) ? "R" : ""
            return ld == 1 ? "L\(prefix)\(lm)/1" : "\(lm)/\(ld)"
        }
        if ld == 1 {
            let prefix = (lc.isLeapMonth == true) ? "闰" : ""
            return "\(prefix)\(lunarMonths[lm - 1])"
        }
        return lunarDays[ld - 1]
    }
}
