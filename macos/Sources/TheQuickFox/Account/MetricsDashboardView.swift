//
//  MetricsDashboardView.swift
//  TheQuickFox
//
//  SwiftUI view for displaying user analytics and usage metrics
//

import SwiftUI
import Charts

struct MetricsDashboardView: View {
    @ObservedObject private var store = AppStore.shared
    @State private var selectedTimeRange: String = "30d"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Your Statistics")
                            .font(.system(size: 28, weight: .bold))
                        Text("Track your productivity and progress")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Time range picker
                    Picker("Time Range", selection: $selectedTimeRange) {
                        Text("7 Days").tag("7d")
                        Text("30 Days").tag("30d")
                        Text("All Time").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    .onChange(of: selectedTimeRange) { newValue in
                        store.dispatch(.metrics(.startFetch(timeRange: newValue)))
                    }
                }
                .padding()

                if store.state.metrics.isLoading {
                    Spacer()
                    ProgressView("Loading your stats...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                } else if let data = store.state.metrics.data {
                    // Hero Stats Cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(
                            icon: "chart.bar.fill",
                            title: "Total Queries",
                            value: "\(data.totalQueries)",
                            color: .blue
                        )

                        StatCard(
                            icon: "clock.fill",
                            title: "Time Saved",
                            value: formatTimeSaved(minutes: data.timeSavedMinutes),
                            subtitle: "\(data.timeSavedMinutes) minutes",
                            color: .green
                        )

                        StatCard(
                            icon: "flame.fill",
                            title: "Current Streak",
                            value: "\(data.currentStreak) days",
                            subtitle: "Best: \(data.longestStreak) days",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)

                    // Queries by Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Queries by Mode")
                            .font(.system(size: 18, weight: .semibold))

                        if #available(macOS 13.0, *) {
                            ModeBreakdownChart(data: data.queriesByMode)
                                .frame(height: 200)
                        } else {
                            ModeBreakdownLegacy(data: data.queriesByMode)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Top Apps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Most Used Apps")
                            .font(.system(size: 18, weight: .semibold))

                        if data.topApps.isEmpty {
                            Text("No app usage data yet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(data.topApps) { app in
                                HStack {
                                    Text(app.appName)
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Text("\(app.count) queries")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Activity Trend
                    if !data.dailyUsage.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity Trend")
                                .font(.system(size: 18, weight: .semibold))

                            if #available(macOS 13.0, *) {
                                ActivityTrendChart(data: data.dailyUsage)
                                    .frame(height: 200)
                            } else {
                                Text("Charts require macOS 13+")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No statistics available yet")
                            .font(.system(size: 16, weight: .medium))
                        Text("Start using TheQuickFox to see your stats here")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Fetch metrics when view appears
            store.dispatch(.metrics(.startFetch(timeRange: selectedTimeRange)))
        }
    }

    private func formatTimeSaved(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 24))
                Spacer()
            }

            Text(value)
                .font(.system(size: 32, weight: .bold))

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Mode Breakdown Chart (macOS 13+)

@available(macOS 13.0, *)
struct ModeBreakdownChart: View {
    let data: [String: Int]

    var body: some View {
        let chartData = data.map { (mode: $0.key.capitalized, count: $0.value) }
            .sorted { $0.count > $1.count }

        Chart(chartData, id: \.mode) { item in
            BarMark(
                x: .value("Count", item.count),
                y: .value("Mode", item.mode)
            )
            .foregroundStyle(by: .value("Mode", item.mode))
        }
        .padding()
    }
}

// MARK: - Mode Breakdown Legacy (macOS 12)

struct ModeBreakdownLegacy: View {
    let data: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(data.sorted(by: { $0.value > $1.value }), id: \.key) { mode, count in
                HStack {
                    Text(mode.capitalized)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Activity Trend Chart (macOS 13+)

@available(macOS 13.0, *)
struct ActivityTrendChart: View {
    let data: [DailyUsage]

    var body: some View {
        Chart(data) { item in
            LineMark(
                x: .value("Date", item.date),
                y: .value("Queries", item.count)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Date", item.date),
                y: .value("Queries", item.count)
            )
            .foregroundStyle(.blue.opacity(0.2))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
        .padding()
    }
}
