//
//  WorldClockStore.swift
//  Itsycal DualTZ
//

import Foundation

struct PrimaryTimeZoneOption {
    let identifier: String
    let flag: String
    let nameZH: String
    let nameEN: String
    let utcOffsetLabel: String

    var displayTitle: String {
        "\(flag) \(identifier) · \(utcOffsetLabel)"
    }
}

struct WorldCityCatalogItem {
    let id: String
    let timeZoneIdentifier: String
    let flag: String
    let nameZH: String
    let nameEN: String
    let isUSCity: Bool
}

struct SecondaryCityConfig: Codable, Equatable {
    let id: String
    var enabled: Bool
    var alias: String
}

enum WorkBusinessStatus {
    case work       // 09:00–17:59 当地办公中
    case prime      // 18:00–22:59 当地晚间消费高峰
    case morning    // 07:00–08:59 早间准备
    case night      // 23:00–06:59 深夜

    var labelZH: String {
        switch self {
        case .work: return "办公中"
        case .prime: return "消费高峰"
        case .morning: return "早间"
        case .night: return "深夜"
        }
    }

    var labelEN: String {
        switch self {
        case .work: return "Work"
        case .prime: return "Prime"
        case .morning: return "Morning"
        case .night: return "Night"
        }
    }
}

struct SecondaryCitySnapshot {
    let id: String
    let flag: String
    let displayName: String
    let formattedTime: String
    let tzAbbreviation: String
    let dayLabel: String
    let status: WorkBusinessStatus
    let offsetText: String
}

struct MenuBarTokenConfig: Codable, Equatable {
    var showPrefix: Bool = true
    var showDate: Bool = true
    var showWeekday: Bool = true
    var showTime: Bool = true
    var showUSRef: Bool = false
    var showDayNight: Bool = false

    func buildTemplate(isChinese: Bool) -> String {
        var primaryTokens: [String] = []
        if showDayNight { primaryTokens.append("{bj_dn}") }
        if showPrefix { primaryTokens.append("{CITY}") }
        if showDate {
            primaryTokens.append(isChinese ? "{PRIMARY:MM月dd日}" : "{PRIMARY:MMM d}")
        }
        if showWeekday { primaryTokens.append("{PRIMARY:EEE}") }
        if showTime { primaryTokens.append("{PRIMARY:HH:mm}") }

        var result = primaryTokens.joined(separator: " ")
        if showUSRef {
            let usPart = isChinese ? "美西 {LA:HH:mm}" : "LA {LA:HH:mm}"
            result = result.isEmpty ? usPart : "\(result) · \(usPart)"
        }
        return result.isEmpty ? "{PRIMARY:HH:mm}" : result
    }
}

enum WorldClockStore {
    static let primaryOptions: [PrimaryTimeZoneOption] = [
        PrimaryTimeZoneOption(identifier: "Asia/Shanghai", flag: "🇨🇳", nameZH: "北京", nameEN: "Beijing", utcOffsetLabel: "UTC+8"),
        PrimaryTimeZoneOption(identifier: "Asia/Hong_Kong", flag: "🇭🇰", nameZH: "香港", nameEN: "Hong Kong", utcOffsetLabel: "UTC+8"),
        PrimaryTimeZoneOption(identifier: "Asia/Taipei", flag: "🇹🇼", nameZH: "台北", nameEN: "Taipei", utcOffsetLabel: "UTC+8"),
        PrimaryTimeZoneOption(identifier: "Asia/Singapore", flag: "🇸🇬", nameZH: "新加坡", nameEN: "Singapore", utcOffsetLabel: "UTC+8"),
        PrimaryTimeZoneOption(identifier: "Asia/Tokyo", flag: "🇯🇵", nameZH: "东京", nameEN: "Tokyo", utcOffsetLabel: "UTC+9")
    ]

