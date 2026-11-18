//
//  AgendaHolidayBuilder.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class DualTZVirtualAgendaItem: NSObject {
    let title: String
    let tagText: String
    let subtitle: String
    let dotColor: NSColor

    init(title: String, tagText: String, subtitle: String, dotColor: NSColor) {
        self.title = title
        self.tagText = tagText
        self.subtitle = subtitle
        self.dotColor = dotColor
    }
}

enum AgendaHolidayBuilder {
    private static let weekdayZh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let weekdayEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthEn = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func items(for moDate: MoDate) -> [DualTZVirtualAgendaItem] {
        let d = UserDefaults.standard
        guard d.bool(forKey: kDualTZShowAgendaHolidays) else { return [] }

        let showCN = d.bool(forKey: kDualTZShowChinaHolidays)
        let showLunar = d.bool(forKey: kDualTZShowLunarSolarTerms)

        let y = moDate.year, m = moDate.month + 1, day = moDate.day
        let lunarSummary = lunarText(year: y, month: m, day: day)
        let rawTerm = HolidayLunarService.solarTermName(year: y, month: m, day: day)
        let locTerm = HolidayLunarService.localizedSolarTerm(year: y, month: m, day: day)

        var list: [DualTZVirtualAgendaItem] = []
        if showCN {
            appendChinaItem(year: y, month: m, day: day, solarTerm: rawTerm, lunarSummary: lunarSummary, into: &list)
        }
        appendUSItems(year: y, month: m, day: day, lunarSummary: lunarSummary, into: &list)
        if showLunar, let term = locTerm, rawTerm != "清明" || !showCN {
            let title = LocalizationService.pick("二十四节气 · \(term)", "Solar Term · \(term)")
            let tag = LocalizationService.pick("节气", "Term")
            let subPrefix = LocalizationService.pick("二十四节气", "24 Solar Terms")
            let sub = lunarSummary.isEmpty ? subPrefix : "\(subPrefix) · \(lunarSummary)"
            list.append(DualTZVirtualAgendaItem(title: title, tagText: tag, subtitle: sub, dotColor: .systemBlue))
        }
        return list
    }

