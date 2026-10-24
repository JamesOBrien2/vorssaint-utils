// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SQLite3

/// Counts the free-model requests OpenCode makes today from its own local
/// database. The database is opened read-only, its sign-in tables are never
/// touched, and only each message's model, role and provider are extracted.
/// The count is local to this Mac, so it can differ from the account's tally.
enum AgentOpenCodeUsage {
    /// OpenCode starts a new free-model day at midnight UTC.
    static let windowMinutes = 24 * 60
    static let windowID = "opencode.free.daily"

    /// One UTC day of free-model requests.
    struct Daily: Equatable {
        let used: Int
        let resetsAt: Date

        func limits(observedAt: Date) -> AgentLimits {
            AgentLimits(provider: .opencode,
                        windows: [AgentLimitWindow(id: AgentOpenCodeUsage.windowID, kind: .daily,
                                                   minutes: AgentOpenCodeUsage.windowMinutes, scope: nil,
                                                   usedPercent: 0, resetsAt: resetsAt,
                                                   requests: used)],
                        observedAt: observedAt, source: .local)
        }
    }

    static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let data = environment["XDG_DATA_HOME"], !data.isEmpty {
            return URL(fileURLWithPath: data, isDirectory: true)
                .appending(path: "opencode/opencode.db")
        }
        return home.appending(path: ".local/share/opencode/opencode.db")
    }

    static func modelsURL(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let cache = environment["XDG_CACHE_HOME"], !cache.isEmpty {
            return URL(fileURLWithPath: cache, isDirectory: true)
                .appending(path: "opencode/models.json")
        }
        return home.appending(path: ".cache/opencode/models.json")
    }

    static func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        databaseURL(home: home, environment: environment).path.withCString {
            var info = stat()
            return stat($0, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
    }

    /// Nil when the database cannot be read right now; the caller keeps its
    /// last reading in that case.
    static func daily(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      now: Date = Date(),
                      environment: [String: String] = ProcessInfo.processInfo.environment) -> Daily? {
        let database = databaseURL(home: home, environment: environment)
        guard isInstalled(home: home, environment: environment) else { return nil }
        let (start, end) = utcDay(containing: now)
        guard let counts = modelCounts(at: database, from: start, to: end) else { return nil }
        let free = freeModelIDs(home: home, environment: environment)
        let used = counts.reduce(0) { total, entry in
            let name = entry.key.lowercased()
            let isFree = free.contains(entry.key) || name.hasSuffix("-free")
            return total + (isFree ? entry.value : 0)
        }
        return Daily(used: used, resetsAt: end)
    }

    /// The UTC day boundary OpenCode uses, wherever the Mac is.
    static func utcDay(containing date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    // MARK: Database

    private static func modelCounts(at url: URL, from start: Date, to end: Date) -> [String: Int]? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)
        let sql = """
            SELECT json_extract(data, '$.modelID'), COUNT(*)
            FROM message
            WHERE time_created >= ? AND time_created < ?
              AND json_extract(data, '$.role') = 'assistant'
              AND json_extract(data, '$.providerID') = 'opencode'
            GROUP BY 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, milliseconds(start))
        sqlite3_bind_int64(statement, 2, milliseconds(end))
        var counts: [String: Int] = [:]
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                counts[String(cString: value), default: 0] += Int(sqlite3_column_int64(statement, 1))
            }
            result = sqlite3_step(statement)
        }
        return result == SQLITE_DONE ? counts : nil
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    // MARK: Free models

    private struct ModelCache: Decodable {
        struct Provider: Decodable {
            let models: [String: Model]?
        }

        struct Model: Decodable {
            struct Cost: Decodable {
                let input: Double?
                let output: Double?
            }

            let cost: Cost?
        }
    }

    private struct FreeModels {
        let path: String
        let modified: Date?
        let ids: Set<String>
    }

    private static let cacheLock = NSLock()
    private static var cache: FreeModels?

    /// Models the public catalogue lists at no cost. The `-free` suffix is
    /// still checked, since a newly released model can be missing here.
    static func freeModelIDs(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> Set<String> {
        let url = modelsURL(home: home, environment: environment)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return cacheLock.withLock {
            if let cache, cache.path == url.path, cache.modified == modified { return cache.ids }
            let ids = readFreeModels(at: url)
            cache = FreeModels(path: url.path, modified: modified, ids: ids)
            return ids
        }
    }

    private static func readFreeModels(at url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let catalogue = try? JSONDecoder().decode([String: ModelCache.Provider].self, from: data),
              let provider = catalogue["opencode"] else { return [] }
        return Set((provider.models ?? [:]).compactMap { name, model in
            guard let cost = model.cost, cost.input == 0, cost.output == 0 else { return nil }
            return name
        })
    }
}
