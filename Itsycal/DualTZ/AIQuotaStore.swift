//
//  AIQuotaStore.swift
//  Itsycal DualTZ
//

import Cocoa
import CryptoKit
import Foundation
import LocalAuthentication
import Security

extension Notification.Name {
    static let dualTZAIQuotaDidChange = Notification.Name("DualTZAIQuotaDidChangeNotification")
}

enum AIQuotaProvider: String, Codable, CaseIterable {
    case claude
    case antigravity
    case codex
    case cursor

    var badgeText: String {
        switch self {
        case .claude: return "CLAUDE"
        case .antigravity: return "GEMINI"
        case .codex: return "CODEX"
        case .cursor: return "CURSOR"
        }
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .antigravity: return "Antigravity (Gemini)"
        case .codex: return "ChatGPT Codex"
        case .cursor: return "Cursor"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .claude: return .systemOrange
        case .antigravity: return .systemGreen
        case .codex: return .systemPurple
        case .cursor: return .systemBlue
        }
    }

    var defaultPrimaryWindowLabel: String {
        switch self {
        case .claude, .codex: return "5h"
        case .antigravity: return "Gemini"
        case .cursor: return "Plan"
        }
    }

    var defaultSecondaryWindowLabel: String? {
        switch self {
        case .claude, .codex: return "7d"
        case .antigravity: return "Claude/GPT"
        case .cursor: return nil
        }
    }
}

struct AIQuotaAccount: Codable, Equatable {
    let id: String
    var provider: AIQuotaProvider
    var customName: String
    var configPath: String
    var keychainService: String
    var enabled: Bool

    var sourceSubtitle: String {
        switch provider {
        case .claude:
            if !configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return configPath
            }
            let svc = keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
            return svc.isEmpty ? "~/.claude (Keychain)" : svc
        case .antigravity:
            return LocalizationService.pick("本地进程探针 · 离线缓存", "Local RPC · Cached")
        case .codex:
            let p = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return p.isEmpty ? "~/.codex/auth.json" : p
        case .cursor:
            let p = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return p.isEmpty ? "state.vscdb" : (p as NSString).lastPathComponent
        }
    }
}

enum AIQuotaStatusState: String, Codable {
    case live
    case cached
    case needsKeychainPermission
    case needsLogin
    case rateLimited
    case unavailable
}

struct AIQuotaSnapshot: Codable, Equatable {
    let accountID: String
    var remainingPercent: Double?
    var primaryWindowLabel: String
    var resetsAt: Date?
    var secondaryRemainingPercent: Double?
    var secondaryWindowLabel: String?
    var secondaryResetsAt: Date?
    var accountEmail: String?
    var planLabel: String?
    var state: AIQuotaStatusState
    var statusMessage: String?
    var updatedAt: Date

    var isExpiredCycleCache: Bool {
        guard state == .cached || state == .unavailable || state == .rateLimited,
              let resetsAt else {
            return false
        }
        return Date() >= resetsAt
    }

    /// 若处于缓存且重置周期已过，返回 nil，不在界面造假 100%，改为提示“周期已过 · 待同步”
    var effectiveRemainingPercent: Double? {
        guard !isExpiredCycleCache, let raw = remainingPercent else { return nil }
        return max(0, min(100, raw))
    }

    var ringColor: NSColor {
        guard let pct = effectiveRemainingPercent else {
            return .secondaryLabelColor
        }
        if pct >= 50 {
            return .systemBlue
        } else if pct >= 20 {
            return .systemOrange
        } else {
            return .systemRed
        }
    }

    func ringColor(provider: AIQuotaProvider) -> NSColor {
        guard let pct = effectiveRemainingPercent else {
            return .secondaryLabelColor
        }
        if pct >= 50 {
            return provider == .claude ? .systemBlue : provider.accentColor
        } else if pct >= 20 {
            return .systemOrange
        } else {
            return .systemRed
        }
    }