    static func dateHeaderTitle(for date: Date, calendar: Calendar, includeLunar: Bool) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        let mon = comp.month ?? 1, day = comp.day ?? 1
        let gregorian = LocalizationService.isChinese
            ? "\(mon)月\(day)日"
            : "\(monthEn[max(0, min(11, mon - 1))]) \(day)"
        guard includeLunar, UserDefaults.standard.bool(forKey: kDualTZShowLunarSolarTerms) else {
            return gregorian
        }
        let mo = MakeDateWithNSDate(date, calendar)
        let fullLunar = lunarText(year: mo.year, month: mo.month + 1, day: mo.day)
        let shortLunar = fullLunar.replacingOccurrences(of: "农历", with: "")
        return shortLunar.isEmpty ? gregorian : "\(gregorian) · \(shortLunar)"
    }

    static func dateHeaderRightTag(for date: Date, calendar: Calendar) -> String {
        let mo = MakeDateWithNSDate(date, calendar)
        let bjToday = TimeZoneService.beijingTodayMoDate()
        let diff = CompareDates(mo, bjToday)
        if diff == 0 { return LocalizationService.pick("今天", "Today") }
        if diff == 1 { return LocalizationService.pick("明天", "Tomorrow") }
        let wd = calendar.component(.weekday, from: date)
        let idx = max(0, min(6, wd - 1))
        return LocalizationService.isChinese ? weekdayZh[idx] : weekdayEn[idx]
    }

    private static func lunarText(year: Int, month: Int, day: Int) -> String {
        guard let noon = HolidayLunarService.noonBeijingDate(year, month, day) else { return "" }
        return TimeZoneService.chineseLunarSummary(for: noon)
    }

    private static func appendChinaItem(
        year: Int,
        month: Int,
        day: Int,
        solarTerm: String?,
        lunarSummary: String,
        into list: inout [DualTZVirtualAgendaItem]
    ) {
        let key = HolidayLunarService.dateKey(year, month, day)
        if let entry = ChinaHolidayStore.shared.entry(forDateKey: key) {
            let name = ChinaHolidayStore.displayName(entry.name)
            if entry.isOffDay {
                let fest = HolidayLunarService.chineseFestivalTitle(year: year, month: month, day: day, solarTerm: solarTerm)
                let title: String
                if let fest = fest, !name.lowercased().contains(fest.lowercased()) && !entry.name.contains(fest) {
                    title = LocalizationService.pick("\(name)放假 · \(fest)", "\(name) Holiday · \(fest)")
                } else {
                    title = LocalizationService.pick("\(name)放假", "\(name) Holiday")
                }
                let tag = LocalizationService.pick("休", "Off")
                let desc = LocalizationService.pick("国务院法定节假日放假", "China Official Statutory Holiday")
                let sub = lunarSummary.isEmpty ? desc : "\(desc) · \(lunarSummary)"
                list.append(DualTZVirtualAgendaItem(title: title, tagText: tag, subtitle: sub, dotColor: .systemGreen))
            } else {
                let title = LocalizationService.pick("\(name)调休补班", "\(name) Makeup Workday")
                let tag = LocalizationService.pick("班", "Work")
                let desc = LocalizationService.pick("国内周末调休上班", "China Adjusted Makeup Workday")
                let sub = lunarSummary.isEmpty ? desc : "\(desc) · \(lunarSummary)"
                list.append(DualTZVirtualAgendaItem(title: title, tagText: tag, subtitle: sub, dotColor: .systemRed))
            }
            return
        }
        if let fest = HolidayLunarService.chineseFestivalTitle(year: year, month: month, day: day, solarTerm: solarTerm) {
            let tag = LocalizationService.pick("全天", "All-day")
            let desc = LocalizationService.pick("中国传统节日", "Chinese Traditional Festival")
            let sub = lunarSummary.isEmpty ? desc : "\(desc) · \(lunarSummary)"
            list.append(DualTZVirtualAgendaItem(title: fest, tagText: tag, subtitle: sub, dotColor: .systemRed))
        }
    }

    private static func appendUSItems(
        year: Int,
        month: Int,
        day: Int,
        lunarSummary: String,
        into list: inout [DualTZVirtualAgendaItem]
    ) {
        for us in USCrossBorderService.allNodes(year: year, month: month, day: day) {
            if us.isFederal {
                let titleZh = us.fullZh.contains("（") ? us.fullZh : "\(us.fullZh)（美国休假）"
                let title = LocalizationService.pick(titleZh, "\(us.fullEn) (US Off)")
                let tag = LocalizationService.pick("全天", "All-day")
                let desc = LocalizationService.pick("美国联邦法定假日", "US Federal Holiday")
                let sub = lunarSummary.isEmpty ? desc : "\(desc) · \(lunarSummary)"
                list.append(DualTZVirtualAgendaItem(title: title, tagText: tag, subtitle: sub, dotColor: .systemPurple))
            } else {
                let title = usTitleForAgenda(us)
                let tag = LocalizationService.pick(us.isMarketingOnly ? "节点" : "全天", us.isMarketingOnly ? "Node" : "Sale")
                let desc = LocalizationService.pick("北美/跨境运营营销节点", "Cross-Border E-Commerce / Retail Node")
                let sub = lunarSummary.isEmpty ? desc : "\(desc) · \(lunarSummary)"
                let color: NSColor = us.isMarketingOnly ? .systemTeal : .systemOrange
                list.append(DualTZVirtualAgendaItem(title: title, tagText: tag, subtitle: sub, dotColor: color))
            }
        }
    }

    private static func usTitleForAgenda(_ us: USNodeInfo) -> String {
        guard LocalizationService.isChinese else { return us.fullEn }
        if us.shortZh == "黑五" { return "Black Friday 黑色星期五 · 跨境大促" }
        if us.shortZh == "网一" { return "Cyber Monday 网络星期一 · 跨境大促" }
        return us.fullZh
    }
}
