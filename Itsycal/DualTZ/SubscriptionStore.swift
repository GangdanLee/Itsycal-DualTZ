//
//  SubscriptionStore.swift
//  Itsycal DualTZ
//

import Foundation

enum SubscriptionRegion: String, CaseIterable {
    case us
    case jp
    case uk
    case eu
    case sg
    case cn

    var flag: String {
        switch self {
        case .us: return "🇺🇸"
        case .jp: return "🇯🇵"
        case .uk: return "🇬🇧"
        case .eu: return "🇪🇺"
        case .sg: return "🇸🇬"
        case .cn: return "🇨🇳"
        }
    }

    var labelZH: String {
        switch self {
        case .us: return "🇺🇸 美区"
        case .jp: return "🇯🇵 日区"
        case .uk: return "🇬🇧 英区"
        case .eu: return "🇪🇺 欧区"
        case .sg: return "🇸🇬 新加坡"
        case .cn: return "🇨🇳 国区"
        }
    }

    var labelEN: String {
        switch self {
        case .us: return "🇺🇸 US"
        case .jp: return "🇯🇵 JP"
        case .uk: return "🇬🇧 UK"
        case .eu: return "🇪🇺 EU"
        case .sg: return "🇸🇬 SG"
        case .cn: return "🇨🇳 CN"
        }
    }

    var localizedLabel: String {
        LocalizationService.pick(labelZH, labelEN)
    }

    var defaultTimeZoneID: String {
        switch self {
        case .us: return "America/Los_Angeles"
        case .jp: return "Asia/Tokyo"
        case .uk: return "Europe/London"
        case .eu: return "Europe/Berlin"
        case .sg: return "Asia/Singapore"
        case .cn: return "Asia/Shanghai"
        }
    }
}

struct SubscriptionItem: Codable, Equatable {
    let id: String
    var customName: String
    var accountEmail: String
    var regionCode: String
    var paymentMethod: String
    var priceText: String
    var billingDay: Int
    var billingTimeZoneID: String
    var enabled: Bool

    var region: SubscriptionRegion {
        SubscriptionRegion(rawValue: regionCode) ?? .us
    }
}

struct SubscriptionScheduleSnapshot {
    let item: SubscriptionItem
    let nextDueDate: Date
    let nextDueMoDate: MoDate
    let daysRemaining: Int
    let progressRatio: Double
    let isUrgent: Bool
    let etaShortText: String
    let etaLongText: String
    let dueDetailText: String
    let dueShortDateText: String
}

enum SubscriptionStore {
    static let defaultItems: [SubscriptionItem] = [
        SubscriptionItem(
            id: "sub_claude_max",
            customName: "Claude Max · 主号",
            accountEmail: "morgan@gmail.com",
            regionCode: "us",
            paymentMethod: "美卡 Visa ••4242",
            priceText: "$100/mo",
            billingDay: 24,
            billingTimeZoneID: "America/Los_Angeles",
            enabled: true
        ),
        SubscriptionItem(
            id: "sub_amazon_pro",
            customName: "Amazon 北美专业卖家",
            accountEmail: "us-seller@brand.co",
            regionCode: "us",
            paymentMethod: "PingPong 美卡",
            priceText: "$39.99/mo",
            billingDay: 2,
            billingTimeZoneID: "America/Los_Angeles",
            enabled: true
        )
    ]

    static func loadAll() -> [SubscriptionItem] {
        guard UserDefaults.standard.object(forKey: kDualTZSubscriptionsJSON) != nil else {
            return defaultItems
        }
        guard let raw = UserDefaults.standard.string(forKey: kDualTZSubscriptionsJSON),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([SubscriptionItem].self, from: data) else {
            return defaultItems
        }
        return list
    }

    static func saveAll(_ items: [SubscriptionItem]) {
        guard let data = try? JSONEncoder().encode(items),
              let str = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(str, forKey: kDualTZSubscriptionsJSON)
    }

    static func add(_ item: SubscriptionItem) {
        var list = loadAll()
        list.append(item)
        saveAll(list)
    }

