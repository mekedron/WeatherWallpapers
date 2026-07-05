import SwiftUI

extension Notification.Name {
    /// Posted after the weather statistics file is cleared or re-pruned, so
    /// the storage breakdown can refresh its sizes.
    static let weatherStatsDidChange = Notification.Name("weatherStatsDidChange")
}

/// Settings sections for the local weather statistics: a ranked bar list of
/// observed conditions, the "never observed" insight, and collection knobs.
struct WeatherStatsSection: View {
    @AppStorage(WeatherStatsSettings.enabledKey) private var collectStats = true
    @AppStorage(WeatherStatsSettings.samplesPerDayKey) private var samplesPerDay = WeatherStatsSettings.defaultSamplesPerDay
    @AppStorage(WeatherStatsSettings.retentionDaysKey) private var retentionDays = WeatherStatsSettings.defaultRetentionDays

    @State private var stats: WeatherStats?
    @State private var confirmingClear = false

    private var observed: [(condition: WeatherCondition, count: Int)] {
        guard let stats else { return [] }
        let totals = stats.conditionTotals()
        return totals
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                let order = WeatherCondition.allCases
                return (order.firstIndex(of: $0.key) ?? 0) < (order.firstIndex(of: $1.key) ?? 0)
            }
            .map { (condition: $0.key, count: $0.value) }
    }

    private var unobserved: [WeatherCondition] {
        let seen = Set(observed.map(\.condition))
        return WeatherCondition.allCases.filter { !seen.contains($0) }
    }

    var body: some View {
        Section {
            if let stats, !stats.isEmpty {
                summaryRow(stats)
                let total = stats.totalChecks
                let maxCount = observed.first?.count ?? 1
                ForEach(observed, id: \.condition) { entry in
                    ConditionBarRow(
                        condition: entry.condition,
                        count: entry.count,
                        totalChecks: total,
                        maxCount: maxCount
                    )
                }
                insightRows
            } else {
                Text("No weather checks recorded yet. Statistics build up as your Shortcuts automation asks for the current wallpaper.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Weather Statistics")
        } footer: {
            Text("Counted on this device each time a shortcut asks for the current wallpaper. Nothing leaves your device.")
        }

        Section {
            Toggle("Collect Statistics", isOn: $collectStats)
            Picker("Record", selection: $samplesPerDay) {
                Text("Every check").tag(0)
                Text("Up to 6 a day").tag(6)
                Text("Up to 3 a day").tag(3)
                Text("Once a day").tag(1)
            }
            Picker("Keep", selection: $retentionDays) {
                Text("1 Month").tag(30)
                Text("3 Months").tag(90)
                Text("6 Months").tag(180)
                Text("1 Year").tag(365)
                Text("2 Years").tag(730)
            }
            Button("Clear Statistics…", role: .destructive) {
                confirmingClear = true
            }
            .disabled(stats?.isEmpty ?? true)
            .confirmationDialog(
                "Clear Weather Statistics?",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                // Not "Clear": that key is taken by the weather condition ("Ясно").
                Button("Clear Statistics", role: .destructive) {
                    Task {
                        await WeatherStatsStore.shared.clear()
                        await reload()
                        NotificationCenter.default.post(name: .weatherStatsDidChange, object: nil)
                    }
                }
            } message: {
                Text("This removes the recorded weather history from this device. Wallpapers are not affected.")
            }
            // Anchored to an always-present row: modifiers directly on Section
            // don't reliably survive Form's section handling.
            .task { await reload() }
            .onChange(of: retentionDays) {
                Task {
                    await WeatherStatsStore.shared.applyRetention()
                    await reload()
                    NotificationCenter.default.post(name: .weatherStatsDidChange, object: nil)
                }
            }
        } footer: {
            Text("Capping the records keeps automations that check the weather many times a day from skewing the picture.")
        }
    }

    private func summaryRow(_ stats: WeatherStats) -> some View {
        LabeledContent {
            if let firstKey = stats.firstDayKey, let date = WeatherStatsStore.date(fromDayKey: firstKey) {
                Text("since \(date.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("\(stats.totalChecks) checks · \(stats.dayCount) days")
        }
    }

    @ViewBuilder
    private var insightRows: some View {
        if unobserved.isEmpty {
            Label("All 24 conditions have occurred at your location.", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            DisclosureGroup {
                Label("These never occurred at your location — you can skip generating them to save on API costs.", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(unobserved.map(\.localizedName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                LabeledContent("Never Observed") {
                    Text("\(unobserved.count) of \(WeatherCondition.allCases.count)")
                }
            }
        }
    }

    private func reload() async {
        stats = await WeatherStatsStore.shared.stats()
    }
}

/// One ranked row: condition name over a thin bar, share and count trailing.
/// Bars are scaled to the most frequent condition; labels carry the numbers.
private struct ConditionBarRow: View {
    let condition: WeatherCondition
    let count: Int
    let totalChecks: Int
    let maxCount: Int

    private var percentText: String {
        guard totalChecks > 0 else { return "0%" }
        let percent = Double(count) / Double(totalChecks) * 100
        return percent < 1 ? "<1%" : String(format: "%.0f%%", percent)
    }

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(percentText)
                    .monospacedDigit()
                Text("\(count)×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, alignment: .trailing)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text(condition.localizedName)
                } icon: {
                    Image(systemName: condition.symbolName)
                        .foregroundStyle(.tint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(max(maxCount, 1))))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