    func formattedResetText(referenceDate: Date = Date()) -> String? {
        if isExpiredCycleCache {
            return LocalizationService.pick("周期已过 · 待同步", "Cycle passed · Sync")
        }
        guard let resetsAt else { return nil }
        let primaryTZ = WorldClockStore.primaryTimeZone
        let cal = TimeZoneService.gregorianCalendar(in: primaryTZ)
        let hmComps = cal.dateComponents([.month, .day, .hour, .minute], from: resetsAt)
        let hm = String(format: "%02d:%02d", hmComps.hour ?? 0, hmComps.minute ?? 0)

        if cal.isDate(resetsAt, inSameDayAs: referenceDate) {
            return LocalizationService.pick("今天 \(hm) 重置", "Today \(hm)")
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: referenceDate),
           cal.isDate(resetsAt, inSameDayAs: tomorrow) {
            return LocalizationService.pick("明天 \(hm) 重置", "Tomorrow \(hm)")
        }
        let md = String(format: "%02d/%02d", hmComps.month ?? 1, hmComps.day ?? 1)
        return LocalizationService.pick("\(md) \(hm) 重置", "\(md) \(hm)")
    }
}

enum AIQuotaStore {
    static let claudeKeychainPrefix = "Claude Code-credentials"

    static func loadAccounts() -> [AIQuotaAccount] {
        guard UserDefaults.standard.object(forKey: kDualTZAIQuotaAccountsJSON) != nil else {
            return discoverDefaultAccounts()
        }
        guard let raw = UserDefaults.standard.string(forKey: kDualTZAIQuotaAccountsJSON),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([AIQuotaAccount].self, from: data) else {
            return discoverDefaultAccounts()
        }
        return list
    }

