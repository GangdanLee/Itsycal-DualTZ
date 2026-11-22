//
//  AIQuotaEngine.swift
//  Itsycal DualTZ
//

import CommonCrypto
import Foundation
import LocalAuthentication
import Security
import SQLite3

private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // 严格仅对本机 127.0.0.1 探针放行自签名证书，公网域名一律执行系统默认校验证书流程
        if challenge.protectionSpace.host == "127.0.0.1",
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

enum CursorLocalAuthError: Error, Equatable {
    case databaseNotFound
    case sqliteError(String)
    case missingToken
    case safeStorageLocked
    case needsKeychainPermission(userCanceled: Bool)
    case invalidJWT
    case expired
}

final class AIQuotaEngine {
    static let shared = AIQuotaEngine()

    static let autoRefreshCooldown: TimeInterval = 300.0
    static let defaultRateLimitBackoff: TimeInterval = 600.0

    private let stateLock = NSLock()
    private var lastAutoRefreshAt: Date?
    private var rateLimitedUntil: [String: Date] = [:]
    private var isRefreshingAll = false
    private var refreshingAccountIDs = Set<String>()

    private let localhostDelegate = LocalhostTrustDelegate()
    private lazy var localhostSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4.0
        cfg.timeoutIntervalForResource = 6.0
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        return URLSession(configuration: cfg, delegate: localhostDelegate, delegateQueue: nil)
    }()

    private lazy var remoteSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12.0
        cfg.timeoutIntervalForResource = 15.0
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private init() {}

    var lastRefreshDate: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastAutoRefreshAt
    }

    var isBusy: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRefreshingAll || !refreshingAccountIDs.isEmpty
    }

    // MARK: - 节流与 429 冷却门控

    func isRateLimited(accountID: String, now: Date = Date()) -> Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let until = rateLimitedUntil[accountID] else { return nil }
        if until > now {
            return until
        }
        rateLimitedUntil.removeValue(forKey: accountID)
        return nil
    }

    func recordRateLimit(accountID: String, retryAfter: Date?, now: Date = Date()) -> Date {
        let fallback = now.addingTimeInterval(Self.defaultRateLimitBackoff)
        let until = retryAfter.map { max($0, now.addingTimeInterval(60.0)) } ?? fallback
        stateLock.lock()
        rateLimitedUntil[accountID] = until
        stateLock.unlock()
        return until
    }

    func clearRateLimit(accountID: String) {
        stateLock.lock()
        rateLimitedUntil.removeValue(forKey: accountID)
        stateLock.unlock()
    }

    static func parseRetryAfterHeader(_ headerValue: String?, now: Date = Date()) -> Date? {
        guard let raw = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw), seconds > 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw), date > now {
            return date
        }
        return nil
    }

    // MARK: - 统一调度刷新

    func refreshIfNeeded(interactive: Bool = false) {
        guard UserDefaults.standard.bool(forKey: kDualTZShowAIQuotaPool) else { return }
        if !interactive {
            stateLock.lock()
            let last = lastAutoRefreshAt
            stateLock.unlock()
            if let last, Date().timeIntervalSince(last) < Self.autoRefreshCooldown {
                return
            }
        }
        refreshAll(interactive: interactive)
    }

    func refreshAll(interactive: Bool, completion: (() -> Void)? = nil) {
        stateLock.lock()
        if isRefreshingAll {
            stateLock.unlock()
            if let completion {
                DispatchQueue.main.async { completion() }
            }
            return
        }
        isRefreshingAll = true
        lastAutoRefreshAt = Date()
        stateLock.unlock()

        let accounts = AIQuotaStore.loadAccounts().filter { $0.enabled }
        if accounts.isEmpty {
            stateLock.lock()
            isRefreshingAll = false
            stateLock.unlock()
            if let completion {
                DispatchQueue.main.async { completion() }
            }
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let existingSnapshots = AIQuotaStore.loadSnapshots()
            var updatedSnapshots = existingSnapshots

            let keychainAccounts = accounts.filter { $0.provider == .claude || $0.provider == .cursor }
            let otherAccounts = accounts.filter { $0.provider != .claude && $0.provider != .cursor }

            await withTaskGroup(of: [AIQuotaSnapshot].self) { group in
                for acc in otherAccounts {
                    let prev = existingSnapshots[acc.id]
                    group.addTask {
                        [await self.fetchSnapshot(for: acc, existing: prev, interactive: interactive)]
                    }
                }
                if !keychainAccounts.isEmpty {
                    group.addTask {
                        // 需要钥匙串授权的平台串行采集，防止叠弹密码框；取消一次后后续降级为静默
                        // 多 Claude 账号批量刷新禁止 CLI 自动唤醒，杜绝同 IP 多号同步心跳
                        let enabledClaudeCount = keychainAccounts.filter { $0.provider == .claude }.count
                        var seenClaudeCount = 0
                        var results: [AIQuotaSnapshot] = []
                        var allowInteractive = interactive
                        for acc in keychainAccounts {
                            let prev = existingSnapshots[acc.id]
                            let outcome: (snapshot: AIQuotaSnapshot, userCanceledKeychain: Bool)
                            if acc.provider == .claude {
                                if seenClaudeCount > 0 {
                                    let jitterNs = UInt64.random(in: 250_000_000...600_000_000)
                                    try? await Task.sleep(nanoseconds: jitterNs)
                                }
                                seenClaudeCount += 1
                                outcome = await self.fetchClaudeWithCancelFlag(
                                    account: acc,
                                    existing: prev,
                                    interactive: allowInteractive,
                                    allowCLIWakeup: allowInteractive && enabledClaudeCount == 1
                                )
                            } else {
                                outcome = await self.fetchCursorWithCancelFlag(
                                    account: acc,
                                    existing: prev,
                                    interactive: allowInteractive
                                )
                            }
                            if outcome.userCanceledKeychain {
                                allowInteractive = false
                            }
                            results.append(outcome.snapshot)
                        }
                        return results
                    }
                }
                for await batch in group {
                    for snap in batch {
                        updatedSnapshots[snap.accountID] = snap
                    }
                }
            }

            // 必须在主线程写入 UserDefaults，避免在后台线程触发主界面 KVO/AutoLayout 崩溃
            let finalSnapshots = updatedSnapshots
            await MainActor.run {
                AIQuotaStore.saveSnapshots(finalSnapshots)
            }

            self.finishRefreshingAll()

            if let completion {
                await MainActor.run { completion() }
            }
        }
    }

    private func finishRefreshingAll() {
        stateLock.lock()
        isRefreshingAll = false
        stateLock.unlock()
    }

    func refreshAccount(id: String, interactive: Bool, completion: ((AIQuotaSnapshot?) -> Void)? = nil) {
        guard let account = AIQuotaStore.loadAccounts().first(where: { $0.id == id }) else {
            if let completion {
                DispatchQueue.main.async { completion(nil) }
            }
            return
        }

        stateLock.lock()
        if refreshingAccountIDs.contains(id) {
            stateLock.unlock()
            return
        }
        refreshingAccountIDs.insert(id)
        stateLock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let existing = AIQuotaStore.loadSnapshots()[id]
            let snap = await self.fetchSnapshot(
                for: account,
                existing: existing,
                interactive: interactive,
                allowClaudeWakeup: interactive
            )
            await MainActor.run {
                AIQuotaStore.saveSnapshot(snap)
            }

            self.finishRefreshingAccount(id)

            if let completion {
                await MainActor.run { completion(snap) }
            }
        }
    }

    private func finishRefreshingAccount(_ id: String) {
        stateLock.lock()
        refreshingAccountIDs.remove(id)
        stateLock.unlock()
    }

    private func fetchSnapshot(
        for account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        interactive: Bool,
        allowClaudeWakeup: Bool = false
    ) async -> AIQuotaSnapshot {
        switch account.provider {
        case .claude:
            return await fetchClaude(
                account: account,
                existing: existing,
                interactive: interactive,
                allowCLIWakeup: allowClaudeWakeup
            )
        case .antigravity:
            return await fetchAntigravity(account: account, existing: existing)
        case .codex:
            return await fetchCodex(account: account, existing: existing)
        case .cursor:
            return await fetchCursorWithCancelFlag(account: account, existing: existing, interactive: interactive).snapshot
        }
    }

    // MARK: - 1. Claude OAuth 只读适配器

    private enum ClaudeCredentialLoadResult {
        case token(
            accessToken: String,
            expiresAt: Date?,
            hasRefreshToken: Bool,
            refreshTokenExpiresAt: Date?,
            subscriptionType: String?
        )
        case needsKeychainPermission(userCanceled: Bool)
        case needsLogin(String)
    }

    private func fetchClaude(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        interactive: Bool,
        allowCLIWakeup: Bool = false
    ) async -> AIQuotaSnapshot {
        await fetchClaudeWithCancelFlag(
            account: account,
            existing: existing,
            interactive: interactive,
            allowCLIWakeup: allowCLIWakeup
        ).snapshot
    }

    private func fetchClaudeWithCancelFlag(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        interactive: Bool,
        allowCLIWakeup: Bool = false,
        allowDelegatedRefresh: Bool = true
    ) async -> (snapshot: AIQuotaSnapshot, userCanceledKeychain: Bool) {
        if let blockedUntil = isRateLimited(accountID: account.id) {
            return (
                preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .rateLimited,
                    message: Self.rateLimitMessage(until: blockedUntil)
                ),
                false
            )
        }

        switch Self.loadClaudeCredentials(account: account, interactive: interactive) {
        case .needsKeychainPermission(let canceled):
            return (
                preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .needsKeychainPermission,
                    message: LocalizationService.pick("需要钥匙串授权 · 点此刷新允许", "Keychain access needed · Click Refresh")
                ),
                canceled
            )
        case .needsLogin(let msg):
            return (
                preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .needsLogin,
                    message: msg
                ),
                false
            )
        case .token(let accessToken, let expiresAt, let hasRefreshToken, let refreshTokenExpiresAt, let subType):
            if let expiresAt, Date() >= expiresAt {
                return await handleDormantOrExpiredClaude(
                    account: account,
                    existing: existing,
                    hasRefreshToken: hasRefreshToken,
                    refreshTokenExpiresAt: refreshTokenExpiresAt,
                    subscriptionType: subType,
                    allowCLIWakeup: allowCLIWakeup,
                    allowDelegatedRefresh: allowDelegatedRefresh
                )
            }

            guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
                return (
                    preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .unavailable,
                        message: "Invalid URL"
                    ),
                    false
                )
            }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 12
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("claude-code/2.1.327", forHTTPHeaderField: "User-Agent")

            do {
                let (data, resp) = try await remoteSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .unavailable,
                            message: LocalizationService.pick("网络响应异常", "Invalid response")
                        ),
                        false
                    )
                }

                switch http.statusCode {
                case 200:
                    clearRateLimit(accountID: account.id)
                    if var parsed = Self.parseClaudeUsageResponse(data: data, accountID: account.id, existing: existing) {
                        if parsed.planLabel == nil, let subType, !subType.isEmpty {
                            parsed.planLabel = subType
                        }
                        return (parsed, false)
                    }
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .unavailable,
                            message: LocalizationService.pick("额度数据解析失败", "Parse failed")
                        ),
                        false
                    )
                case 401, 403:
                    return await handleDormantOrExpiredClaude(
                        account: account,
                        existing: existing,
                        hasRefreshToken: hasRefreshToken,
                        refreshTokenExpiresAt: refreshTokenExpiresAt,
                        subscriptionType: subType,
                        allowCLIWakeup: allowCLIWakeup,
                        allowDelegatedRefresh: allowDelegatedRefresh
                    )
                case 429:
                    let retryHeader = http.value(forHTTPHeaderField: "Retry-After")
                    let retryDate = Self.parseRetryAfterHeader(retryHeader)
                    let until = recordRateLimit(accountID: account.id, retryAfter: retryDate)
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .rateLimited,
                            message: Self.rateLimitMessage(until: until)
                        ),
                        false
                    )
                default:
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .unavailable,
                            message: "HTTP \(http.statusCode)"
                        ),
                        false
                    )
                }
            } catch {
                return (
                    preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: existing?.remainingPercent != nil ? .cached : .unavailable,
                        message: LocalizationService.pick("网络请求失败", "Network error")
                    ),
                    false
                )
            }
        }
    }

    private static func loadClaudeCredentials(account: AIQuotaAccount, interactive: Bool) -> ClaudeCredentialLoadResult {
        let trimmedDir = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirURL: URL
        if trimmedDir.isEmpty {
            dirURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        } else {
            let expanded = NSString(string: trimmedDir).expandingTildeInPath
            dirURL = URL(fileURLWithPath: expanded, isDirectory: true)
        }

        // 若明文 .credentials.json 存在，优先只读读取
        let fileURL = dirURL.appendingPathComponent(".credentials.json", isDirectory: false)
        if let fileData = try? Data(contentsOf: fileURL),
           let parsed = parseClaudeCredentials(data: fileData) {
            return .token(
                accessToken: parsed.accessToken,
                expiresAt: parsed.expiresAt,
                hasRefreshToken: parsed.hasRefreshToken,
                refreshTokenExpiresAt: parsed.refreshTokenExpiresAt,
                subscriptionType: parsed.subscriptionType
            )
        }

        // 查询 macOS Keychain（后台/自动刷新强制静默，不弹窗打扰用户）
        let serviceName: String
        let explicitSvc = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitSvc.isEmpty {
            serviceName = explicitSvc
        } else {
            serviceName = AIQuotaStore.claudeKeychainServiceName(forConfigDir: trimmedDir)
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !interactive {
            let ctx = LAContext()
            ctx.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = ctx
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let parsed = parseClaudeCredentials(data: data) else {
                return .needsLogin(LocalizationService.pick("凭据格式异常 · 请重新登录 claude", "Invalid Claude credentials"))
            }
            return .token(
                accessToken: parsed.accessToken,
                expiresAt: parsed.expiresAt,
                hasRefreshToken: parsed.hasRefreshToken,
                refreshTokenExpiresAt: parsed.refreshTokenExpiresAt,
                subscriptionType: parsed.subscriptionType
            )
        case errSecInteractionNotAllowed:
            return .needsKeychainPermission(userCanceled: false)
        case errSecItemNotFound:
            return .needsLogin(LocalizationService.pick("未找到凭据 · 请先运行 claude 登录", "Not signed in · Run claude login"))
        case errSecUserCanceled:
            return .needsKeychainPermission(userCanceled: true)
        case errSecAuthFailed:
            return .needsKeychainPermission(userCanceled: false)
        default:
            return .needsLogin(LocalizationService.pick("钥匙串读取失败 (\(status))", "Keychain error (\(status))"))
        }
    }

    private static func parseCredentialDate(_ raw: Any?) -> Date? {
        if let num = raw as? Double {
            let seconds = num > 1_000_000_000_000 ? num / 1000.0 : num
            return Date(timeIntervalSince1970: seconds)
        }
        if let num = raw as? Int {
            let d = Double(num)
            let seconds = d > 1_000_000_000_000 ? d / 1000.0 : d
            return Date(timeIntervalSince1970: seconds)
        }
        if let str = raw as? String {
            return parseISO8601Date(str)
        }
        return nil
    }

    static func parseClaudeCredentials(data: Data) -> (
        accessToken: String,
        expiresAt: Date?,
        hasRefreshToken: Bool,
        refreshTokenExpiresAt: Date?,
        subscriptionType: String?
    )? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let rawToken = oauth["accessToken"] as? String else { return nil }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        let expiresAt = parseCredentialDate(oauth["expiresAt"])
        let rawRefresh = (oauth["refreshToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRefreshToken = (rawRefresh?.isEmpty == false)
        let refreshTokenExpiresAt = parseCredentialDate(oauth["refreshTokenExpiresAt"])
        let subType = (oauth["subscriptionType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token, expiresAt, hasRefreshToken, refreshTokenExpiresAt, subType)
    }

    static func parseClaudeUsageResponse(
        data: Data,
        accountID: String,
        existing: AIQuotaSnapshot?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let fiveHour = json["five_hour"] as? [String: Any]
        let sevenDay = json["seven_day"] as? [String: Any]

        var primaryRem: Double?
        var primaryReset: Date?
        if let fiveHour, let util = numericValue(fiveHour["utilization"]) {
            primaryRem = max(0, min(100, 100.0 - util))
            primaryReset = parseISO8601Date(fiveHour["resets_at"] as? String)
        }

        var secondaryRem: Double?
        var secondaryReset: Date?
        if let sevenDay, let util = numericValue(sevenDay["utilization"]) {
            secondaryRem = max(0, min(100, 100.0 - util))
            secondaryReset = parseISO8601Date(sevenDay["resets_at"] as? String)
        }

        // 若某些账户仅返回 seven_day 而无 five_hour，主环平滑回退显示 seven_day
        if primaryRem == nil, let sec = secondaryRem {
            return AIQuotaSnapshot(
                accountID: accountID,
                remainingPercent: sec,
                primaryWindowLabel: "7d",
                resetsAt: secondaryReset,
                secondaryRemainingPercent: nil,
                secondaryWindowLabel: nil,
                secondaryResetsAt: nil,
                accountEmail: existing?.accountEmail,
                planLabel: existing?.planLabel,
                state: .live,
                statusMessage: nil,
                updatedAt: now
            )
        }

        guard primaryRem != nil else { return nil }

        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: primaryRem,
            primaryWindowLabel: "5h",
            resetsAt: primaryReset,
            secondaryRemainingPercent: secondaryRem,
            secondaryWindowLabel: secondaryRem != nil ? "7d" : nil,
            secondaryResetsAt: secondaryReset,
            accountEmail: existing?.accountEmail,
            planLabel: existing?.planLabel,
            state: .live,
            statusMessage: nil,
            updatedAt: now
        )
    }

    private static func claudeDormantHintMessage() -> String {
        LocalizationService.pick(
            "休眠中 · 点单条 ↻ 唤醒或使用即同步",
            "Dormant · Click ↻ or use Claude"
        )
    }

    private func handleDormantOrExpiredClaude(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        hasRefreshToken: Bool,
        refreshTokenExpiresAt: Date?,
        subscriptionType: String?,
        allowCLIWakeup: Bool,
        allowDelegatedRefresh: Bool
    ) async -> (snapshot: AIQuotaSnapshot, userCanceledKeychain: Bool) {
        let isRefreshSessionValid = hasRefreshToken && (refreshTokenExpiresAt.map { Date() < $0 } ?? true)
        guard isRefreshSessionValid else {
            return (
                preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .needsLogin,
                    message: Self.claudeExpiredHintMessage(for: account)
                ),
                false
            )
        }

        if allowCLIWakeup && allowDelegatedRefresh {
            let refreshed = await Self.attemptClaudeCLIRefresh(account: account)
            if refreshed {
                return await fetchClaudeWithCancelFlag(
                    account: account,
                    existing: existing,
                    interactive: false,
                    allowCLIWakeup: false,
                    allowDelegatedRefresh: false
                )
            }
        }

        let localCached = Self.loadClaudeLocalCachedUsage(account: account, existing: existing)
        var bestSnapshot: AIQuotaSnapshot?
        if let local = localCached, let prev = existing, prev.remainingPercent != nil {
            bestSnapshot = (local.updatedAt >= prev.updatedAt) ? local : prev
        } else {
            bestSnapshot = localCached ?? existing
        }

        if var snap = bestSnapshot {
            snap.state = .cached
            snap.statusMessage = Self.claudeDormantHintMessage()
            if snap.planLabel == nil, let subscriptionType, !subscriptionType.isEmpty {
                snap.planLabel = subscriptionType
            }
            return (snap, false)
        }

        return (
            AIQuotaSnapshot(
                accountID: account.id,
                remainingPercent: nil,
                primaryWindowLabel: account.provider.defaultPrimaryWindowLabel,
                resetsAt: nil,
                secondaryRemainingPercent: nil,
                secondaryWindowLabel: nil,
                secondaryResetsAt: nil,
                accountEmail: existing?.accountEmail,
                planLabel: subscriptionType,
                state: .cached,
                statusMessage: Self.claudeDormantHintMessage(),
                updatedAt: Date()
            ),
            false
        )
    }

    private static func resolveClaudeStateJSONURL(for account: AIQuotaAccount) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let defaultClaudeDir = home.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL.path

        let trimmed = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitSvc = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDir: String?
        if !trimmed.isEmpty {
            resolvedDir = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).standardizedFileURL.path
        } else {
            resolvedDir = AIQuotaStore.resolveKnownClaudeConfigDir(forKeychainService: explicitSvc)
        }

        if let dir = resolvedDir, dir != defaultClaudeDir {
            let isolatedJSON = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(".claude.json", isDirectory: false)
            return fm.fileExists(atPath: isolatedJSON.path) ? isolatedJSON : nil
        }
        let defaultJSON = home.appendingPathComponent(".claude.json", isDirectory: false)
        return fm.fileExists(atPath: defaultJSON.path) ? defaultJSON : nil
    }

    /// 只读解析 Claude CLI 本地 ~/.claude.json 中的 cachedUsageUtilization 作为休眠兜底
    static func loadClaudeLocalCachedUsage(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let url = resolveClaudeStateJSONURL(for: account),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parseClaudeStateJSONCachedUsage(data: data, accountID: account.id, existing: existing, now: now)
    }

    static func parseClaudeStateJSONCachedUsage(
        data: Data,
        accountID: String,
        existing: AIQuotaSnapshot?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cached = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] as? [String: Any],
              let utilData = try? JSONSerialization.data(withJSONObject: utilization) else {
            return nil
        }
        let fetchedAt: Date
        if let ms = numericValue(cached["fetchedAtMs"]) {
            fetchedAt = Date(timeIntervalSince1970: ms > 1_000_000_000_000 ? ms / 1000.0 : ms)
        } else {
            fetchedAt = now
        }
        guard var snap = parseClaudeUsageResponse(data: utilData, accountID: accountID, existing: existing, now: fetchedAt) else {
            return nil
        }
        if snap.accountEmail == nil,
           let oa = root["oauthAccount"] as? [String: Any],
           let email = (oa["emailAddress"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            snap.accountEmail = email
        }
        snap.state = .cached
        snap.statusMessage = claudeDormantHintMessage()
        return snap
    }

    private static func claudeExpiredHintMessage(for account: AIQuotaAccount) -> String {
        let trimmedDir = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let svc = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDir.isEmpty && !svc.isEmpty && svc != AIQuotaStore.claudeKeychainPrefix {
            return LocalizationService.pick(
                "登录已过期 · 请填隔离目录或在终端重新登录",
                "Token expired · Set config dir or run claude login"
            )
        }
        return LocalizationService.pick("登录已过期 · 请在终端重新登录 claude", "Session expired · Run claude login")
    }

    /// 仅在单条按需点击时，通过官方 `claude doctor` 安全触发原生 OAuth 续期（不触碰其他账号，不弹浏览器）
    static func resolvedExistingClaudeConfigEnvDir(for account: AIQuotaAccount) -> (allowed: Bool, envDir: String?) {
        let trimmedDir = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let svc = account.keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default

        if !trimmedDir.isEmpty {
            let expanded = NSString(string: trimmedDir).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                // 隔离目录已被移除（如已删除目录或清理 Orca），跳过唤醒以免新建空目录
                return (false, nil)
            }
            return (true, expanded)
        }

        if !svc.isEmpty && svc != AIQuotaStore.claudeKeychainPrefix {
            if let resolvedDir = AIQuotaStore.resolveKnownClaudeConfigDir(forKeychainService: svc) {
                return (true, resolvedDir)
            }
            // 无法定位隔离目录时跳过唤醒，绝不误触默认主号
            return (false, nil)
        }

        return (true, nil)
    }

    private static func attemptClaudeCLIRefresh(account: AIQuotaAccount) async -> Bool {
        guard let claudePath = resolveExecutable(named: "claude", extraPaths: []) else {
            return false
        }
        let target = resolvedExistingClaudeConfigEnvDir(for: account)
        guard target.allowed else {
            return false
        }

        var env = ProcessInfo.processInfo.environment
        env["BROWSER"] = "/usr/bin/false"
        if let dir = target.envDir {
            env["CLAUDE_CONFIG_DIR"] = dir
        }

        _ = await runProcessAsync(
            executable: claudePath,
            arguments: ["doctor"],
            environment: env,
            currentDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            timeout: 10.0
        )
        try? await Task.sleep(nanoseconds: 350_000_000)
        return true
    }

    // MARK: - 2. Antigravity (Gemini) 2.x CLI 优先 + 本地探测 + 持久化离线兜底

    private func fetchAntigravity(account: AIQuotaAccount, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot {
        if let cliSnap = await Self.fetchAntigravityViaCLI(accountID: account.id, existing: existing) {
            return cliSnap
        }

        guard let psOutput = Self.runProcess(executable: "/bin/ps", arguments: ["-axo", "pid=,args="], timeout: 2.0) else {
            return Self.mergeAntigravityFallbackSnapshot(
                accountID: account.id,
                existing: existing,
                reason: LocalizationService.pick("Antigravity 未运行 · 显示上次缓存", "Antigravity offline · Cached")
            )
        }

        let procs = Self.parseAntigravityProcesses(psOutput)
        guard !procs.isEmpty else {
            return Self.mergeAntigravityFallbackSnapshot(
                accountID: account.id,
                existing: existing,
                reason: LocalizationService.pick("Antigravity 未运行 · 显示上次缓存", "Antigravity offline · Cached")
            )
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en"
            ]
        ]) else {
            return Self.mergeAntigravityFallbackSnapshot(
                accountID: account.id,
                existing: existing,
                reason: LocalizationService.pick("本地请求构建失败", "Request build error")
            )
        }

        for proc in procs {
            var ports: [Int] = []
            if let lsofOut = Self.runProcess(
                executable: "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(proc.pid)],
                timeout: 2.0
            ) {
                ports = Self.parseLsofListeningPorts(lsofOut)
            }
            if let extPort = proc.extPort, !ports.contains(extPort) {
                ports.append(extPort)
            }

            for port in ports {
                for scheme in ["https", "http"] {
                    guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
                        continue
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.httpBody = bodyData
                    req.timeoutInterval = 3.0
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")
                    req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                    if let csrf = proc.csrfToken, !csrf.isEmpty {
                        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
                    }

                    if let (data, resp) = try? await localhostSession.data(for: req),
                       let http = resp as? HTTPURLResponse,
                       http.statusCode == 200,
                       let snap = Self.parseAntigravityUserStatus(data: data, accountID: account.id) {
                        return snap
                    }
                }
            }
        }

        return Self.mergeAntigravityFallbackSnapshot(
            accountID: account.id,
            existing: existing,
            reason: LocalizationService.pick("Antigravity 离线或未响应 · 显示缓存", "Antigravity unreachable · Cached")
        )
    }

    private static func fetchAntigravityViaCLI(accountID: String, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot? {
        guard let agyPath = resolveExecutable(
            named: "agy",
            extraPaths: ["/Applications/Antigravity.app/Contents/Resources/app/bin/agy"]
        ) else {
            return nil
        }

        let probeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("itsycal-agy-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: probeDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: probeDir) }

        let stubData = Data("#!/bin/sh\nexit 1\n".utf8)
        for cmd in ["open", "xdg-open"] {
            let stubURL = probeDir.appendingPathComponent(cmd, isDirectory: false)
            _ = FileManager.default.createFile(
                atPath: stubURL.path,
                contents: stubData,
                attributes: [.posixPermissions: 0o700]
            )
        }

        var env = ProcessInfo.processInfo.environment
        let oldPath = env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = "\(probeDir.path):\(oldPath)"
        env["BROWSER"] = probeDir.appendingPathComponent("open").path

        guard let output = await runProcessAsync(
            executable: agyPath,
            arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "15s"],
            environment: env,
            timeout: 18.0
        ) else {
            return nil
        }

        guard let jsonData = extractJSONObjectData(from: output) else { return nil }
        return parseAntigravityCLIUsageJSON(data: jsonData, accountID: accountID, existing: existing)
    }

    static func parseAntigravityCLIUsageJSON(
        data: Data,
        accountID: String,
        existing: AIQuotaSnapshot?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? String) == "SUCCESS",
              let command = root["command"] as? [String: Any],
              (command["name"] as? String) == "usage",
              let cmdData = command["data"] as? [String: Any],
              let groups = cmdData["groups"] as? [[String: Any]],
              !groups.isEmpty else {
            return nil
        }

        let geminiGroup = groups.first(where: { (($0["name"] as? String) ?? "").lowercased().contains("gemini") }) ?? groups.first
        guard let geminiBuckets = geminiGroup?["buckets"] as? [[String: Any]] else { return nil }

        func pickBucket(in buckets: [[String: Any]], matchingWindow win: String) -> (pct: Double, reset: Date?)? {
            let matched = buckets.first { b in
                let w = ((b["window"] as? String) ?? "").lowercased()
                let id = ((b["id"] as? String) ?? "").lowercased()
                return w == win || id.contains(win)
            }
            guard let target = matched, let frac = numericValue(target["remaining_fraction"]) else { return nil }
            let pct = max(0, min(100, frac * 100.0))
            let reset = parseISO8601Date(target["reset_time"] as? String)
            return (pct, reset)
        }

        let fiveHour = pickBucket(in: geminiBuckets, matchingWindow: "5h")
        let weekly = pickBucket(in: geminiBuckets, matchingWindow: "weekly")
        let fallbackFirst = geminiBuckets.first(where: { numericValue($0["remaining_fraction"]) != nil }).flatMap { b -> (pct: Double, reset: Date?)? in
            guard let frac = numericValue(b["remaining_fraction"]) else { return nil }
            return (max(0, min(100, frac * 100.0)), parseISO8601Date(b["reset_time"] as? String))
        }

        guard let primary = fiveHour ?? weekly ?? fallbackFirst else { return nil }
        let primaryLabel = fiveHour != nil ? "Gemini 5h" : (weekly != nil ? "Gemini 7d" : "Gemini")
        let secondary = (fiveHour != nil) ? weekly : nil

        var thirdPartySummary: String? = existing?.planLabel
        if let threePGroup = groups.first(where: {
            let name = (($0["name"] as? String) ?? "").lowercased()
            return name.contains("claude") || name.contains("gpt")
        }), let buckets = threePGroup["buckets"] as? [[String: Any]] {
            let threeP = pickBucket(in: buckets, matchingWindow: "5h") ?? pickBucket(in: buckets, matchingWindow: "weekly")
            if let threeP {
                thirdPartySummary = "3P \(Int(round(threeP.pct)))%"
            }
        }

        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: primary.pct,
            primaryWindowLabel: primaryLabel,
            resetsAt: primary.reset,
            secondaryRemainingPercent: secondary?.pct,
            secondaryWindowLabel: secondary != nil ? "7d" : nil,
            secondaryResetsAt: secondary?.reset,
            accountEmail: existing?.accountEmail,
            planLabel: thirdPartySummary,
            state: .live,
            statusMessage: nil,
            updatedAt: now
        )
    }

    private static func extractJSONObjectData(from rawText: String) -> Data? {
        guard let start = rawText.firstIndex(of: "{"),
              let end = rawText.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return String(rawText[start...end]).data(using: .utf8)
    }

    static func parseAntigravityProcesses(_ psOutput: String) -> [(pid: Int, csrfToken: String?, extPort: Int?)] {
        var found: [(pid: Int, csrfToken: String?, extPort: Int?)] = []
        for rawLine in psOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard lower.contains("language_server"), lower.contains("antigravity") else { continue }

            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            let cmd = String(parts[1])

            let csrf = extractFlag("--csrf_token", from: cmd)
            let extPortStr = extractFlag("--extension_server_port", from: cmd)
            let extPort = extPortStr.flatMap { Int($0) }
            found.append((pid: pid, csrfToken: csrf, extPort: extPort))
        }
        return found
    }

    static func parseLsofListeningPorts(_ output: String) -> [Int] {
        var ports: [Int] = []
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return ports }
        let ns = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges >= 2 {
            let portStr = ns.substring(with: m.range(at: 1))
            if let port = Int(portStr), port > 0, port <= 65535, !ports.contains(port) {
                ports.append(port)
            }
        }
        return ports
    }

    static func parseAntigravityUserStatus(
        data: Data,
        accountID: String,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = root["userStatus"] as? [String: Any] else {
            return nil
        }

        let email = (userStatus["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tierName = ((userStatus["userTier"] as? [String: Any])?["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let planInfo = (userStatus["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any]
        let planDisplay = (planInfo?["planDisplayName"] as? String)
            ?? (planInfo?["displayName"] as? String)
            ?? (planInfo?["productName"] as? String)
            ?? tierName

        let modelData = userStatus["cascadeModelConfigData"] as? [String: Any]
        let configs = modelData?["clientModelConfigs"] as? [[String: Any]] ?? []

        var geminiBest: (pct: Double, reset: Date?)?
        var claudeGptBest: (pct: Double, reset: Date?)?
        var fallbackAny: (pct: Double, reset: Date?, label: String)?

        for cfg in configs {
            guard let quotaInfo = cfg["quotaInfo"] as? [String: Any],
                  let fraction = numericValue(quotaInfo["remainingFraction"]) else {
                continue
            }
            let pct = max(0, min(100, fraction * 100.0))
            let reset = parseISO8601Date(quotaInfo["resetTime"] as? String)

            let label = (cfg["label"] as? String) ?? ""
            let modelAlias = (cfg["modelOrAlias"] as? [String: Any])?["model"] as? String ?? ""
            let combined = "\(label) \(modelAlias)".lowercased()

            if fallbackAny == nil {
                fallbackAny = (pct, reset, label.isEmpty ? "Quota" : label)
            }

            if combined.contains("gemini") {
                if let cur = geminiBest {
                    if pct < cur.pct { geminiBest = (pct, reset ?? cur.reset) }
                } else {
                    geminiBest = (pct, reset)
                }
            } else if combined.contains("claude")
                        || combined.contains("gpt")
                        || combined.contains("opus")
                        || combined.contains("sonnet")
                        || combined.contains("o1")
                        || combined.contains("o3") {
                if let cur = claudeGptBest {
                    if pct < cur.pct { claudeGptBest = (pct, reset ?? cur.reset) }
                } else {
                    claudeGptBest = (pct, reset)
                }
            }
        }

        let primaryPct: Double?
        let primaryLabel: String
        let primaryReset: Date?
        let secondaryPct: Double?
        let secondaryLabel: String?
        let secondaryReset: Date?

        if let g = geminiBest {
            primaryPct = g.pct
            primaryLabel = "Gemini"
            primaryReset = g.reset
            secondaryPct = claudeGptBest?.pct
            secondaryLabel = claudeGptBest != nil ? "Claude/GPT" : nil
            secondaryReset = claudeGptBest?.reset
        } else if let c = claudeGptBest {
            primaryPct = c.pct
            primaryLabel = "Claude/GPT"
            primaryReset = c.reset
            secondaryPct = nil
            secondaryLabel = nil
            secondaryReset = nil
        } else if let fb = fallbackAny {
            primaryPct = fb.pct
            primaryLabel = fb.label
            primaryReset = fb.reset
            secondaryPct = nil
            secondaryLabel = nil
            secondaryReset = nil
        } else {
            return nil
        }

        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: primaryPct,
            primaryWindowLabel: primaryLabel,
            resetsAt: primaryReset,
            secondaryRemainingPercent: secondaryPct,
            secondaryWindowLabel: secondaryLabel,
            secondaryResetsAt: secondaryReset,
            accountEmail: email,
            planLabel: planDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
            state: .live,
            statusMessage: nil,
            updatedAt: now
        )
    }

    static func mergeAntigravityFallbackSnapshot(
        accountID: String,
        existing: AIQuotaSnapshot?,
        reason: String
    ) -> AIQuotaSnapshot {
        if var cached = existing,
           cached.remainingPercent != nil || cached.secondaryRemainingPercent != nil {
            cached.state = .cached
            cached.statusMessage = reason
            return cached
        }
        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: nil,
            primaryWindowLabel: "Gemini",
            resetsAt: nil,
            secondaryRemainingPercent: nil,
            secondaryWindowLabel: nil,
            secondaryResetsAt: nil,
            accountEmail: existing?.accountEmail,
            planLabel: existing?.planLabel,
            state: .unavailable,
            statusMessage: LocalizationService.pick("打开 Antigravity 后自动同步", "Open Antigravity to sync"),
            updatedAt: Date()
        )
    }

    // MARK: - 3. ChatGPT Codex 只读适配器

    private func fetchCodex(account: AIQuotaAccount, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot {
        if let blockedUntil = isRateLimited(accountID: account.id) {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .rateLimited,
                message: Self.rateLimitMessage(until: blockedUntil)
            )
        }

        let authURL = Self.codexAuthFileURL(configPath: account.configPath)
        guard let authData = try? Data(contentsOf: authURL) else {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .needsLogin,
                message: LocalizationService.pick("未找到 auth.json · 请运行 codex login", "Missing auth.json · Run codex login")
            )
        }

        guard let cred = Self.parseCodexAuthJSON(data: authData) else {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .needsLogin,
                message: LocalizationService.pick("Codex OAuth 凭据无效 · 请重新登录", "Invalid Codex auth.json")
            )
        }

        if let exp = cred.expiresAt, Date() >= exp {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .needsLogin,
                message: LocalizationService.pick("Codex 登录已过期 · 请运行 codex login", "Codex token expired")
            )
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(cred.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("ItsycalDualTZ/2.2", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = cred.accountID, !accountId.isEmpty {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, resp) = try await remoteSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid response")
            }
            switch http.statusCode {
            case 200:
                clearRateLimit(accountID: account.id)
                if let snap = Self.parseCodexUsage(data: data, accountID: account.id, email: cred.email) {
                    return snap
                }
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .unavailable,
                    message: LocalizationService.pick("Codex 额度解析失败", "Parse failed")
                )
            case 401, 403:
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .needsLogin,
                    message: LocalizationService.pick("Codex 登录已失效 · 请运行 codex login", "Codex unauthorized")
                )
            case 429:
                let retryDate = Self.parseRetryAfterHeader(http.value(forHTTPHeaderField: "Retry-After"))
                let until = recordRateLimit(accountID: account.id, retryAfter: retryDate)
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .rateLimited,
                    message: Self.rateLimitMessage(until: until)
                )
            default:
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .unavailable,
                    message: "HTTP \(http.statusCode)"
                )
            }
        } catch {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: existing?.remainingPercent != nil ? .cached : .unavailable,
                message: LocalizationService.pick("网络请求失败", "Network error")
            )
        }
    }

    private static func codexAuthFileURL(configPath: String) -> URL {
        let trimmed = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AIQuotaStore.defaultCodexAuthURL()
        }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        if expanded.hasSuffix(".json") {
            return URL(fileURLWithPath: expanded, isDirectory: false)
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).appendingPathComponent("auth.json", isDirectory: false)
    }

    static func parseCodexAuthJSON(data: Data) -> (accessToken: String, accountID: String?, email: String?, expiresAt: Date?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let rawAccess = tokens["access_token"] as? String else {
            return nil
        }
        let access = rawAccess.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !access.isEmpty else { return nil }

        let accountID = (tokens["account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let idToken = tokens["id_token"] as? String
        let idClaims = decodeJWTPayload(idToken)
        let accessClaims = decodeJWTPayload(access)
        let email = (idClaims?["email"] as? String) ?? (accessClaims?["email"] as? String)

        var expiresAt: Date?
        if let expNum = accessClaims?["exp"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expNum)
        }
        return (access, accountID, email, expiresAt)
    }

    static func parseCodexUsage(
        data: Data,
        accountID: String,
        email: String?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = json["rate_limit"] as? [String: Any] else {
            return nil
        }

        let planType = (json["plan_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = rateLimit["primary_window"] as? [String: Any]
        let secondary = rateLimit["secondary_window"] as? [String: Any]

        func parseWindow(_ w: [String: Any]?, defaultLabel: String) -> (rem: Double, label: String, reset: Date?)? {
            guard let w, let used = numericValue(w["used_percent"]) else { return nil }
            let rem = max(0, min(100, 100.0 - used))
            var reset: Date?
            if let ts = numericValue(w["reset_at"]) {
                reset = Date(timeIntervalSince1970: ts)
            }
            let secs = numericValue(w["limit_window_seconds"])
            let label: String
            if let secs {
                if secs <= 6 * 3600 {
                    label = "\(Int(round(secs / 3600)))h"
                } else if secs >= 6 * 86400 {
                    label = "\(Int(round(secs / 86400)))d"
                } else {
                    label = defaultLabel
                }
            } else {
                label = defaultLabel
            }
            return (rem, label, reset)
        }

        let pWin = parseWindow(primary, defaultLabel: "5h")
        let sWin = parseWindow(secondary, defaultLabel: "7d")
        guard pWin != nil || sWin != nil else { return nil }

        let mainWin = pWin ?? sWin!
        let subWin = pWin != nil ? sWin : nil

        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: mainWin.rem,
            primaryWindowLabel: mainWin.label,
            resetsAt: mainWin.reset,
            secondaryRemainingPercent: subWin?.rem,
            secondaryWindowLabel: subWin?.label,
            secondaryResetsAt: subWin?.reset,
            accountEmail: email,
            planLabel: planType?.capitalized,
            state: .live,
            statusMessage: nil,
            updatedAt: now
        )
    }

    // MARK: - 4. Cursor SQLite 只读 + Chromium Safe Storage AES 解密适配器

    private func fetchCursor(account: AIQuotaAccount, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot {
        await fetchCursorWithCancelFlag(account: account, existing: existing, interactive: false).snapshot
    }

    private func fetchCursorWithCancelFlag(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        interactive: Bool
    ) async -> (snapshot: AIQuotaSnapshot, userCanceledKeychain: Bool) {
        if let blockedUntil = isRateLimited(accountID: account.id) {
            return (
                preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .rateLimited,
                    message: Self.rateLimitMessage(until: blockedUntil)
                ),
                false
            )
        }

        let trimmedPath = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dbPath = trimmedPath.isEmpty
            ? AIQuotaStore.defaultCursorDBURL().path
            : NSString(string: trimmedPath).expandingTildeInPath

        let tokenRes = Self.readCursorAccessToken(dbPath: dbPath, interactive: interactive)
        switch tokenRes {
        case .failure(let err):
            var userCanceled = false
            let msg: String
            let state: AIQuotaStatusState
            switch err {
            case .databaseNotFound, .missingToken:
                state = .needsLogin
                msg = LocalizationService.pick("未检测到 Cursor 登录状态", "Cursor not signed in")
            case .expired:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 登录已过期 · 请打开 Cursor 刷新", "Cursor token expired")
            case .needsKeychainPermission(let canceled):
                userCanceled = canceled
                state = .needsKeychainPermission
                msg = LocalizationService.pick("需要 Cursor 钥匙串授权 · 点此刷新允许", "Cursor Keychain access needed · Refresh")
            case .safeStorageLocked:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 令牌无法解密 · 请打开 Cursor 重新登录", "Cursor Safe Storage unavailable")
            case .invalidJWT:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 令牌格式异常", "Invalid Cursor JWT")
            case .sqliteError(let detail):
                state = .unavailable
                msg = detail
            }
            return (preserveOrCreateErrorSnapshot(account: account, existing: existing, state: state, message: msg), userCanceled)

        case .success(let auth):
            guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
                return (preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid URL"), false)
            }

            let cookieHeader = Self.buildCursorCookieHeader(userID: auth.userID, accessToken: auth.accessToken)
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 12
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("ItsycalDualTZ/2.2", forHTTPHeaderField: "User-Agent")

            do {
                let (data, resp) = try await remoteSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    return (preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid response"), false)
                }
                switch http.statusCode {
                case 200:
                    clearRateLimit(accountID: account.id)
                    if let snap = Self.parseCursorUsageSummary(data: data, accountID: account.id, emailFallback: auth.email) {
                        return (snap, false)
                    }
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .unavailable,
                            message: LocalizationService.pick("Cursor 额度解析失败", "Parse failed")
                        ),
                        false
                    )
                case 401, 403:
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .needsLogin,
                            message: LocalizationService.pick("Cursor 会话失效 · 请重开 Cursor", "Cursor unauthorized")
                        ),
                        false
                    )
                case 429:
                    let retryDate = Self.parseRetryAfterHeader(http.value(forHTTPHeaderField: "Retry-After"))
                    let until = recordRateLimit(accountID: account.id, retryAfter: retryDate)
                    return (
                        preserveOrCreateErrorSnapshot(
                            account: account,
                            existing: existing,
                            state: .rateLimited,
                            message: Self.rateLimitMessage(until: until)
                        ),
                        false
                    )
                default:
                    return (preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "HTTP \(http.statusCode)"), false)
                }
            } catch {
                return (
                    preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: existing?.remainingPercent != nil ? .cached : .unavailable,
                        message: LocalizationService.pick("网络请求失败", "Network error")
                    ),
                    false
                )
            }
        }
    }

    static func readCursorAccessToken(
        dbPath: String,
        interactive: Bool = false,
        passwordOverride: String? = nil,
        now: Date = Date()
    ) -> Result<(accessToken: String, userID: String, email: String?, expiresAt: Date?), CursorLocalAuthError> {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return .failure(.databaseNotFound)
        }

        let walMissing = !FileManager.default.fileExists(atPath: dbPath + "-wal")
            && !FileManager.default.fileExists(atPath: dbPath + "-shm")

        let tokenValue: String?
        do {
            tokenValue = try queryCursorSQLite(dbPath: dbPath, immutable: false)
        } catch let err as CursorLocalAuthError {
            if case .sqliteError = err, walMissing {
                do {
                    tokenValue = try queryCursorSQLite(dbPath: dbPath, immutable: true)
                } catch let fallbackErr as CursorLocalAuthError {
                    return .failure(fallbackErr)
                } catch {
                    return .failure(.sqliteError(error.localizedDescription))
                }
            } else {
                return .failure(err)
            }
        } catch {
            return .failure(.sqliteError(error.localizedDescription))
        }

        guard let rawValue = tokenValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return .failure(.missingToken)
        }

        let rawToken: String
        let v1Prefix = "cursor-safe-storage:v1:"
        if rawValue.hasPrefix(v1Prefix) {
            let b64 = String(rawValue.dropFirst(v1Prefix.count))
            guard let encrypted = Data(base64Encoded: b64) else {
                return .failure(.safeStorageLocked)
            }
            let password: String
            if let passwordOverride {
                password = passwordOverride
            } else {
                switch loadCursorSafeStoragePassword(interactive: interactive) {
                case .success(let pwd):
                    password = pwd
                case .failure(let err):
                    return .failure(err)
                }
            }
            guard let decrypted = decryptChromiumSafeStorageV1(encryptedValue: encrypted, password: password) else {
                return .failure(.safeStorageLocked)
            }
            rawToken = decrypted
        } else if rawValue.hasPrefix("cursor-safe-storage:") {
            return .failure(.safeStorageLocked)
        } else {
            rawToken = rawValue
        }

        guard let claims = decodeJWTPayload(rawToken),
              let sub = claims["sub"] as? String else {
            return .failure(.invalidJWT)
        }
        let userID = sub.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        guard !userID.isEmpty else {
            return .failure(.invalidJWT)
        }

        var expiresAt: Date?
        if let expVal = numericValue(claims["exp"]) {
            expiresAt = Date(timeIntervalSince1970: expVal)
            if let expDate = expiresAt, now >= expDate {
                return .failure(.expired)
            }
        }

        let email = (claims["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success((rawToken, userID, email, expiresAt))
    }

    static func loadCursorSafeStoragePassword(interactive: Bool) -> Result<String, CursorLocalAuthError> {
        let candidates = ["Cursor Key", "Cursor"]
        var sawDenied = false
        var sawCanceled = false

        for accountName in candidates {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Cursor Safe Storage",
                kSecAttrAccount as String: accountName,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            if !interactive {
                let ctx = LAContext()
                ctx.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = ctx
            }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let pwd = String(data: data, encoding: .utf8), !pwd.isEmpty {
                return .success(pwd)
            }
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                sawDenied = true
            } else if status == errSecUserCanceled {
                sawCanceled = true
            }
        }

        if sawCanceled {
            return .failure(.needsKeychainPermission(userCanceled: true))
        }
        if sawDenied {
            return .failure(.needsKeychainPermission(userCanceled: false))
        }
        return .failure(.safeStorageLocked)
    }

    /// 使用 Chromium Safe Storage PBKDF2-HMAC-SHA1(1003, "saltysalt") + AES-128-CBC (IV=0x20*16) 解密 v10 令牌
    static func decryptChromiumSafeStorageV1(encryptedValue: Data, password: String) -> String? {
        guard encryptedValue.count > 3,
              String(data: encryptedValue.prefix(3), encoding: .utf8) == "v10" else {
            return nil
        }
        let ciphertext = Data(encryptedValue.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else {
            return nil
        }

        let salt = Data("saltysalt".utf8)
        var derivedKey = Data(count: kCCKeySizeAES128)
        let keyLen = derivedKey.count
        let kdfStatus = derivedKey.withUnsafeMutableBytes { keyBuf in
            password.utf8CString.withUnsafeBytes { passBuf in
                salt.withUnsafeBytes { saltBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBuf.bindMemory(to: Int8.self).baseAddress,
                        max(0, passBuf.count - 1),
                        saltBuf.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBuf.bindMemory(to: UInt8.self).baseAddress,
                        keyLen
                    )
                }
            }
        }
        guard kdfStatus == kCCSuccess else { return nil }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var decrypted = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outCap = decrypted.count
        var outMoved: size_t = 0
        let cryptStatus = decrypted.withUnsafeMutableBytes { outBuf in
            ciphertext.withUnsafeBytes { inBuf in
                derivedKey.withUnsafeBytes { keyBuf in
                    iv.withUnsafeBytes { ivBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress,
                            kCCKeySizeAES128,
                            ivBuf.baseAddress,
                            inBuf.baseAddress,
                            ciphertext.count,
                            outBuf.baseAddress,
                            outCap,
                            &outMoved
                        )
                    }
                }
            }
        }
        guard cryptStatus == kCCSuccess else { return nil }

        let plainData = Data(decrypted.prefix(outMoved))
        if let str = String(data: plainData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           decodeJWTPayload(str) != nil {
            return str
        }
        // 兼容部分版本在明文头部附带 32 字节校验前缀的场景
        if plainData.count > 32,
           let sliced = String(data: Data(plainData.dropFirst(32)), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           decodeJWTPayload(sliced) != nil {
            return sliced
        }
        return String(data: plainData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func queryCursorSQLite(dbPath: String, immutable: Bool) throws -> String? {
        var db: OpaquePointer?
        let fileURL = URL(fileURLWithPath: dbPath, isDirectory: false).absoluteURL
        let filename = immutable ? "\(fileURL.absoluteString)?immutable=1" : dbPath
        let flags = immutable ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_URI) : SQLITE_OPEN_READONLY

        let openRc = sqlite3_open_v2(filename, &db, flags, nil)
        guard openRc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed (\(openRc))"
            sqlite3_close(db)
            throw CursorLocalAuthError.sqliteError(msg)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite prepare failed"
            throw CursorLocalAuthError.sqliteError(msg)
        }
        defer { sqlite3_finalize(stmt) }

        let stepRc = sqlite3_step(stmt)
        if stepRc == SQLITE_DONE {
            return nil
        }
        guard stepRc == SQLITE_ROW else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite step failed"
            throw CursorLocalAuthError.sqliteError(msg)
        }

        switch sqlite3_column_type(stmt, 0) {
        case SQLITE_TEXT:
            guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
            return String(cString: cStr)
        case SQLITE_BLOB:
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: ptr, count: len)
            if data.count.isMultiple(of: 2),
               stride(from: 0, to: data.count, by: 2).allSatisfy({ (1..<128).contains(data[$0]) && data[$0 + 1] == 0 }),
               let utf16 = String(data: data, encoding: .utf16LittleEndian) {
                return utf16
            }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16LittleEndian)
        default:
            return nil
        }
    }

    static func buildCursorCookieHeader(userID: String, accessToken: String) -> String {
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }

    static func buildCursorCookieHeader(accessToken: String) -> String? {
        guard let claims = decodeJWTPayload(accessToken),
              let sub = claims["sub"] as? String else {
            return nil
        }
        let userID = sub.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        guard !userID.isEmpty else { return nil }
        return buildCursorCookieHeader(userID: userID, accessToken: accessToken)
    }

    static func parseCursorUsageSummary(
        data: Data,
        accountID: String,
        emailFallback: String?,
        now: Date = Date()
    ) -> AIQuotaSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let individual = json["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let overall = individual?["overall"] as? [String: Any]
        let team = json["teamUsage"] as? [String: Any]
        let pooled = team?["pooled"] as? [String: Any]

        var usedPercent: Double?
        if let total = numericValue(plan?["totalPercentUsed"]) {
            usedPercent = total
        } else {
            let autoPct = numericValue(plan?["autoPercentUsed"])
            let apiPct = numericValue(plan?["apiPercentUsed"])
            if let a = autoPct, let p = apiPct {
                usedPercent = (a + p) / 2.0
            } else if let p = apiPct {
                usedPercent = p
            } else if let a = autoPct {
                usedPercent = a
            } else if let used = numericValue(plan?["used"]),
                      let limit = numericValue(plan?["limit"]),
                      limit > 0 {
                usedPercent = (used / limit) * 100.0
            } else if let used = numericValue(overall?["used"]),
                      let limit = numericValue(overall?["limit"]),
                      limit > 0 {
                usedPercent = (used / limit) * 100.0
            } else if let used = numericValue(pooled?["used"]),
                      let limit = numericValue(pooled?["limit"]),
                      limit > 0 {
                usedPercent = (used / limit) * 100.0
            }
        }

        guard let used = usedPercent else { return nil }
        let rem = max(0, min(100, 100.0 - used))
        let cycleEnd = parseISO8601Date(json["billingCycleEnd"] as? String)
        let membership = (json["membershipType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AIQuotaSnapshot(
            accountID: accountID,
            remainingPercent: rem,
            primaryWindowLabel: "Plan",
            resetsAt: cycleEnd,
            secondaryRemainingPercent: nil,
            secondaryWindowLabel: nil,
            secondaryResetsAt: nil,
            accountEmail: emailFallback,
            planLabel: membership?.capitalized,
            state: .live,
            statusMessage: nil,
            updatedAt: now
        )
    }

    // MARK: - 通用解析与兜底辅助

    private func preserveOrCreateErrorSnapshot(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        state: AIQuotaStatusState,
        message: String
    ) -> AIQuotaSnapshot {
        if var prev = existing, prev.remainingPercent != nil || prev.secondaryRemainingPercent != nil {
            prev.state = state
            prev.statusMessage = message
            return prev
        }
        return AIQuotaSnapshot(
            accountID: account.id,
            remainingPercent: nil,
            primaryWindowLabel: account.provider.defaultPrimaryWindowLabel,
            resetsAt: nil,
            secondaryRemainingPercent: nil,
            secondaryWindowLabel: account.provider.defaultSecondaryWindowLabel,
            secondaryResetsAt: nil,
            accountEmail: existing?.accountEmail,
            planLabel: existing?.planLabel,
            state: state,
            statusMessage: message,
            updatedAt: Date()
        )
    }

    private static func rateLimitMessage(until: Date) -> String {
        let cal = TimeZoneService.gregorianCalendar(in: WorldClockStore.primaryTimeZone)
        let hm = cal.dateComponents([.hour, .minute], from: until)
        let hhmm = String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        return LocalizationService.pick("请求受限 · \(hhmm) 后再试", "Rate limited · Retry at \(hhmm)")
    }

    static func decodeJWTPayload(_ jwt: String?) -> [String: Any]? {
        guard let jwt else { return nil }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    static func parseISO8601Date(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    private static func numericValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d.isFinite ? d : nil }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String, let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return d.isFinite ? d : nil
        }
        return nil
    }

    private static func extractFlag(_ flag: String, from command: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: flag)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)(?:=|\\s+)(\\S+)") else { return nil }
        let ns = command as NSString
        guard let match = regex.firstMatch(in: command, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    static func resolveExecutable(named name: String, extraPaths: [String]) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        candidates.append(contentsOf: extraPaths.map { NSString(string: $0).expandingTildeInPath })
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
                candidates.append(URL(fileURLWithPath: String(dir), isDirectory: true).appendingPathComponent(name).path)
            }
        }
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func runProcessAsync(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let output = runProcess(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    currentDirectoryURL: currentDirectoryURL,
                    timeout: timeout
                )
                continuation.resume(returning: output)
            }
        }
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval
    ) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        if let environment {
            proc.environment = environment
        }
        if let currentDirectoryURL {
            proc.currentDirectoryURL = currentDirectoryURL
        }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in
            sem.signal()
        }

        do {
            try proc.run()
        } catch {
            return nil
        }

        let waitResult = sem.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            proc.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
