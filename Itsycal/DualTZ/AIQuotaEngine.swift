//
//  AIQuotaEngine.swift
//  Itsycal DualTZ
//

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

            await withTaskGroup(of: AIQuotaSnapshot.self) { group in
                for acc in accounts {
                    let prev = existingSnapshots[acc.id]
                    group.addTask {
                        await self.fetchSnapshot(for: acc, existing: prev, interactive: interactive)
                    }
                }
                for await snap in group {
                    updatedSnapshots[snap.accountID] = snap
                }
            }

            AIQuotaStore.saveSnapshots(updatedSnapshots)

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
            let snap = await self.fetchSnapshot(for: account, existing: existing, interactive: interactive)
            AIQuotaStore.saveSnapshot(snap)

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
        interactive: Bool
    ) async -> AIQuotaSnapshot {
        switch account.provider {
        case .claude:
            return await fetchClaude(account: account, existing: existing, interactive: interactive)
        case .antigravity:
            return await fetchAntigravity(account: account, existing: existing)
        case .codex:
            return await fetchCodex(account: account, existing: existing)
        case .cursor:
            return await fetchCursor(account: account, existing: existing)
        }
    }

    // MARK: - 1. Claude OAuth 只读适配器

    private enum ClaudeCredentialLoadResult {
        case token(accessToken: String, expiresAt: Date?, subscriptionType: String?)
        case needsKeychainPermission
        case needsLogin(String)
    }

    private func fetchClaude(
        account: AIQuotaAccount,
        existing: AIQuotaSnapshot?,
        interactive: Bool
    ) async -> AIQuotaSnapshot {
        if let blockedUntil = isRateLimited(accountID: account.id) {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .rateLimited,
                message: Self.rateLimitMessage(until: blockedUntil)
            )
        }

        switch Self.loadClaudeCredentials(account: account, interactive: interactive) {
        case .needsKeychainPermission:
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .needsKeychainPermission,
                message: LocalizationService.pick("需要钥匙串授权 · 点此刷新允许", "Keychain access needed · Click Refresh")
            )
        case .needsLogin(let msg):
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .needsLogin,
                message: msg
            )
        case .token(let accessToken, let expiresAt, let subType):
            if let expiresAt, Date() >= expiresAt {
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .needsLogin,
                    message: LocalizationService.pick("登录已过期 · 请在终端重新登录 claude", "Session expired · Run claude login")
                )
            }

            guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
                return preserveOrCreateErrorSnapshot(
                    account: account,
                    existing: existing,
                    state: .unavailable,
                    message: "Invalid URL"
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
            req.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, resp) = try await remoteSession.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    return preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .unavailable,
                        message: LocalizationService.pick("网络响应异常", "Invalid response")
                    )
                }

                switch http.statusCode {
                case 200:
                    clearRateLimit(accountID: account.id)
                    if var parsed = Self.parseClaudeUsageResponse(data: data, accountID: account.id, existing: existing) {
                        if parsed.planLabel == nil, let subType, !subType.isEmpty {
                            parsed.planLabel = subType
                        }
                        return parsed
                    }
                    return preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .unavailable,
                        message: LocalizationService.pick("额度数据解析失败", "Parse failed")
                    )
                case 401, 403:
                    return preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .needsLogin,
                        message: LocalizationService.pick("凭证已失效 · 请在终端重新登录 claude", "Unauthorized · Run claude login")
                    )
                case 429:
                    let retryHeader = http.value(forHTTPHeaderField: "Retry-After")
                    let retryDate = Self.parseRetryAfterHeader(retryHeader)
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
                subscriptionType: parsed.subscriptionType
            )
        case errSecInteractionNotAllowed:
            return .needsKeychainPermission
        case errSecItemNotFound:
            return .needsLogin(LocalizationService.pick("未找到凭据 · 请先运行 claude 登录", "Not signed in · Run claude login"))
        case errSecAuthFailed, errSecUserCanceled:
            return .needsKeychainPermission
        default:
            return .needsLogin(LocalizationService.pick("钥匙串读取失败 (\(status))", "Keychain error (\(status))"))
        }
    }

    static func parseClaudeCredentials(data: Data) -> (accessToken: String, expiresAt: Date?, subscriptionType: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let rawToken = oauth["accessToken"] as? String else { return nil }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        var expiresAt: Date?
        if let num = oauth["expiresAt"] as? Double {
            let seconds = num > 1_000_000_000_000 ? num / 1000.0 : num
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else if let str = oauth["expiresAt"] as? String {
            expiresAt = parseISO8601Date(str)
        }

        let subType = (oauth["subscriptionType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token, expiresAt, subType)
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

    // MARK: - 2. Antigravity (Gemini) 本地探测 + 持久化离线兜底适配器

    private func fetchAntigravity(account: AIQuotaAccount, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot {
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

    // MARK: - 4. Cursor SQLite 只读适配器

    private func fetchCursor(account: AIQuotaAccount, existing: AIQuotaSnapshot?) async -> AIQuotaSnapshot {
        if let blockedUntil = isRateLimited(accountID: account.id) {
            return preserveOrCreateErrorSnapshot(
                account: account,
                existing: existing,
                state: .rateLimited,
                message: Self.rateLimitMessage(until: blockedUntil)
            )
        }

        let trimmedPath = account.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dbPath = trimmedPath.isEmpty
            ? AIQuotaStore.defaultCursorDBURL().path
            : NSString(string: trimmedPath).expandingTildeInPath

        let tokenRes = Self.readCursorAccessToken(dbPath: dbPath)
        switch tokenRes {
        case .failure(let err):
            let msg: String
            let state: AIQuotaStatusState
            switch err {
            case .databaseNotFound, .missingToken:
                state = .needsLogin
                msg = LocalizationService.pick("未检测到 Cursor 登录状态", "Cursor not signed in")
            case .expired:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 登录已过期 · 请打开 Cursor 刷新", "Cursor token expired")
            case .safeStorageLocked:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 令牌已加密锁定 · 请从本地客户端登入", "Cursor Safe Storage locked")
            case .invalidJWT:
                state = .needsLogin
                msg = LocalizationService.pick("Cursor 令牌格式异常", "Invalid Cursor JWT")
            case .sqliteError(let detail):
                state = .unavailable
                msg = detail
            }
            return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: state, message: msg)

        case .success(let auth):
            guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
                return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid URL")
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
                    return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "Invalid response")
                }
                switch http.statusCode {
                case 200:
                    clearRateLimit(accountID: account.id)
                    if let snap = Self.parseCursorUsageSummary(data: data, accountID: account.id, emailFallback: auth.email) {
                        return snap
                    }
                    return preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .unavailable,
                        message: LocalizationService.pick("Cursor 额度解析失败", "Parse failed")
                    )
                case 401, 403:
                    return preserveOrCreateErrorSnapshot(
                        account: account,
                        existing: existing,
                        state: .needsLogin,
                        message: LocalizationService.pick("Cursor 会话失效 · 请重开 Cursor", "Cursor unauthorized")
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
                    return preserveOrCreateErrorSnapshot(account: account, existing: existing, state: .unavailable, message: "HTTP \(http.statusCode)")
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
    }

    static func readCursorAccessToken(
        dbPath: String,
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

        guard let rawToken = tokenValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawToken.isEmpty else {
            return .failure(.missingToken)
        }

        if rawToken.hasPrefix("cursor-safe-storage:") {
            return .failure(.safeStorageLocked)
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

    private static func runProcess(executable: String, arguments: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

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
