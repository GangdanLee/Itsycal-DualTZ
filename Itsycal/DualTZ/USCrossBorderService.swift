//
//  USCrossBorderService.swift
//  Itsycal DualTZ
//

import Foundation

struct USNodeInfo {
    let shortZh: String
    let shortEn: String
    let fullZh: String
    let fullEn: String
    let isFederal: Bool
    let isMarketingOnly: Bool

    var shortTitle: String { LocalizationService.pick(shortZh, shortEn) }
    var fullTitle: String { LocalizationService.pick(fullZh, fullEn) }
}

enum USCrossBorderService {
    static func primaryCellNode(year: Int, month: Int, day: Int) -> USNodeInfo? {
        let d = UserDefaults.standard
        if d.bool(forKey: kDualTZShowUSHolidays), let fed = usFederalOrCoreSale(year: year, month: month, day: day) {
            return fed
        }
        if d.bool(forKey: kDualTZShowMarketingNodes) {
            return marketingNode(year: year, month: month, day: day)
        }
        return nil
    }

    static func allNodes(year: Int, month: Int, day: Int) -> [USNodeInfo] {
        let d = UserDefaults.standard
        var list: [USNodeInfo] = []
        if d.bool(forKey: kDualTZShowUSHolidays), let fed = usFederalOrCoreSale(year: year, month: month, day: day) {
            list.append(fed)
        }
        if d.bool(forKey: kDualTZShowMarketingNodes), let mkt = marketingNode(year: year, month: month, day: day) {
            list.append(mkt)
        }
        return list
    }