    static func update(_ item: SubscriptionItem) {
        var list = loadAll()
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
        } else {
            list.append(item)
        }
        saveAll(list)
    }

    static func delete(id: String) {
        var list = loadAll()
        list.removeAll { $0.id == id }
        saveAll(list)
    }

    /// 计算在主城市日历中某公历日（year/month/day）是否恰好是某启用订阅的扣费日（考虑月末大小月/闰年夹取）
    static func subscriptionsDue(on moDate: MoDate, referenceDate: Date = Date()) -> [SubscriptionScheduleSnapshot] {
        guard UserDefaults.standard.bool(forKey: kDualTZShowSubscriptionBar) else { return [] }
        let items = loadAll().filter { $0.enabled }
        return items.compactMap { item in
            let snap = snapshot(for: item, from: referenceDate)
            let dueDateInPrimary = primaryDayMatch(for: item, targetMoDate: moDate)
            return dueDateInPrimary ? snap : nil
        }
    }

    static func hasSubscriptionDue(on moDate: MoDate) -> Bool {
        guard UserDefaults.standard.bool(forKey: kDualTZShowSubscriptionBar) else { return false }
        for item in loadAll() where item.enabled {
            if primaryDayMatch(for: item, targetMoDate: moDate) {
                return true
            }
        }
        return false
    }

    static func activeSnapshots(from referenceDate: Date = Date()) -> [SubscriptionScheduleSnapshot] {
        loadAll()
            .filter { $0.enabled }
            .map { snapshot(for: $0, from: referenceDate) }
            .sorted { $0.daysRemaining < $1.daysRemaining }
    }

    static func snapshot(for item: SubscriptionItem, from referenceDate: Date = Date()) -> SubscriptionScheduleSnapshot {
        let primaryTZ = WorldClockStore.primaryTimeZone
        let primaryCal = TimeZoneService.gregorianCalendar(in: primaryTZ)
        let billTZ = TimeZone(identifier: item.billingTimeZoneID) ?? primaryTZ
        let billCal = TimeZoneService.gregorianCalendar(in: billTZ)

        let clampedBillingDay = max(1, min(31, item.billingDay))
        let nowBillComp = billCal.dateComponents([.year, .month, .day], from: referenceDate)
        let curYear = nowBillComp.year ?? 2026
        let curMonth = nowBillComp.month ?? 1

        // 在扣费源时区构建本月扣费瞬间（按当地 00:00 + 扣费源时区与北京时间转换）
        // 美区常见扣费落在当地时间 16:00（即次日北京 08:00，或次月美西 00:00 = 北京 16:00），统一用当地 00:00 起算，如果已过该天则滚入下月
        let thisMonthCandidate = clampedDate(year: curYear, month: curMonth, day: clampedBillingDay, calendar: billCal)
        let dueInstant: Date
        let prevCycleInstant: Date
        let startOfTodayInBill = billCal.startOfDay(for: referenceDate)
        if thisMonthCandidate >= startOfTodayInBill {
            dueInstant = thisMonthCandidate
            let prevYM = shiftMonth(year: curYear, month: curMonth, delta: -1)
            prevCycleInstant = clampedDate(year: prevYM.year, month: prevYM.month, day: clampedBillingDay, calendar: billCal)
        } else {
            let nextYM = shiftMonth(year: curYear, month: curMonth, delta: 1)
            dueInstant = clampedDate(year: nextYM.year, month: nextYM.month, day: clampedBillingDay, calendar: billCal)
            prevCycleInstant = thisMonthCandidate
        }

        let dueMo = MakeDateWithNSDate(dueInstant, primaryCal)
        let todayMo = TimeZoneService.beijingTodayMoDate(at: referenceDate)
        let daysLeft = max(0, daysBetween(from: todayMo, to: dueMo))

        let totalSpan = max(86400.0, dueInstant.timeIntervalSince(prevCycleInstant))
        let elapsed = max(0.0, referenceDate.timeIntervalSince(prevCycleInstant))
        let ratio = min(0.98, max(0.08, elapsed / totalSpan))

        let isUrgent = daysLeft <= 3
        let etaShort = daysLeft == 0 ? LocalizationService.pick("今", "Now") : "\(daysLeft)d"
        let etaLong: String
        if daysLeft == 0 {
            etaLong = LocalizationService.pick("今日扣费", "Due Today")
        } else {
            etaLong = LocalizationService.pick("\(daysLeft)天后", "In \(daysLeft)d")
        }

        let dueComp = primaryCal.dateComponents([.month, .day, .hour, .minute], from: dueInstant)
        let hm = String(format: "%02d:%02d", dueComp.hour ?? 0, dueComp.minute ?? 0)
        let cityPrefix = WorldClockStore.primaryDisplayName
        let md = "\(dueComp.month ?? 1)/\(dueComp.day ?? 1)"

        let detailText: String
        if item.billingTimeZoneID != primaryTZ.identifier {
            let billAbbr = billTZ.abbreviation(for: dueInstant) ?? ""
            let zoneTag = item.region == .us
                ? LocalizationService.pick("美西 \(billAbbr)", "US \(billAbbr)")
                : billAbbr
            detailText = LocalizationService.pick("\(cityPrefix) \(md) \(hm) (\(zoneTag))", "\(cityPrefix) \(md) \(hm) (\(zoneTag))")
        } else {
            detailText = "\(cityPrefix) \(md) \(hm)"
        }

        return SubscriptionScheduleSnapshot(
            item: item,
            nextDueDate: dueInstant,
            nextDueMoDate: dueMo,
            daysRemaining: daysLeft,
            progressRatio: ratio,
            isUrgent: isUrgent,
            etaShortText: etaShort,
            etaLongText: etaLong,
            dueDetailText: detailText,
            dueShortDateText: md
        )
    }

    private static func primaryDayMatch(for item: SubscriptionItem, targetMoDate: MoDate) -> Bool {
        let billTZ = TimeZone(identifier: item.billingTimeZoneID) ?? WorldClockStore.primaryTimeZone
        let billCal = TimeZoneService.gregorianCalendar(in: billTZ)
        let primaryCal = TimeZoneService.gregorianCalendar(in: WorldClockStore.primaryTimeZone)

        // 先按目标年月的本月或前一个月尝试换算到主时区，看是否落入 targetMoDate
        let year = targetMoDate.year
        let month = targetMoDate.month + 1
        let candidates = [
            (year, month),
            shiftMonth(year: year, month: month, delta: -1),
            shiftMonth(year: year, month: month, delta: 1)
        ]
        for (y, m) in candidates {
            let instant = clampedDate(year: y, month: m, day: max(1, min(31, item.billingDay)), calendar: billCal)
            let mo = MakeDateWithNSDate(instant, primaryCal)
            if mo.year == targetMoDate.year && mo.month == targetMoDate.month && mo.day == targetMoDate.day {
                return true
            }
        }
        return false
    }

    private static func clampedDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let firstComps = DateComponents(year: year, month: month, day: 1, hour: 0, minute: 0, second: 0)
        guard let firstDate = calendar.date(from: firstComps),
              let range = calendar.range(of: .day, in: .month, for: firstDate) else {
            return Date()
        }
        let clampedDay = min(max(1, day), range.count)
        let targetComps = DateComponents(year: year, month: month, day: clampedDay, hour: 0, minute: 0, second: 0)
        return calendar.date(from: targetComps) ?? firstDate
    }

    private static func shiftMonth(year: Int, month: Int, delta: Int) -> (year: Int, month: Int) {
        let zeroBased = (year * 12 + (month - 1)) + delta
        let newYear = zeroBased >= 0 ? zeroBased / 12 : (zeroBased - 11) / 12
        let newMonth = ((zeroBased % 12) + 12) % 12 + 1
        return (newYear, newMonth)
    }

    private static func daysBetween(from a: MoDate, to b: MoDate) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let d1 = cal.date(from: DateComponents(year: a.year, month: a.month + 1, day: a.day)) ?? Date()
        let d2 = cal.date(from: DateComponents(year: b.year, month: b.month + 1, day: b.day)) ?? Date()
        return Int(round(d2.timeIntervalSince(d1) / 86400.0))
    }
}