    static let cityCatalog: [WorldCityCatalogItem] = [
        WorldCityCatalogItem(id: "la", timeZoneIdentifier: "America/Los_Angeles", flag: "🇺🇸", nameZH: "洛杉矶", nameEN: "Los Angeles", isUSCity: true),
        WorldCityCatalogItem(id: "ny", timeZoneIdentifier: "America/New_York", flag: "🇺🇸", nameZH: "纽约", nameEN: "New York", isUSCity: true),
        WorldCityCatalogItem(id: "chi", timeZoneIdentifier: "America/Chicago", flag: "🇺🇸", nameZH: "芝加哥", nameEN: "Chicago", isUSCity: true),
        WorldCityCatalogItem(id: "lon", timeZoneIdentifier: "Europe/London", flag: "🇬🇧", nameZH: "伦敦", nameEN: "London", isUSCity: false),
        WorldCityCatalogItem(id: "fra", timeZoneIdentifier: "Europe/Berlin", flag: "🇩🇪", nameZH: "法兰克福", nameEN: "Frankfurt", isUSCity: false),
        WorldCityCatalogItem(id: "tyo", timeZoneIdentifier: "Asia/Tokyo", flag: "🇯🇵", nameZH: "东京", nameEN: "Tokyo", isUSCity: false),
        WorldCityCatalogItem(id: "sin", timeZoneIdentifier: "Asia/Singapore", flag: "🇸🇬", nameZH: "新加坡", nameEN: "Singapore", isUSCity: false),
        WorldCityCatalogItem(id: "syd", timeZoneIdentifier: "Australia/Sydney", flag: "🇦🇺", nameZH: "悉尼", nameEN: "Sydney", isUSCity: false)
    ]

    static let defaultSecondaryConfigs: [SecondaryCityConfig] = [
        SecondaryCityConfig(id: "la", enabled: true, alias: ""),
        SecondaryCityConfig(id: "ny", enabled: true, alias: "")
    ]

    static var currentPrimaryOption: PrimaryTimeZoneOption {
        let id = UserDefaults.standard.string(forKey: kDualTZPrimaryTimeZoneID) ?? "Asia/Shanghai"
        return primaryOptions.first(where: { $0.identifier == id }) ?? primaryOptions[0]
    }

    static var primaryTimeZone: TimeZone {
        let opt = currentPrimaryOption
        return TimeZone(identifier: opt.identifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    static var primaryFlag: String {
        currentPrimaryOption.flag
    }

    static var primaryDisplayName: String {
        let custom = (UserDefaults.standard.string(forKey: kDualTZPrimaryCityAlias) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let opt = currentPrimaryOption
        return LocalizationService.pick(opt.nameZH, opt.nameEN)
    }

    static func loadSecondaryConfigs() -> [SecondaryCityConfig] {
        guard let raw = UserDefaults.standard.string(forKey: kDualTZSecondaryCitiesJSON),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SecondaryCityConfig].self, from: data) else {
            return defaultSecondaryConfigs
        }
        return decoded
    }

    static func saveSecondaryConfigs(_ configs: [SecondaryCityConfig]) {
        guard let data = try? JSONEncoder().encode(configs),
              let str = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(str, forKey: kDualTZSecondaryCitiesJSON)
    }

    static func secondaryConfig(for cityID: String) -> SecondaryCityConfig {
        let list = loadSecondaryConfigs()
        return list.first(where: { $0.id == cityID }) ?? SecondaryCityConfig(id: cityID, enabled: false, alias: "")
    }

    static func setSecondaryCity(id cityID: String, enabled: Bool? = nil, alias: String? = nil) {
        var list = loadSecondaryConfigs()
        if let idx = list.firstIndex(where: { $0.id == cityID }) {
            if let enabled = enabled { list[idx].enabled = enabled }
            if let alias = alias { list[idx].alias = alias }
        } else {
            list.append(SecondaryCityConfig(id: cityID, enabled: enabled ?? false, alias: alias ?? ""))
        }
        saveSecondaryConfigs(list)
    }

    static func loadMenuTokens() -> MenuBarTokenConfig {
        guard let raw = UserDefaults.standard.string(forKey: kDualTZMenuTokensJSON),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MenuBarTokenConfig.self, from: data) else {
            return MenuBarTokenConfig()
        }
        return decoded
    }