    static func usFederalOrCoreSale(year: Int, month: Int, day: Int) -> USNodeInfo? {
        let cal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        guard let date = HolidayLunarService.noonBeijingDate(year, month, day) else { return nil }
        let wd = cal.component(.weekday, from: date)

        if let fixed = checkObservedFixedUS(year: year, month: month, day: day, cal: cal) {
            return fixed
        }
        if month == 1 && wd == 2 && (15...21).contains(day) {
            return USNodeInfo(shortZh: "马丁金", shortEn: "MLK", fullZh: "马丁路德金日", fullEn: "MLK Jr. Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 2 && wd == 2 && (15...21).contains(day) {
            return USNodeInfo(shortZh: "总统日", shortEn: "PresDay", fullZh: "总统日", fullEn: "Presidents' Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 5 && wd == 2 && (25...31).contains(day) {
            return USNodeInfo(shortZh: "阵亡日", shortEn: "MemDay", fullZh: "阵亡将士纪念日", fullEn: "Memorial Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 9 && wd == 2 && (1...7).contains(day) {
            return USNodeInfo(shortZh: "劳工节", shortEn: "Labor", fullZh: "美国劳工节", fullEn: "US Labor Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 10 && wd == 2 && (8...14).contains(day) {
            return USNodeInfo(shortZh: "哥伦布", shortEn: "Colmbus", fullZh: "哥伦布日", fullEn: "Columbus Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 11 && wd == 5 && (22...28).contains(day) {
            return USNodeInfo(shortZh: "感恩节", shortEn: "Thksgvg", fullZh: "感恩节", fullEn: "Thanksgiving Day", isFederal: true, isMarketingOnly: false)
        }
        if month == 11 && wd == 6 && (23...29).contains(day) {
            return USNodeInfo(shortZh: "黑五", shortEn: "BlkFri", fullZh: "黑色星期五（跨境大促）", fullEn: "Black Friday Sale", isFederal: false, isMarketingOnly: false)
        }
        if isCyberMonday(month: month, day: day, weekday: wd, date: date, cal: cal) {
            return USNodeInfo(shortZh: "网一", shortEn: "CybMon", fullZh: "网络星期一（跨境大促）", fullEn: "Cyber Monday Sale", isFederal: false, isMarketingOnly: false)
        }
        return nil
    }

    static func marketingNode(year: Int, month: Int, day: Int) -> USNodeInfo? {
        if month == 2 && day == 14 {
            return USNodeInfo(shortZh: "情人节", shortEn: "ValDay", fullZh: "情人节 · 北美消费季", fullEn: "Valentine's Day · Retail Node", isFederal: false, isMarketingOnly: true)
        }
        if month == 6 && day == 18 {
            return USNodeInfo(shortZh: "618", shortEn: "618", fullZh: "618 年中大促 · 跨境运营节点", fullEn: "618 Mid-Year Sale · Operations", isFederal: false, isMarketingOnly: true)
        }
        if month == 10 && day == 31 {
            return USNodeInfo(shortZh: "万圣节", shortEn: "Hlwyn", fullZh: "万圣节 · 北美热销节点", fullEn: "Halloween · US Retail Peak", isFederal: false, isMarketingOnly: true)
        }
        if month == 11 && day == 11 {
            return USNodeInfo(shortZh: "双11", shortEn: "11.11", fullZh: "双11 全球购物节 · 大促节点", fullEn: "Double 11 Shopping Festival", isFederal: false, isMarketingOnly: true)
        }
        if month == 12 && day == 24 {
            return USNodeInfo(shortZh: "平安夜", shortEn: "XmasEv", fullZh: "平安夜 · 圣诞备货冲刺", fullEn: "Christmas Eve · Peak Shipping", isFederal: false, isMarketingOnly: true)
        }
        guard let date = HolidayLunarService.noonBeijingDate(year, month, day) else { return nil }
        let wd = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ).component(.weekday, from: date)
        if month == 5 && wd == 1 && (8...14).contains(day) {
            return USNodeInfo(shortZh: "母亲节", shortEn: "MomDay", fullZh: "母亲节 · 北美消费大促", fullEn: "Mother's Day · US Retail Node", isFederal: false, isMarketingOnly: true)
        }
        if month == 6 && wd == 1 && (15...21).contains(day) {
            return USNodeInfo(shortZh: "父亲节", shortEn: "DadDay", fullZh: "父亲节 · 北美消费大促", fullEn: "Father's Day · US Retail Node", isFederal: false, isMarketingOnly: true)
        }
        return nil
    }

    private static func isCyberMonday(month: Int, day: Int, weekday: Int, date: Date, cal: Calendar) -> Bool {
        guard (month == 11 && weekday == 2 && (27...30).contains(day)) || (month == 12 && weekday == 2 && day == 1) else {
            return false
        }
        let fourDaysAgo = cal.date(byAdding: .day, value: -4, to: date)!
        let ac = cal.dateComponents([.month, .day, .weekday], from: fourDaysAgo)
        return ac.month == 11 && ac.weekday == 5 && (22...28).contains(ac.day ?? 0)
    }

    private static func checkObservedFixedUS(year: Int, month: Int, day: Int, cal: Calendar) -> USNodeInfo? {
        let fixedHolidays: [(Int, Int, String, String, String, String)] = [
            (1, 1, "新年", "NewYr", "美国新年", "US New Year's Day"),
            (6, 19, "六月节", "Jntnth", "六月节（联邦休假）", "Juneteenth National Day"),
            (7, 4, "独立日", "Jul4", "美国独立日", "US Independence Day"),
            (11, 11, "退伍日", "VetDay", "退伍军人日", "Veterans Day"),
            (12, 25, "圣诞节", "Xmas", "圣诞节", "Christmas Day")
        ]
        for (fm, fd, sZh, sEn, fZh, fEn) in fixedHolidays {
            guard let actual = HolidayLunarService.noonBeijingDate(year, fm, fd) else { continue }
            let awd = cal.component(.weekday, from: actual)
            let observed: Date
            if awd == 7 { observed = cal.date(byAdding: .day, value: -1, to: actual)! }
            else if awd == 1 { observed = cal.date(byAdding: .day, value: 1, to: actual)! }
            else { observed = actual }
            let oc = cal.dateComponents([.year, .month, .day], from: observed)
            if oc.year == year && oc.month == month && oc.day == day {
                return USNodeInfo(shortZh: sZh, shortEn: sEn, fullZh: fZh, fullEn: fEn, isFederal: true, isMarketingOnly: false)
            }
        }
        if month == 12 && day == 31, let nextNY = HolidayLunarService.noonBeijingDate(year + 1, 1, 1),
           cal.component(.weekday, from: nextNY) == 7 {
            return USNodeInfo(shortZh: "新年休", shortEn: "NYObs", fullZh: "美国新年补休", fullEn: "US New Year (Observed)", isFederal: true, isMarketingOnly: false)
        }
        return nil
    }
}
