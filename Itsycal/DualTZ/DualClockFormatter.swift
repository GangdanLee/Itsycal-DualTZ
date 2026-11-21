//
//  DualClockFormatter.swift
//  Itsycal DualTZ
//

import Foundation

enum DualClockFormatter {
    private enum Segment {
        case localPattern(String)
        case tzPattern(TimeZone, String)
        case cityNameToken
        case diffToken
        case diffCnToken
        case beijingDayNightToken
        case dstGapToken
    }

    private static var tzAliases: [String: TimeZone] {
        [
            "PRIMARY": WorldClockStore.primaryTimeZone,
            "BJ": TimeZoneService.beijingTZ,
            "LA": TimeZoneService.losAngelesTZ,
            "NY": TimeZoneService.newYorkTZ,
            "UTC": TimeZoneService.utcTZ
        ]
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: "\\{([A-Za-z0-9_/+\\-]+)(?::([^}]+))?\\}")

    static func string(from date: Date, template: String, localTZ: TimeZone = .autoupdatingCurrent) -> String {
        guard !template.isEmpty else { return "" }
        let segments = parseSegments(template)
        var output = ""
        for seg in segments {
            switch seg {
            case .localPattern(let pat):
                output += formatSegment(date: date, pattern: pat, timeZone: localTZ, forceChineseLocale: false)
            case .tzPattern(let tz, let pat):
                let isChina = tz.identifier == TimeZoneService.beijingTZ.identifier || tz.identifier == "Asia/Shanghai"
                output += formatSegment(date: date, pattern: pat, timeZone: tz, forceChineseLocale: isChina)
            case .cityNameToken:
                output += WorldClockStore.primaryDisplayName
            case .diffToken:
                let delta = TimeZoneService.dayDeltaFromLocalToBeijing(at: date, localTZ: localTZ)
                output += delta > 0 ? "+\(delta)d" : (delta < 0 ? "\(delta)d" : "")
            case .diffCnToken:
                let delta = TimeZoneService.dayDeltaFromLocalToBeijing(at: date, localTZ: localTZ)
                output += delta > 0 ? LocalizationService.pick("次日", "+1d") : ""
            case .beijingDayNightToken:
                let hour = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ).component(.hour, from: date)
                output += (hour >= 7 && hour < 20) ? "☀️" : "🌙"
            case .dstGapToken:
                let diffSec = TimeZoneService.beijingTZ.secondsFromGMT(for: date) - localTZ.secondsFromGMT(for: date)
                output += "\(Int(round(Double(diffSec) / 3600.0)))h"
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    static func usesTime(_ template: String) -> Bool {
        let timeChars = CharacterSet(charactersIn: "aHhKkjms")
        return scanICUCharacters(in: template, targetSet: timeChars)
    }

    static func usesSeconds(_ template: String) -> Bool {
        return scanICUCharacters(in: template, targetSet: CharacterSet(charactersIn: "s"))
    }

    private static func parseSegments(_ template: String) -> [Segment] {
        let nsStr = template as NSString
        let matches = tokenRegex.matches(in: template, range: NSRange(location: 0, length: nsStr.length))
        var segments: [Segment] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let raw = nsStr.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                segments.append(.localPattern(raw))
            }
            let key = nsStr.substring(with: match.range(at: 1))
            let subRange = match.range(at: 2)
            let subPat = subRange.location != NSNotFound ? nsStr.substring(with: subRange) : nil

            if let tokenSeg = resolveToken(key: key, subPattern: subPat) {
                segments.append(tokenSeg)
            } else {
                segments.append(.localPattern(nsStr.substring(with: match.range)))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsStr.length {
            segments.append(.localPattern(nsStr.substring(from: cursor)))
        }
        return segments
    }

    private static func resolveToken(key: String, subPattern: String?) -> Segment? {
        switch key {
        case "CITY": return .cityNameToken
        case "diff": return .diffToken
        case "diff_cn": return .diffCnToken
        case "bj_dn": return .beijingDayNightToken
        case "dst_gap": return .dstGapToken
        default:
            guard let pat = subPattern, !pat.isEmpty else { return nil }
            let tz = tzAliases[key] ?? TimeZone(identifier: key)
            guard let resolvedTZ = tz else { return nil }
            return .tzPattern(resolvedTZ, pat)
        }
    }

    private static func formatSegment(date: Date, pattern: String, timeZone: TimeZone, forceChineseLocale: Bool) -> String {
        let formatter = DateFormatter()
        formatter.formattingContext = .standalone
        formatter.calendar = TimeZoneService.gregorianCalendar(in: timeZone)
        formatter.timeZone = timeZone
        formatter.locale = (forceChineseLocale && LocalizationService.isChinese)
            ? Locale(identifier: "zh_Hans_CN@calendar=gregorian")
            : LocalizationService.effectiveLocale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // 绕行 macOS 15+ 下 ISO 8601 日历导致 EEE 星期缩写丢失的问题
    private static func gregorianSystemLocale() -> Locale {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let country = Locale.current.region?.identifier
        let base = country.map { "\(lang)_\($0)" } ?? lang
        return Locale(identifier: "\(base)@calendar=gregorian")
    }

    private static func scanICUCharacters(in template: String, targetSet: CharacterSet) -> Bool {
        for seg in parseSegments(template) {
            let pat: String
            switch seg {
            case .localPattern(let p), .tzPattern(_, let p): pat = p
            default: continue
            }
            let stripped = pat.replacingOccurrences(of: "''", with: "")
            var inQuotes = false
            for scalar in stripped.unicodeScalars {
                if scalar == "'" {
                    inQuotes.toggle()
                    continue
                }
                if !inQuotes && targetSet.contains(scalar) {
                    return true
                }
            }
        }
        return false
    }
}