    static func saveAccounts(_ accounts: [AIQuotaAccount]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                Self.saveAccounts(accounts)
            }
            return
        }
        guard let data = try? JSONEncoder().encode(accounts),
              let str = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(str, forKey: kDualTZAIQuotaAccountsJSON)
        postChangedNotification()
    }

    static func add(_ account: AIQuotaAccount) {
        var list = loadAccounts()
        list.append(account)
        saveAccounts(list)
    }

    static func update(_ account: AIQuotaAccount) {
        var list = loadAccounts()
        if let idx = list.firstIndex(where: { $0.id == account.id }) {
            list[idx] = account
        } else {
            list.append(account)
        }
        saveAccounts(list)
    }

    static func delete(id: String) {
        var list = loadAccounts()
        list.removeAll { $0.id == id }
        saveAccounts(list)

        var snaps = loadSnapshots()
        if snaps.removeValue(forKey: id) != nil {
            saveSnapshots(snaps)
        }
    }

    static func loadSnapshots() -> [String: AIQuotaSnapshot] {
        guard let raw = UserDefaults.standard.string(forKey: kDualTZAIQuotaSnapshotsJSON),
              let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: AIQuotaSnapshot].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func saveSnapshot(_ snapshot: AIQuotaSnapshot) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                Self.saveSnapshot(snapshot)
            }
            return
        }
        var dict = loadSnapshots()
        dict[snapshot.accountID] = snapshot
        saveSnapshots(dict)
    }

    static func saveSnapshots(_ snapshots: [String: AIQuotaSnapshot]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                Self.saveSnapshots(snapshots)
            }
            return
        }
        guard let data = try? JSONEncoder().encode(snapshots),
              let str = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(str, forKey: kDualTZAIQuotaSnapshotsJSON)
        postChangedNotification()
    }

    private static func postChangedNotification() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .dualTZAIQuotaDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .dualTZAIQuotaDidChange, object: nil)
            }
        }
    }

    /// 静默发现本机 Keychain 中所有的 Claude Code 凭据条目（仅查询 attributes，不触发解锁弹窗）
    static func discoverClaudeKeychainServices() -> [String] {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: ctx
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            return []
        }

        var found = Set<String>()
        for row in rows {
            if let svc = row[kSecAttrService as String] as? String,
               svc.hasPrefix(claudeKeychainPrefix) {
                found.insert(svc)
            }
        }

        return found.sorted { lhs, rhs in
            if lhs == claudeKeychainPrefix { return true }
            if rhs == claudeKeychainPrefix { return false }
            return lhs < rhs
        }
    }

    /// 根据隔离配置目录路径推算 Claude Code 对应的 Keychain service 名称（默认目录无后缀，否则带 8 位 SHA256 前缀）
    static func claudeKeychainServiceName(forConfigDir path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return claudeKeychainPrefix }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .standardizedFileURL.path

        if normalized == defaultPath {
            return claudeKeychainPrefix
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let prefix8 = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(claudeKeychainPrefix)-\(prefix8)"
    }

    static func defaultCodexAuthURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    static func defaultCursorDBURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb", isDirectory: false)
    }

    static func discoverDefaultAccounts() -> [AIQuotaAccount] {
        var result: [AIQuotaAccount] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let claudeServices = discoverClaudeKeychainServices()
        if claudeServices.isEmpty {
            result.append(AIQuotaAccount(
                id: "ai_claude_1",
                provider: .claude,
                customName: LocalizationService.pick("Claude 主", "Claude Primary"),
                configPath: "",
                keychainService: claudeKeychainPrefix,
                enabled: true
            ))
        } else {
            for (idx, svc) in claudeServices.enumerated() {
                let name: String
                if idx == 0 {
                    name = LocalizationService.pick("Claude 主", "Claude Primary")
                } else if idx == 1 {
                    name = LocalizationService.pick("Claude 副", "Claude Secondary")
                } else {
                    name = "Claude #\(idx + 1)"
                }
                result.append(AIQuotaAccount(
                    id: "ai_claude_\(idx + 1)",
                    provider: .claude,
                    customName: name,
                    configPath: "",
                    keychainService: svc,
                    enabled: true
                ))
            }
        }

        let hasAntigravityLocal = fm.fileExists(atPath: home.appendingPathComponent(".gemini").path)
            || fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Antigravity").path)
            || fm.fileExists(atPath: "/Applications/Antigravity.app")
        if hasAntigravityLocal {
            result.append(AIQuotaAccount(
                id: "ai_antigravity_1",
                provider: .antigravity,
                customName: "Antigravity (Gemini)",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
        }

        if fm.fileExists(atPath: defaultCodexAuthURL().path) {
            result.append(AIQuotaAccount(
                id: "ai_codex_1",
                provider: .codex,
                customName: "Codex",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
        }

        if fm.fileExists(atPath: defaultCursorDBURL().path) {
            result.append(AIQuotaAccount(
                id: "ai_cursor_1",
                provider: .cursor,
                customName: "Cursor",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
        }

        // 兜底保证：即使在纯净无本地工具环境，也保留可展示与编辑的预设项
        if !result.contains(where: { $0.provider == .antigravity }) {
            result.append(AIQuotaAccount(
                id: "ai_antigravity_1",
                provider: .antigravity,
                customName: "Antigravity (Gemini)",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
        }

        return result
    }

    @discardableResult
    static func mergeDiscoveredAccounts() -> Int {
        var current = loadAccounts()
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var addedCount = 0

        let claudeServices = discoverClaudeKeychainServices()
        for svc in claudeServices {
            let exists = current.contains { acc in
                guard acc.provider == .claude else { return false }
                let resolved = acc.keychainService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? claudeKeychainServiceName(forConfigDir: acc.configPath)
                    : acc.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
                return resolved == svc
            }
            if !exists {
                let claudeCount = current.filter { $0.provider == .claude }.count
                let name = claudeCount == 0
                    ? LocalizationService.pick("Claude 主", "Claude Primary")
                    : (claudeCount == 1
                        ? LocalizationService.pick("Claude 副", "Claude Secondary")
                        : "Claude #\(claudeCount + 1)")
                current.append(AIQuotaAccount(
                    id: "ai_claude_\(UUID().uuidString.prefix(6))",
                    provider: .claude,
                    customName: name,
                    configPath: "",
                    keychainService: svc,
                    enabled: true
                ))
                addedCount += 1
            }
        }

        let hasAntigravity = fm.fileExists(atPath: home.appendingPathComponent(".gemini").path)
            || fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Antigravity").path)
            || fm.fileExists(atPath: "/Applications/Antigravity.app")
        if hasAntigravity && !current.contains(where: { $0.provider == .antigravity }) {
            current.append(AIQuotaAccount(
                id: "ai_ag_\(UUID().uuidString.prefix(6))",
                provider: .antigravity,
                customName: "Antigravity (Gemini)",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
            addedCount += 1
        }

        if fm.fileExists(atPath: defaultCodexAuthURL().path) && !current.contains(where: { $0.provider == .codex }) {
            current.append(AIQuotaAccount(
                id: "ai_codex_\(UUID().uuidString.prefix(6))",
                provider: .codex,
                customName: "Codex",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
            addedCount += 1
        }

        if fm.fileExists(atPath: defaultCursorDBURL().path) && !current.contains(where: { $0.provider == .cursor }) {
            current.append(AIQuotaAccount(
                id: "ai_cursor_\(UUID().uuidString.prefix(6))",
                provider: .cursor,
                customName: "Cursor",
                configPath: "",
                keychainService: "",
                enabled: true
            ))
            addedCount += 1
        }

        if addedCount > 0 {
            saveAccounts(current)
        }
        return addedCount
    }
}
