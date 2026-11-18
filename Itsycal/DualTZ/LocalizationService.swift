//
//  LocalizationService.swift
//  Itsycal DualTZ
//

import Foundation

extension Notification.Name {
    static let dualTZLanguageDidChange = Notification.Name("DualTZLanguageDidChangeNotification")
}

enum AppLanguageMode: Int {
    case chinese = 0
    case english = 1
    case system = 2
}

enum LocalizationService {
    static var mode: AppLanguageMode {
        let raw = UserDefaults.standard.integer(forKey: kDualTZAppLanguage)
        return AppLanguageMode(rawValue: raw) ?? .chinese
    }

    static var isChinese: Bool {
        switch mode {
        case .chinese:
            return true
        case .english:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh")
        }
    }

    static var effectiveLocale: Locale {
        return isChinese
            ? Locale(identifier: "zh_Hans_CN@calendar=gregorian")
            : Locale(identifier: "en_US@calendar=gregorian")
    }

    static var effectivePickerLocale: Locale {
        // 统一采用年-月-日 24 小时制（en_SE 为官方 ISO yyyy-MM-dd HH:mm），消除 11/12 月日混淆
        return isChinese
            ? Locale(identifier: "zh_CN@calendar=gregorian")
            : Locale(identifier: "en_SE@calendar=gregorian")
    }

    private static var zhBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }()

    static func tr(_ key: String, default fallback: String? = nil) -> String {
        if isChinese {
            if let hit = DualTZStrings.zhTable[key] {
                return hit
            }
            if let bundle = zhBundle {
                let sentinel = "__MISSING__"
                let val = bundle.localizedString(forKey: key, value: sentinel, table: nil)
                if val != sentinel {
                    return val
                }
            }
            return fallback ?? key
        }
        if let hit = DualTZStrings.enTable[key] {
            return hit
        }
        return fallback ?? key
    }

    static func pick(_ zh: String, _ en: String) -> String {
        return isChinese ? zh : en
    }
}
