import Foundation
import os

/// Aggregated history of weather checks: for each local calendar day, how many
/// times each condition was observed. Lives in one compact JSON file in
/// Application Support — local to this device, never synced, never uploaded.
struct WeatherStats: Codable {
    /// "2026-07-03" → condition rawValue → number of checks that resolved to it.
    /// Day keys sort lexicographically, so string comparison is date comparison.
    var days: [String: [String: Int]] = [:]
    /// When the last sample was recorded — drives the samples-per-day cap.
    var lastRecordedAt: Date?

    var isEmpty: Bool { days.isEmpty }
    var dayCount: Int { days.count }
    var firstDayKey: String? { days.keys.min() }

    var totalChecks: Int {
        days.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    /// Checks per condition across all days. Raw values that no longer map to
    /// a known condition (written by a newer app version) are dropped.
    func conditionTotals() -> [WeatherCondition: Int] {
        var totals: [WeatherCondition: Int] = [:]
        for day in days.values {
            for (raw, count) in day {
                guard let condition = WeatherCondition(rawValue: raw) else { continue }
                totals[condition, default: 0] += count
            }
        }
        return totals
    }

    /// Number of days a condition was observed at least once.
    func dayCounts() -> [WeatherCondition: Int] {
        var counts: [WeatherCondition: Int] = [:]
        for day in days.values {
            for raw in day.keys {
                guard let condition = WeatherCondition(rawValue: raw) else { continue }
                counts[condition, default: 0] += 1
            }
        }
        return counts
    }
}

/// UserDefaults-backed knobs for the collection, shared by the store (reads)
/// and the Settings UI (@AppStorage with the same keys and defaults).
enum WeatherStatsSettings {
    static let enabledKey = "weatherStatsEnabled"
    static let samplesPerDayKey = "weatherStatsSamplesPerDay"
    static let retentionDaysKey = "weatherStatsRetentionDays"

    /// 0 means "record every check".
    static let defaultSamplesPerDay = 3
    static let defaultRetentionDays = 365

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var samplesPerDay: Int {
        UserDefaults.standard.object(forKey: samplesPerDayKey) as? Int ?? defaultSamplesPerDay
    }

    static var retentionDays: Int {
        UserDefaults.standard.object(forKey: retentionDaysKey) as? Int ?? defaultRetentionDays
    }
}

/// Serializes reads and writes of `weather-stats.json` across the app UI and
/// the Shortcuts intent (which can run concurrently in the same process).
actor WeatherStatsStore {
    static let shared = WeatherStatsStore()
    static let fileName = "weather-stats.json"

    private let logger = Logger(subsystem: "com.mekedron.WeatherWallpapers", category: "weather-stats")
    private var cached: WeatherStats?

    /// `Application Support/weather-stats.json`, creating the directory on first use.
    static func fileURL() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(fileName)
    }

    /// Counts one weather check, honoring the collection toggle, the
    /// samples-per-day cap and the retention window.
    func record(_ condition: WeatherCondition, at date: Date = Date()) {
        guard WeatherStatsSettings.isEnabled else { return }

        var stats = load()
        let day = Self.dayKey(for: date)
        let cap = WeatherStatsSettings.samplesPerDay
        if cap > 0 {
            // Spacing keeps the samples spread across the day instead of
            // burning the whole cap on a burst of morning automations. The
            // 0.9 tolerance forgives scheduling jitter of periodic checks.
            let minInterval = 86_400.0 / Double(cap) * 0.9
            if let last = stats.lastRecordedAt, date.timeIntervalSince(last) < minInterval {
                return
            }
            let samplesToday = stats.days[day]?.values.reduce(0, +) ?? 0
            if samplesToday >= cap { return }
        }

        stats.days[day, default: [:]][condition.rawValue, default: 0] += 1
        stats.lastRecordedAt = date
        prune(&stats, now: date)
        save(stats)
        logger.info("Recorded \(condition.rawValue, privacy: .public) for \(day, privacy: .public)")
    }

    /// Current stats, pruned to the retention window (persisting the prune).
    func stats() -> WeatherStats {
        var stats = load()
        if prune(&stats, now: Date()) {
            save(stats)
        }
        return stats
    }

    /// Applies the current retention setting immediately (Settings picker).
    func applyRetention() {
        _ = stats()
    }

    func clear() {
        cached = WeatherStats()
        try? FileManager.default.removeItem(at: Self.fileURL())
        logger.info("Statistics cleared")
    }

    func fileSizeBytes() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: Self.fileURL().path)[.size] as? Int) ?? 0
    }

    // MARK: - Internals

    private func load() -> WeatherStats {
        if let cached { return cached }
        var stats = WeatherStats()
        if let data = try? Data(contentsOf: Self.fileURL()) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(WeatherStats.self, from: data) {
                stats = decoded
            } else {
                logger.error("Corrupt stats file, starting over")
            }
        }
        cached = stats
        return stats
    }

    private func save(_ stats: WeatherStats) {
        cached = stats
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(stats)
            try data.write(to: Self.fileURL(), options: .atomic)
        } catch {
            logger.error("Saving stats failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops days older than the retention window. Returns true if anything changed.
    @discardableResult
    private func prune(_ stats: inout WeatherStats, now: Date) -> Bool {
        let days = max(1, WeatherStatsSettings.retentionDays)
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: now) else { return false }
        let cutoff = Self.dayKey(for: cutoffDate)
        let before = stats.days.count
        stats.days = stats.days.filter { $0.key >= cutoff }
        return stats.days.count != before
    }

    /// "2026-07-03" in the user's current calendar and time zone.
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parses a day key back into a Date (start of day, current time zone).
    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }
}