    static func saveMenuTokens(_ config: MenuBarTokenConfig, syncTemplate: Bool = true) {
        if let data = try? JSONEncoder().encode(config),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: kDualTZMenuTokensJSON)
        }
        if syncTemplate && !UserDefaults.standard.bool(forKey: kDualTZMenuUseAdvanced) {
            UserDefaults.standard.set(config.buildTemplate(isChinese: LocalizationService.isChinese), forKey: kDualTZMenuBarFormat)
        }
    }

    static func syncMenuTemplateFromTokensIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: kDualTZMenuUseAdvanced) else { return }
        let tokens = loadMenuTokens()
        let next = tokens.buildTemplate(isChinese: LocalizationService.isChinese)
        if UserDefaults.standard.string(forKey: kDualTZMenuBarFormat) != next {
            UserDefaults.standard.set(next, forKey: kDualTZMenuBarFormat)
        }
    }

    static func dynamicAbbreviation(for item: WorldCityCatalogItem, at date: Date, timeZone: TimeZone) -> String {
        switch item.timeZoneIdentifier {
        case "America/Los_Angeles":
            return timeZone.isDaylightSavingTime(for: date) ? "PDT" : "PST"
        case "America/New_York":
            return timeZone.isDaylightSavingTime(for: date) ? "EDT" : "EST"
        case "America/Chicago":
            return timeZone.isDaylightSavingTime(for: date) ? "CDT" : "CST"
        case "Europe/London":
            return timeZone.isDaylightSavingTime(for: date) ? "BST" : "GMT"
        case "Europe/Berlin":
            return timeZone.isDaylightSavingTime(for: date) ? "CEST" : "CET"
        default:
            return timeZone.abbreviation(for: date) ?? item.id.uppercased()
        }
    }

    static func utcOffsetString(for timeZone: TimeZone, at date: Date) -> String {
        let secs = timeZone.secondsFromGMT(for: date)
        let hours = Double(secs) / 3600.0
        if abs(hours - hours.rounded()) < 0.01 {
            let h = Int(hours.rounded())
            return h >= 0 ? "UTC+\(h)" : "UTC\(h)"
        }
        let sign = secs >= 0 ? "+" : "-"
        let absSecs = abs(secs)
        return String(format: "UTC%@%d:%02d", sign, absSecs / 3600, (absSecs % 3600) / 60)
    }

    static func businessStatus(forHour hour: Int) -> WorkBusinessStatus {
        switch hour {
        case 9..<18: return .work
        case 18..<23: return .prime
        case 7..<9: return .morning
        default: return .night
        }
    }

    static func activeSecondarySnapshots(
        at date: Date = Date(),
        localTZ: TimeZone = .autoupdatingCurrent
    ) -> [SecondaryCitySnapshot] {
        let configs = loadSecondaryConfigs()
        let refIsSystem = UserDefaults.standard.integer(forKey: kDualTZWorldClockOffsetRef) == 1
        let primaryTZ = primaryTimeZone
        let refTZ = refIsSystem ? localTZ : primaryTZ

        // 按配置启用状态过滤，保持目录展示顺序的一致性
        var snapshots: [SecondaryCitySnapshot] = []
        for item in cityCatalog {
            guard let cfg = configs.first(where: { $0.id == item.id }), cfg.enabled else { continue }
            guard let cityTZ = TimeZone(identifier: item.timeZoneIdentifier) else { continue }

            let cleanAlias = cfg.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = cleanAlias.isEmpty ? LocalizationService.pick(item.nameZH, item.nameEN) : cleanAlias
            let formattedTime = TimeZoneService.formatDate(date, pattern: "HH:mm", in: cityTZ)
            let abbr = dynamicAbbreviation(for: item, at: date, timeZone: cityTZ)

            let calCity = TimeZoneService.gregorianCalendar(in: cityTZ)
            let cityHour = calCity.component(.hour, from: date)
            let status = businessStatus(forHour: cityHour)

            let dayDelta = dayDelta(from: refTZ, to: cityTZ, at: date)
            let dayText: String
            if dayDelta < 0 {
                dayText = LocalizationService.pick("昨日", "Yday")
            } else if dayDelta > 0 {
                dayText = LocalizationService.pick("明日", "Tmrw")
            } else {
                dayText = LocalizationService.pick("今日", "Today")
            }

            let diffHours = Int(round(Double(cityTZ.secondsFromGMT(for: date) - refTZ.secondsFromGMT(for: date)) / 3600.0))
            let offsetText: String
            if diffHours == 0 {
                offsetText = refIsSystem
                    ? LocalizationService.pick("本地", "Local")
                    : LocalizationService.pick("同步", "Same")
            } else {
                offsetText = diffHours > 0 ? "+\(diffHours)h" : "\(diffHours)h"
            }

            snapshots.append(SecondaryCitySnapshot(
                id: item.id,
                flag: item.flag,
                displayName: name,
                formattedTime: formattedTime,
                tzAbbreviation: abbr,
                dayLabel: dayText,
                status: status,
                offsetText: offsetText
            ))
        }
        return snapshots
    }

    private static func dayDelta(from refTZ: TimeZone, to targetTZ: TimeZone, at date: Date) -> Int {
        let refComp = TimeZoneService.gregorianCalendar(in: refTZ).dateComponents([.year, .month, .day], from: date)
        let tgtComp = TimeZoneService.gregorianCalendar(in: targetTZ).dateComponents([.year, .month, .day], from: date)
        let utc = TimeZoneService.gregorianCalendar(in: TimeZoneService.utcTZ)
        guard let d1 = utc.date(from: refComp), let d2 = utc.date(from: tgtComp) else { return 0 }
        return Int(round(d2.timeIntervalSince(d1) / 86400.0))
    }
}
