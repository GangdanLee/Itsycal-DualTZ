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
    static let dualTZKeychainInteractionDidFinish = Notification.Name("DualTZKeychainInteractionDidFinishNotification")
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
            return LocalizationService.pick("Antigravity 本地探针", "Antigravity Local")
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
    var accountUUID: String?
    var accountDisplayName: String?

    init(
        accountID: String,
        remainingPercent: Double?,
        primaryWindowLabel: String,
        resetsAt: Date?,
        secondaryRemainingPercent: Double?,
        secondaryWindowLabel: String?,
        secondaryResetsAt: Date?,
        accountEmail: String?,
        planLabel: String?,
        state: AIQuotaStatusState,
        statusMessage: String?,
        updatedAt: Date,
        accountUUID: String? = nil,
        accountDisplayName: String? = nil
    ) {
        self.accountID = accountID
        self.remainingPercent = remainingPercent
        self.primaryWindowLabel = primaryWindowLabel
        self.resetsAt = resetsAt
        self.secondaryRemainingPercent = secondaryRemainingPercent
        self.secondaryWindowLabel = secondaryWindowLabel
        self.secondaryResetsAt = secondaryResetsAt
        self.accountEmail = accountEmail
        self.planLabel = planLabel
        self.state = state
        self.statusMessage = statusMessage
        self.updatedAt = updatedAt
        self.accountUUID = accountUUID
        self.accountDisplayName = accountDisplayName
    }

    var isExpiredCycleCache: Bool {
        guard state == .cached || state == .unavailable || state == .rateLimited,
              let expDate = resetsAt ?? secondaryResetsAt else {
            return false
        }
        return Date() >= expDate
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
        formattedResetText(includeTimeZoneName: false, referenceDate: referenceDate)
    }

    func formattedResetText(includeTimeZoneName: Bool, referenceDate: Date = Date()) -> String? {
        if isExpiredCycleCache {
            return LocalizationService.pick("周期已过 · 待同步", "Cycle passed · Sync")
        }
        if let resetsAt {
            return Self.formatResetDate(resetsAt, prefix: nil, includeTimeZoneName: includeTimeZoneName, referenceDate: referenceDate)
        }
        if let secondaryResetsAt {
            let lbl = secondaryWindowLabel ?? "7d"
            return Self.formatResetDate(secondaryResetsAt, prefix: lbl, includeTimeZoneName: includeTimeZoneName, referenceDate: referenceDate)
        }
        return nil
    }

    private static func formatResetDate(
        _ date: Date,
        prefix: String?,
        includeTimeZoneName: Bool,
        referenceDate: Date
    ) -> String {
        let primaryTZ = WorldClockStore.primaryTimeZone
        let cal = TimeZoneService.gregorianCalendar(in: primaryTZ)
        let hmComps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        let hm = String(format: "%02d:%02d", hmComps.hour ?? 0, hmComps.minute ?? 0)
        let head = prefix.map { "\($0) " } ?? ""
        let tzTag = includeTimeZoneName ? "\(WorldClockStore.primaryDisplayName) " : ""

        if cal.isDate(date, inSameDayAs: referenceDate) {
            return LocalizationService.pick("\(head)\(tzTag)今天 \(hm) 重置", "\(head)\(tzTag)Today \(hm)")
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: referenceDate),
           cal.isDate(date, inSameDayAs: tomorrow) {
            return LocalizationService.pick("\(head)\(tzTag)明天 \(hm) 重置", "\(head)\(tzTag)Tomorrow \(hm)")
        }
        let md = String(format: "%02d/%02d", hmComps.month ?? 1, hmComps.day ?? 1)
        return LocalizationService.pick("\(head)\(tzTag)\(md) \(hm) 重置", "\(head)\(tzTag)\(md) \(hm)")
    }

    /// 识别同池短+长双时间窗（如 5h + 7d），排除旧异池字段（如 "Gemini" + "Claude/GPT"）
    var hasSamePoolDualTimeWindows: Bool {
        guard !isExpiredCycleCache,
              remainingPercent != nil,
              secondaryRemainingPercent != nil,
              let secLbl = secondaryWindowLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !secLbl.isEmpty else {
            return false
        }
        let priLbl = primaryWindowLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return priLbl.hasSuffix("h") && secLbl.hasSuffix("d")
    }

    /// 同池 5h/7d 双窗口平台（Claude / Antigravity / Codex）统一返回两者较小值，避免 7d 吃紧仍显 100%
    func displayRemainingPercent(for provider: AIQuotaProvider) -> Double? {
        guard let pri = effectiveRemainingPercent else { return nil }
        if hasSamePoolDualTimeWindows, let secRaw = secondaryRemainingPercent {
            let sec = max(0, min(100, secRaw))
            return min(pri, sec)
        }
        return pri
    }

    /// 当同池次窗口（7d）比主窗口（5h）更紧张时返回 true
    func isSecondaryConstraining(for provider: AIQuotaProvider) -> Bool {
        guard hasSamePoolDualTimeWindows,
              let pri = effectiveRemainingPercent,
              let secRaw = secondaryRemainingPercent else {
            return false
        }
        let sec = max(0, min(100, secRaw))
        return sec < pri
    }

    func displayRingColor(provider: AIQuotaProvider) -> NSColor {
        guard let pct = displayRemainingPercent(for: provider) else {
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

    func formattedResetText(
        for provider: AIQuotaProvider,
        includeTimeZoneName: Bool = false,
        referenceDate: Date = Date()
    ) -> String? {
        if isExpiredCycleCache {
            return LocalizationService.pick("周期已过 · 待同步", "Cycle passed · Sync")
        }
        if isSecondaryConstraining(for: provider), let secondaryResetsAt {
            let lbl = secondaryWindowLabel ?? "7d"
            return Self.formatResetDate(secondaryResetsAt, prefix: lbl, includeTimeZoneName: includeTimeZoneName, referenceDate: referenceDate)
        }
        return formattedResetText(includeTimeZoneName: includeTimeZoneName, referenceDate: referenceDate)
    }

    /// 展示真实未压缩的双窗口对比（如 "5h 100% · 7d 99%"），精简旧快照前缀防截断
    func dualWindowSummaryText() -> String? {
        guard hasSamePoolDualTimeWindows,
              let pri = effectiveRemainingPercent,
              let secRaw = secondaryRemainingPercent,
              let secLbl = secondaryWindowLabel else {
            return nil
        }
        let sec = max(0, min(100, secRaw))
        let compactPriLbl: String
        if let lastToken = primaryWindowLabel.split(separator: " ").last,
           lastToken.lowercased().hasSuffix("h") {
            compactPriLbl = String(lastToken)
        } else {
            compactPriLbl = primaryWindowLabel
        }
        return "\(compactPriLbl) \(Int(round(pri)))% · \(secLbl) \(Int(round(sec)))%"
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

    /// 根据 Keychain service 哈希后缀，只读反查已知 Orca 隔离目录与常见 ~/.claude-* 隔离目录
    static func resolveKnownClaudeConfigDir(forKeychainService serviceName: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == claudeKeychainPrefix {
            let defDir = home.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL.path
            return fm.fileExists(atPath: defDir) ? defDir : nil
        }
        guard trimmed.hasPrefix("\(claudeKeychainPrefix)-") else { return nil }

        var candidates: [URL] = []
        let orcaRoot = home.appendingPathComponent("Library/Application Support/orca/claude-profiles", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: orcaRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for profileDir in entries {
                let homeDir = profileDir.appendingPathComponent("home", isDirectory: true)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: homeDir.path, isDirectory: &isDir), isDir.boolValue {
                    candidates.append(homeDir)
                }
            }
        }
        if let homeItems = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: []) {
            for item in homeItems where item.lastPathComponent.hasPrefix(".claude-") {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    candidates.append(item)
                }
            }
        }

        for dirURL in candidates {
            let normalized = dirURL.standardizedFileURL.path
            if claudeKeychainServiceName(forConfigDir: normalized) == trimmed {
                return normalized
            }
        }
        return nil
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
                let resolvedDir = (svc == claudeKeychainPrefix) ? "" : (resolveKnownClaudeConfigDir(forKeychainService: svc) ?? "")
                result.append(AIQuotaAccount(
                    id: "ai_claude_\(idx + 1)",
                    provider: .claude,
                    customName: name,
                    configPath: resolvedDir,
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
        var updatedExisting = false

        // 为已存在但隔离目录留空的非默认 Claude 账号自动补齐可识别的 Orca/隔离目录
        for idx in current.indices where current[idx].provider == .claude {
            let trimmedDir = current[idx].configPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let svc = current[idx].keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDir.isEmpty, !svc.isEmpty, svc != claudeKeychainPrefix,
               let resolvedDir = resolveKnownClaudeConfigDir(forKeychainService: svc) {
                current[idx].configPath = resolvedDir
                updatedExisting = true
            }
        }

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
                let resolvedDir = (svc == claudeKeychainPrefix) ? "" : (resolveKnownClaudeConfigDir(forKeychainService: svc) ?? "")
                current.append(AIQuotaAccount(
                    id: "ai_claude_\(UUID().uuidString.prefix(6))",
                    provider: .claude,
                    customName: name,
                    configPath: resolvedDir,
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

        if addedCount > 0 || updatedExisting {
            saveAccounts(current)
        }
        return addedCount
    }

    /// 检测启用的多条 Claude 账号是否绑定了同一后台账号（优先比较 accountUUID，其次比较 accountEmail）
    static func duplicateClaudePeerNames(accounts: [AIQuotaAccount], snapshots: [String: AIQuotaSnapshot]) -> [String: [String]] {
        var groups: [String: [AIQuotaAccount]] = [:]
        for acc in accounts where acc.enabled && acc.provider == .claude {
            guard let snap = snapshots[acc.id] else { continue }
            let uuidKey = snap.accountUUID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let emailKey = snap.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let identityKey: String?
            if let uuidKey, !uuidKey.isEmpty {
                identityKey = "uuid:\(uuidKey)"
            } else if let emailKey, !emailKey.isEmpty {
                identityKey = "email:\(emailKey)"
            } else {
                identityKey = nil
            }
            if let identityKey {
                groups[identityKey, default: []].append(acc)
            }
        }

        var result: [String: [String]] = [:]
        for (_, peers) in groups where peers.count >= 2 {
            for acc in peers {
                let others = peers.filter { $0.id != acc.id }.map { $0.customName }
                if !others.isEmpty {
                    result[acc.id] = others
                }
            }
        }
        return result
    }

    /// 缩短超长 Apple 私密中继邮箱以保留界面关键信息展示空间
    static func compactDisplayEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "@privaterelay.appleid.com"
        if trimmed.lowercased().hasSuffix(suffix) {
            let local = String(trimmed.dropLast(suffix.count))
            return "\(local)@appleid…"
        }
        return trimmed
    }

    static func shortClaudeKeychainTag(for account: AIQuotaAccount) -> String {
        let explicit = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        let svc = explicit.isEmpty ? claudeKeychainServiceName(forConfigDir: account.configPath) : explicit
        let prefix = "\(claudeKeychainPrefix)-"
        if svc.hasPrefix(prefix) {
            return String(svc.dropFirst(prefix.count))
        }
        return LocalizationService.pick("默认", "Default")
    }
}

// MARK: - Claude 无密码 statusLine 同步（兼容 Orca / 零 Keychain 弹窗）

struct ClaudeStatusLineStatus: Equatable {
    let scriptExists: Bool
    let installedDirs: [String]
    let discoveredDirs: [String]
    let hasUpstreamHooks: Bool

    var installedCount: Int { installedDirs.count }
    var totalCount: Int { discoveredDirs.count }
    var isEnabled: Bool { scriptExists && !installedDirs.isEmpty }
}

struct ClaudeStatusLineInstallResult {
    let installedDirs: [String]
    let failedDirs: [(dir: String, error: String)]
}

struct ClaudeStatusLineUninstallResult {
    let restoredDirs: [String]
    let failedDirs: [(dir: String, error: String)]
}

enum ClaudeStatusLineSync {
    static let markerHeader = "# itsycal-dualtz-statusline-v1"
    static let upstreamBegin = "# itsycal-dualtz-upstream-begin"
    static let upstreamEnd = "# itsycal-dualtz-upstream-end"

    static func configRootURL(baseConfigDir: URL? = nil, homeDir: URL? = nil) -> URL {
        if let baseConfigDir {
            return baseConfigDir.standardizedFileURL
        }
        let home = (homeDir ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("itsycal-dualtz", isDirectory: true)
    }

    static func scriptURL(baseConfigDir: URL? = nil, homeDir: URL? = nil) -> URL {
        configRootURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
            .appendingPathComponent("claude-statusline.sh", isDirectory: false)
    }

    static func rateLimitsDirURL(baseConfigDir: URL? = nil, homeDir: URL? = nil) -> URL {
        configRootURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
            .appendingPathComponent("claude-rate-limits", isDirectory: true)
    }

    static func backupsDirURL(baseConfigDir: URL? = nil, homeDir: URL? = nil) -> URL {
        configRootURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
            .appendingPathComponent("backups", isDirectory: true)
    }

    static func resolvedServiceName(forAccount account: AIQuotaAccount) -> String {
        let explicit = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        return AIQuotaStore.claudeKeychainServiceName(forConfigDir: account.configPath)
    }

    static func cacheKey(forServiceName serviceName: String) -> String {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == AIQuotaStore.claudeKeychainPrefix {
            return "default"
        }
        let prefix = "\(AIQuotaStore.claudeKeychainPrefix)-"
        if trimmed.hasPrefix(prefix) {
            let rawSuffix = String(trimmed.dropFirst(prefix.count))
            let cleaned = String(rawSuffix.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
            return cleaned.isEmpty ? "default" : cleaned
        }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func cacheKey(forConfigDir configDirPath: String, homeDir: URL? = nil) -> String {
        let normalized = URL(fileURLWithPath: NSString(string: configDirPath).expandingTildeInPath).standardizedFileURL.path
        let defaultPath = (homeDir ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.path
        if normalized == defaultPath {
            return "default"
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func discoverTargetClaudeConfigDirs(
        homeDir: URL? = nil,
        accounts: [AIQuotaAccount]? = nil
    ) -> [String] {
        let fm = FileManager.default
        let resolvedHome = (homeDir ?? fm.homeDirectoryForCurrentUser).standardizedFileURL
        var result: [String] = []
        var seen = Set<String>()

        func appendIfDirectory(_ url: URL) {
            let normalized = url.standardizedFileURL.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: normalized, isDirectory: &isDir), isDir.boolValue else { return }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        // 1. 默认 ~/.claude
        appendIfDirectory(resolvedHome.appendingPathComponent(".claude", isDirectory: true))

        // 2. Orca 多号隔离目录
        let orcaRoot = resolvedHome.appendingPathComponent("Library/Application Support/orca/claude-profiles", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: orcaRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for profileDir in entries.sorted(by: { $0.path < $1.path }) {
                appendIfDirectory(profileDir.appendingPathComponent("home", isDirectory: true))
            }
        }

        // 3. 自定义 ~/.claude-* 隔离目录
        if let homeItems = try? fm.contentsOfDirectory(at: resolvedHome, includingPropertiesForKeys: nil, options: []) {
            for item in homeItems.sorted(by: { $0.path < $1.path }) where item.lastPathComponent.hasPrefix(".claude-") {
                appendIfDirectory(item)
            }
        }

        // 4. 账号池中配置的 Claude 目录及可反查目录（仅当未传隔离测试 homeDir 时回退读取全局配置，防止污染测试沙箱）
        let effectiveAccounts = accounts ?? (homeDir == nil ? AIQuotaStore.loadAccounts() : [])
        for acc in effectiveAccounts where acc.provider == .claude {
            let trimmedDir = acc.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDir.isEmpty {
                let expanded = NSString(string: trimmedDir).expandingTildeInPath
                appendIfDirectory(URL(fileURLWithPath: expanded, isDirectory: true))
            } else if homeDir == nil {
                let svc = acc.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
                if let known = AIQuotaStore.resolveKnownClaudeConfigDir(forKeychainService: svc) {
                    appendIfDirectory(URL(fileURLWithPath: known, isDirectory: true))
                }
            }
        }

        return result
    }

    static func shellSingleQuoted(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func unwrapStatusLineCommand(_ command: String) -> (isWrapped: Bool, originalCommand: String?) {
        guard command.contains(markerHeader) else {
            return (false, command)
        }
        let beginToken = "\n\(upstreamBegin)\n"
        let endTokenWithNewline = "\n\(upstreamEnd)\n"
        if let beginRange = command.range(of: beginToken),
           let endRange = command.range(of: endTokenWithNewline, options: .backwards, range: beginRange.upperBound..<command.endIndex) {
            let original = String(command[beginRange.upperBound..<endRange.lowerBound])
            return (true, original.isEmpty ? nil : original)
        }
        let endToken = "\n\(upstreamEnd)"
        if let beginRange = command.range(of: beginToken),
           let endRange = command.range(of: endToken, options: .backwards, range: beginRange.upperBound..<command.endIndex) {
            let original = String(command[beginRange.upperBound..<endRange.lowerBound])
            return (true, original.isEmpty ? nil : original)
        }
        return (true, nil)
    }

    static func wrapStatusLineCommand(
        existingCommand: String?,
        settingsDirPath: String,
        scriptPath: String? = nil
    ) -> String {
        let resolvedScript = URL(
            fileURLWithPath: NSString(string: scriptPath ?? self.scriptURL().path).expandingTildeInPath
        ).standardizedFileURL.path
        let normalizedDir = URL(
            fileURLWithPath: NSString(string: settingsDirPath).expandingTildeInPath
        ).standardizedFileURL.path

        let rawUpstream: String?
        if let existingCommand {
            let unwrapped = unwrapStatusLineCommand(existingCommand)
            if let orig = unwrapped.originalCommand, !orig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rawUpstream = orig
            } else {
                rawUpstream = nil
            }
        } else {
            rawUpstream = nil
        }

        let hookCall = "ITSYCAL_DUALTZ_SETTINGS_DIR=\(shellSingleQuoted(normalizedDir)) /bin/sh \(shellSingleQuoted(resolvedScript)) >/dev/null 2>&1 || :"
        guard let upstream = rawUpstream else {
            return """
            \(markerHeader)
            \(hookCall)
            """
        }

        return """
        \(markerHeader)
        _idtz_p=$(/bin/cat); { [ -n "$_idtz_p" ] && printf '%s\\n' "$_idtz_p" || :; } | \(hookCall); { [ -n "$_idtz_p" ] && printf '%s\\n' "$_idtz_p" || :; } | (
        \(upstreamBegin)
        \(upstream)
        \(upstreamEnd)
        )
        """
    }

    static func hookScriptSource(baseConfigDir: URL? = nil, homeDir: URL? = nil) -> String {
        let cacheDirPath = rateLimitsDirURL(baseConfigDir: baseConfigDir, homeDir: homeDir).path
        let defaultClaudeDirPath = (homeDir ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.path

        return """
        #!/bin/sh
        payload=$(/bin/cat 2>/dev/null || :)
        case "$payload" in
          *'"rate_limits"'*) ;;
          *) exit 0 ;;
        esac
        rate_json=$(printf '%s' "$payload" | /usr/bin/plutil -extract rate_limits json -o - - 2>/dev/null) || exit 0
        case "$rate_json" in
          '{'*'}') ;;
          *) exit 0 ;;
        esac
        raw_dir=${CLAUDE_CONFIG_DIR:-${ITSYCAL_DUALTZ_SETTINGS_DIR:-}}
        while [ "$raw_dir" != "/" ] && [ "${raw_dir%/}" != "$raw_dir" ]; do
          raw_dir=${raw_dir%/}
        done
        default_dir=\(shellSingleQuoted(defaultClaudeDirPath))
        if [ -z "$default_dir" ]; then
          default_dir="${HOME%/}/.claude"
        fi
        if [ -z "$raw_dir" ] || [ "$raw_dir" = "$default_dir" ] || [ "$raw_dir" = "${HOME%/}/.claude" ]; then
          cache_key="default"
          service_name="\(AIQuotaStore.claudeKeychainPrefix)"
        else
          hash8=$(printf '%s' "$raw_dir" | /usr/bin/shasum -a 256 2>/dev/null | /usr/bin/cut -c1-8)
          if [ -z "$hash8" ]; then
            exit 0
          fi
          cache_key="$hash8"
          service_name="\(AIQuotaStore.claudeKeychainPrefix)-$hash8"
        fi
        umask 077
        cache_dir=${ITSYCAL_DUALTZ_CACHE_DIR:-\(shellSingleQuoted(cacheDirPath))}
        /bin/mkdir -p "$cache_dir" 2>/dev/null || exit 0
        now_sec=$(/bin/date +%s 2>/dev/null || printf '0')
        case "$now_sec" in
          ''|*[!0-9]*) now_sec=0 ;;
        esac
        tmp_file="$cache_dir/.${cache_key}.tmp.$$"
        out_file="$cache_dir/${cache_key}.json"
        printf '{"version":1,"updated_at":%s,"service":"%s","rate_limits":%s}\\n' "$now_sec" "$service_name" "$rate_json" >"$tmp_file" 2>/dev/null && /bin/mv -f "$tmp_file" "$out_file" 2>/dev/null || /bin/rm -f "$tmp_file" 2>/dev/null || :
        exit 0
        """
    }

    static func currentStatus(
        targetDirs: [String]? = nil,
        baseConfigDir: URL? = nil,
        homeDir: URL? = nil,
        accounts: [AIQuotaAccount]? = nil
    ) -> ClaudeStatusLineStatus {
        let fm = FileManager.default
        let scriptPath = scriptURL(baseConfigDir: baseConfigDir, homeDir: homeDir).path
        let scriptExists = fm.isExecutableFile(atPath: scriptPath) || fm.fileExists(atPath: scriptPath)
        let dirs = targetDirs ?? discoverTargetClaudeConfigDirs(homeDir: homeDir, accounts: accounts)

        var installedDirs: [String] = []
        var hasUpstream = false

        for dir in dirs {
            let settingsURL = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
            guard let data = try? Data(contentsOf: settingsURL),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sl = root["statusLine"] as? [String: Any],
                  let cmd = sl["command"] as? String else {
                continue
            }
            let unwrapped = unwrapStatusLineCommand(cmd)
            if unwrapped.isWrapped {
                installedDirs.append(dir)
                if let orig = unwrapped.originalCommand, !orig.isEmpty {
                    hasUpstream = true
                }
            } else if !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasUpstream = true
            }
        }

        return ClaudeStatusLineStatus(
            scriptExists: scriptExists,
            installedDirs: installedDirs,
            discoveredDirs: dirs,
            hasUpstreamHooks: hasUpstream
        )
    }

    @discardableResult
    static func install(
        targetDirs: [String]? = nil,
        baseConfigDir: URL? = nil,
        homeDir: URL? = nil,
        accounts: [AIQuotaAccount]? = nil
    ) -> ClaudeStatusLineInstallResult {
        let fm = FileManager.default
        let rootDir = configRootURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
        let cacheDir = rateLimitsDirURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
        let backupsDir = backupsDirURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
        let scriptFile = scriptURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
        let dirs = targetDirs ?? discoverTargetClaudeConfigDirs(homeDir: homeDir, accounts: accounts)

        do {
            try ensureSecureDirectory(rootDir)
            try ensureSecureDirectory(cacheDir)
            try ensureSecureDirectory(backupsDir)
            let scriptData = Data(hookScriptSource(baseConfigDir: baseConfigDir, homeDir: homeDir).utf8)
            try writeDataAtomically(scriptData, to: scriptFile, permissions: 0o700)
        } catch {
            return ClaudeStatusLineInstallResult(
                installedDirs: [],
                failedDirs: dirs.map { ($0, error.localizedDescription) }
            )
        }

        var installed: [String] = []
        var failed: [(dir: String, error: String)] = []

        for dir in dirs {
            let normalizedDir = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath).standardizedFileURL.path
            let settingsURL = URL(fileURLWithPath: normalizedDir, isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
            do {
                var root: [String: Any] = [:]
                var rawExistingData: Data?
                if fm.fileExists(atPath: settingsURL.path) {
                    let data = try Data(contentsOf: settingsURL)
                    rawExistingData = data
                    let parsed = try JSONSerialization.jsonObject(with: data)
                    guard let dict = parsed as? [String: Any] else {
                        throw NSError(
                            domain: "ClaudeStatusLineSync",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "settings.json root is not a JSON object"]
                        )
                    }
                    root = dict
                }

                var statusLineDict = (root["statusLine"] as? [String: Any]) ?? [:]
                let existingCommand = statusLineDict["command"] as? String
                let wasAlreadyWrapped = existingCommand.map { unwrapStatusLineCommand($0).isWrapped } ?? false

                if !wasAlreadyWrapped, let backupBytes = rawExistingData {
                    let dirKey = cacheKey(forConfigDir: normalizedDir, homeDir: homeDir)
                    let backupURL = backupsDir.appendingPathComponent("\(dirKey)-settings.json.bak", isDirectory: false)
                    if !fm.fileExists(atPath: backupURL.path) {
                        try writeDataAtomically(backupBytes, to: backupURL, permissions: 0o600)
                    }
                }

                let wrappedCommand = wrapStatusLineCommand(
                    existingCommand: existingCommand,
                    settingsDirPath: normalizedDir,
                    scriptPath: scriptFile.path
                )
                statusLineDict["type"] = "command"
                statusLineDict["command"] = wrappedCommand
                root["statusLine"] = statusLineDict

                let encoded = try serializeSettingsJSON(root)
                try writeDataAtomically(encoded, to: settingsURL, permissions: 0o600)
                installed.append(normalizedDir)
            } catch {
                failed.append((normalizedDir, error.localizedDescription))
            }
        }

        return ClaudeStatusLineInstallResult(installedDirs: installed, failedDirs: failed)
    }

    @discardableResult
    static func uninstall(
        targetDirs: [String]? = nil,
        baseConfigDir: URL? = nil,
        homeDir: URL? = nil,
        accounts: [AIQuotaAccount]? = nil
    ) -> ClaudeStatusLineUninstallResult {
        let fm = FileManager.default
        let scriptFile = scriptURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
        let dirs = targetDirs ?? discoverTargetClaudeConfigDirs(homeDir: homeDir, accounts: accounts)

        var restored: [String] = []
        var failed: [(dir: String, error: String)] = []

        for dir in dirs {
            let normalizedDir = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath).standardizedFileURL.path
            let settingsURL = URL(fileURLWithPath: normalizedDir, isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
            guard fm.fileExists(atPath: settingsURL.path) else { continue }
            do {
                let data = try Data(contentsOf: settingsURL)
                let parsed = try JSONSerialization.jsonObject(with: data)
                guard var root = parsed as? [String: Any] else { continue }
                guard var sl = root["statusLine"] as? [String: Any],
                      let cmd = sl["command"] as? String else {
                    continue
                }
                let unwrapped = unwrapStatusLineCommand(cmd)
                guard unwrapped.isWrapped else { continue }

                if let orig = unwrapped.originalCommand {
                    sl["command"] = orig
                    root["statusLine"] = sl
                } else {
                    root.removeValue(forKey: "statusLine")
                }

                let encoded = try serializeSettingsJSON(root)
                try writeDataAtomically(encoded, to: settingsURL, permissions: 0o600)
                restored.append(normalizedDir)
            } catch {
                failed.append((normalizedDir, error.localizedDescription))
            }
        }

        if fm.fileExists(atPath: scriptFile.path) {
            try? fm.removeItem(at: scriptFile)
        }

        return ClaudeStatusLineUninstallResult(restoredDirs: restored, failedDirs: failed)
    }

    static func readCachedQuota(
        forAccount account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        baseConfigDir: URL? = nil,
        homeDir: URL? = nil,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard account.provider == .claude else { return nil }
        let svc = resolvedServiceName(forAccount: account)
        let key = cacheKey(forServiceName: svc)
        let fileURL = rateLimitsDirURL(baseConfigDir: baseConfigDir, homeDir: homeDir)
            .appendingPathComponent("\(key).json", isDirectory: false)

        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = root["rate_limits"] as? [String: Any] else {
            return nil
        }

        func numeric(_ raw: Any?) -> Double? {
            if let d = raw as? Double { return d.isFinite ? d : nil }
            if let i = raw as? Int { return Double(i) }
            if let n = raw as? NSNumber { return n.doubleValue }
            if let s = raw as? String, let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return d.isFinite ? d : nil
            }
            return nil
        }

        func parseFlexibleDate(_ raw: Any?) -> Date? {
            if let num = numeric(raw), num > 0 {
                let sec = num > 1_000_000_000_000 ? num / 1000.0 : num
                return Date(timeIntervalSince1970: sec)
            }
            if let str = raw as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = f1.date(from: trimmed) { return d }
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: trimmed)
            }
            return nil
        }

        let fiveObj = rateLimits["five_hour"] as? [String: Any]
        let sevenObj = rateLimits["seven_day"] as? [String: Any]

        var primaryRem: Double?
        var primaryReset: Date?
        if let fiveObj, let util = numeric(fiveObj["used_percentage"]) {
            primaryRem = max(0, min(100, 100.0 - util))
            primaryReset = parseFlexibleDate(fiveObj["resets_at"])
        }

        var secondaryRem: Double?
        var secondaryReset: Date?
        if let sevenObj, let util = numeric(sevenObj["used_percentage"]) {
            secondaryRem = max(0, min(100, 100.0 - util))
            secondaryReset = parseFlexibleDate(sevenObj["resets_at"])
        }

        guard primaryRem != nil || secondaryRem != nil else { return nil }

        let updatedAt: Date
        if let parsedUpdated = parseFlexibleDate(root["updated_at"]) {
            updatedAt = parsedUpdated
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let mdate = attrs[.modificationDate] as? Date {
            updatedAt = mdate
        } else {
            updatedAt = now
        }

        let resetDates = [primaryReset, secondaryReset].compactMap { $0 }
        let hasActiveWindow = resetDates.isEmpty || resetDates.contains { $0 > now }
        let state: AIQuotaStatusState = hasActiveWindow ? .live : .cached
        let statusMsg: String? = hasActiveWindow
            ? nil
            : LocalizationService.pick("周期已过 · 待使用 Claude 同步", "Cycle passed · Use Claude to sync")

        if primaryRem == nil, let sec = secondaryRem {
            return AIQuotaSnapshot(
                accountID: account.id,
                remainingPercent: sec,
                primaryWindowLabel: "7d",
                resetsAt: secondaryReset,
                secondaryRemainingPercent: nil,
                secondaryWindowLabel: nil,
                secondaryResetsAt: nil,
                accountEmail: existing?.accountEmail,
                planLabel: existing?.planLabel,
                state: state,
                statusMessage: statusMsg,
                updatedAt: updatedAt,
                accountUUID: existing?.accountUUID,
                accountDisplayName: existing?.accountDisplayName
            )
        }

        return AIQuotaSnapshot(
            accountID: account.id,
            remainingPercent: primaryRem,
            primaryWindowLabel: "5h",
            resetsAt: primaryReset,
            secondaryRemainingPercent: secondaryRem,
            secondaryWindowLabel: secondaryRem != nil ? "7d" : nil,
            secondaryResetsAt: secondaryReset,
            accountEmail: existing?.accountEmail,
            planLabel: existing?.planLabel,
            state: state,
            statusMessage: statusMsg,
            updatedAt: updatedAt,
            accountUUID: existing?.accountUUID,
            accountDisplayName: existing?.accountDisplayName
        )
    }

    private static func ensureSecureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: url.path)
    }

    private static func serializeSettingsJSON(_ root: [String: Any]) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }
        var data = try JSONSerialization.data(withJSONObject: root, options: options)
        data.append(0x0A)
        return data
    }

    private static func writeDataAtomically(_ data: Data, to targetURL: URL, permissions: Int) throws {
        let fm = FileManager.default
        let parentDir = targetURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let tempURL = parentDir.appendingPathComponent(".\(targetURL.lastPathComponent).tmp.\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: [.atomic])
            try fm.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: tempURL.path)
            if fm.fileExists(atPath: targetURL.path) {
                _ = try fm.replaceItemAt(targetURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: targetURL)
            }
            try? fm.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: targetURL.path)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }
}
