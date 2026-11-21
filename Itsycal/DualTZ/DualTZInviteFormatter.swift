//
//  DualTZInviteFormatter.swift
//  Itsycal DualTZ
//

import Cocoa

@objcMembers
final class DualTZEchoResult: NSObject {
    let text: String
    let isLateNight: Bool

    init(text: String, isLateNight: Bool) {
        self.text = text
        self.isLateNight = isLateNight
    }
}

enum DualTZInviteFormatter {
    static func shortLocalTag(at date: Date, localTZ: TimeZone = .autoupdatingCurrent) -> String {
        if localTZ.identifier == TimeZoneService.losAngelesTZ.identifier {
            return LocalizationService.pick("美西", "LA")
        }
        return localTZ.abbreviation(for: date) ?? LocalizationService.pick("本地", "Local")
    }

    static func echoResult(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        isBeijingInput: Bool,
        localTZ: TimeZone = .autoupdatingCurrent
    ) -> DualTZEchoResult {
        if isAllDay {
            return DualTZEchoResult(text: LocalizationService.tr("dualtz.echo.allday"), isLateNight: false)
        }
        let targetTZ = isBeijingInput ? localTZ : TimeZoneService.beijingTZ
        let targetLabel = isBeijingInput
            ? TimeZoneService.localTimeZoneLabel(at: startDate, localTZ: localTZ)
            : LocalizationService.pick("北京时间", "Beijing")
        let cal = TimeZoneService.gregorianCalendar(in: targetTZ)
        let sc = cal.dateComponents([.year, .month, .day, .hour], from: startDate)
        let ec = cal.dateComponents([.year, .month, .day], from: endDate)
        let wd = TimeZoneService.weekdayText(for: startDate, in: targetTZ)
        let sTime = TimeZoneService.formatDate(startDate, pattern: "HH:mm", in: targetTZ)
        let eTime = TimeZoneService.formatDate(endDate, pattern: "HH:mm", in: targetTZ)

        let startHour = sc.hour ?? 12
        let warnEnabled = UserDefaults.standard.object(forKey: kDualTZWarnLateNight) == nil
            ? true
            : UserDefaults.standard.bool(forKey: kDualTZWarnLateNight)
        let isLateNight = warnEnabled && (startHour >= 0 && startHour < 7)

        let body: String
        if sc.year == ec.year && sc.month == ec.month && sc.day == ec.day || endDate <= startDate {
            let range = endDate > startDate ? "\(sTime)–\(eTime)" : sTime
            body = "\(targetLabel)：\(sc.month ?? 1)/\(sc.day ?? 1)(\(wd)) \(range)"
        } else {
            body = "\(targetLabel)：\(sc.month ?? 1)/\(sc.day ?? 1) \(sTime) – \(ec.month ?? 1)/\(ec.day ?? 1) \(eTime)"
        }
        if isLateNight {
            let suffix = LocalizationService.tr("dualtz.echo.late_night")
            return DualTZEchoResult(text: "🌙 \(body) · \(suffix)", isLateNight: true)
        }
        return DualTZEchoResult(text: body, isLateNight: false)
    }

    static func inviteText(
        title: String,
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool,
        location: String?,
        meetingURL: URL?,
        localTZ: TimeZone = .autoupdatingCurrent
    ) -> String {
        let bjCal = TimeZoneService.gregorianCalendar(in: TimeZoneService.beijingTZ)
        let laCal = TimeZoneService.gregorianCalendar(in: localTZ)
        let bjComp = bjCal.dateComponents([.month, .day], from: startDate)
        let laComp = laCal.dateComponents([.month, .day], from: startDate)
        let bjWD = TimeZoneService.weekdayText(for: startDate, in: TimeZoneService.beijingTZ)
        let laWD = TimeZoneService.weekdayText(for: startDate, in: localTZ)

        var lines: [String] = []
        if isAllDay {
            let dateStr = LocalizationService.pick("\(bjComp.month ?? 1)月\(bjComp.day ?? 1)日(\(bjWD)) 全天", "\(bjComp.month ?? 1)/\(bjComp.day ?? 1) (\(bjWD)) All-day")
            lines.append("\(title)｜\(dateStr)")
        } else {
            let bjS = TimeZoneService.formatDate(startDate, pattern: "HH:mm", in: TimeZoneService.beijingTZ)
            let laS = TimeZoneService.formatDate(startDate, pattern: "HH:mm", in: localTZ)
            let hasEnd = (endDate != nil && endDate! > startDate)
            let bjRange = hasEnd ? "\(bjS)–\(TimeZoneService.formatDate(endDate!, pattern: "HH:mm", in: TimeZoneService.beijingTZ))" : bjS
            let laRange = hasEnd ? "\(laS)–\(TimeZoneService.formatDate(endDate!, pattern: "HH:mm", in: localTZ))" : laS
            let laTag = TimeZoneService.localTimeZoneLabel(at: startDate, localTZ: localTZ)
            let bjPrefix = LocalizationService.pick("北京时间", "Beijing")
            let header = "\(title)\n\(bjPrefix): \(bjComp.month ?? 1)/\(bjComp.day ?? 1)(\(bjWD)) \(bjRange)\n\(laTag): \(laComp.month ?? 1)/\(laComp.day ?? 1)(\(laWD)) \(laRange)"
            lines.append(header)
        }
        if let loc = location, !loc.isEmpty {
            lines.append("\(LocalizationService.pick("地点", "Location")): \(loc)")
        }
        if let url = meetingURL {
            lines.append("\(LocalizationService.pick("会议链接", "Meeting")): \(url.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }
}
