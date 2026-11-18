//
//  ChinaHolidayStore.swift
//  Itsycal DualTZ
//

import Foundation

struct ChinaHolidayEntry: Codable {
    let date: String
    let name: String
    let isOffDay: Bool
}

private struct ChinaHolidayFile: Codable {
    let days: [ChinaHolidayEntry]
}

enum HolidayStoreError: LocalizedError {
    case invalidSchema(String)
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidSchema(let msg), .networkFailure(let msg):
            return msg
        }
    }
}

extension Notification.Name {
    static let dualTZHolidaysDidChange = Notification.Name("DualTZHolidaysDidChangeNotification")
}

final class ChinaHolidayStore {
    static let shared = ChinaHolidayStore()

    private var entriesByDate: [String: ChinaHolidayEntry] = [:]
    private var customEntriesByDate: [String: ChinaHolidayEntry] = [:]
    private let lock = NSLock()

    private static let validDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZoneService.beijingTZ
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.isLenient = false
        return fmt
    }()

    private init() {
        reloadAll()
    }

    func reloadAll() {
        var merged: [String: ChinaHolidayEntry] = [:]
        if let url = Bundle.main.url(forResource: "BundledChinaHolidays", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? Self.parseAndValidate(data: data) {
            merged.merge(bundled) { _, new in new }
        }
        var loadedCustom: [String: ChinaHolidayEntry] = [:]
        if let customURL = Self.customFileURL(),
           let data = try? Data(contentsOf: customURL),
           let custom = try? Self.parseAndValidate(data: data) {
            loadedCustom = custom
            merged.merge(custom) { _, new in new }
        }
        lock.lock()
        entriesByDate = merged
        customEntriesByDate = loadedCustom
        lock.unlock()
    }

    func entry(forDateKey dateKey: String) -> ChinaHolidayEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entriesByDate[dateKey]
    }

    func statusSummary() -> String {
        lock.lock()
        let total = entriesByDate.count
        let customCount = customEntriesByDate.count
        lock.unlock()
        if customCount > 0 {
            return LocalizationService.pick(
                "已加载 \(total) 条节假日/调休记录（含 \(customCount) 条更新覆盖）",
                "Loaded \(total) holiday/workday entries (\(customCount) custom overrides)"
            )
        }
        return LocalizationService.pick(
            "已内置 2025–2027 年共 \(total) 条国务院放假与调休记录",
            "Bundled \(total) China 2025–2027 official holiday & makeup-workday entries"
        )
    }

    static func displayName(_ rawName: String) -> String {
        guard !LocalizationService.isChinese else { return rawName }
        let map: [String: String] = [
            "元旦": "New Year's Day",
            "春节": "Spring Festival",
            "清明节": "Qingming Festival",
            "劳动节": "Labor Day",
            "端午节": "Dragon Boat Festival",
            "中秋节": "Mid-Autumn Festival",
            "国庆节": "National Day"
        ]
        return map[rawName] ?? rawName
    }

    @discardableResult
    static func parseAndValidate(data: Data) throws -> [String: ChinaHolidayEntry] {
        let decoded: ChinaHolidayFile
        do {
            decoded = try JSONDecoder().decode(ChinaHolidayFile.self, from: data)
        } catch {
            throw HolidayStoreError.invalidSchema("JSON 格式不合法或缺少 days 字段")
        }
        guard !decoded.days.isEmpty else {
            throw HolidayStoreError.invalidSchema("节假日数据为空，已保留原有记录")
        }
        var map: [String: ChinaHolidayEntry] = [:]
        for item in decoded.days {
            let cleanName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty,
                  item.date.count == 10,
                  validDateFormatter.date(from: item.date) != nil else {
                throw HolidayStoreError.invalidSchema("存在无效日期或节日名称：\(item.date)")
            }
            map[item.date] = ChinaHolidayEntry(date: item.date, name: cleanName, isOffDay: item.isOffDay)
        }
        return map
    }

    @discardableResult
    func importLocalFile(url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let parsed = try Self.parseAndValidate(data: data)
        try mergeAndPersistCustom(parsed)
        return parsed.count
    }

    func syncOnline(year: Int, completion: @escaping (Result<Int, Error>) -> Void) {
        let urlStr = "https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json"
        guard let url = URL(string: urlStr) else {
            completion(.failure(HolidayStoreError.networkFailure("无效的同步地址")))
            return
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        let session = URLSession(configuration: cfg)
        session.dataTask(with: url) { [weak self] data, response, error in
            self?.handleNetworkResponse(data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    private func handleNetworkResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if let error = error {
            DispatchQueue.main.async {
                completion(.failure(HolidayStoreError.networkFailure("网络请求失败：\(error.localizedDescription)")))
            }
            return
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            DispatchQueue.main.async {
                completion(.failure(HolidayStoreError.networkFailure("远端返回 HTTP \(http.statusCode)，可能尚未发布该年份调休")))
            }
            return
        }
        guard let data = data else {
            DispatchQueue.main.async {
                completion(.failure(HolidayStoreError.networkFailure("服务器未返回数据")))
            }
            return
        }
        do {
            let parsed = try Self.parseAndValidate(data: data)
            try mergeAndPersistCustom(parsed)
            DispatchQueue.main.async { completion(.success(parsed.count)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    private func mergeAndPersistCustom(_ newEntries: [String: ChinaHolidayEntry]) throws {
        lock.lock()
        var nextCustom = customEntriesByDate
        nextCustom.merge(newEntries) { _, new in new }
        var nextAll = entriesByDate
        nextAll.merge(newEntries) { _, new in new }
        let sortedList = nextCustom.values.sorted { $0.date < $1.date }
        let encoded = try JSONEncoder().encode(ChinaHolidayFile(days: sortedList))
        if let url = Self.customFileURL() {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: .atomic)
        }
        customEntriesByDate = nextCustom
        entriesByDate = nextAll
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dualTZHolidaysDidChange, object: nil)
        }
    }

    private static func customFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.morgan.ItsycalDualTZ"
        return support
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("custom_china_holidays.json", isDirectory: false)
    }
}
