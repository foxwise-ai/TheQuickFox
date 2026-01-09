//
//  MetricsCelebrationView.swift
//  TheQuickFox
//
//  SwiftUI view for displaying success metrics celebration in the HUD
//

import SwiftUI

struct MetricsCelebrationView: View {
    let data: AnalyticsData
    @State private var showContent = false
    @State private var showParticles = false
    @State private var countdownProgress: Double = 1.0
    @State private var timer: Timer?

    var onDismiss: (() -> Void)?
    var countdownDuration: TimeInterval = 10.0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Dismiss button with countdown indicator in top-right corner
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        // Countdown circle background
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                            .frame(width: 32, height: 32)

                        // Countdown progress
                        Circle()
                            .trim(from: 0, to: countdownProgress)
                            .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: countdownProgress)

                        // X button
                        Button(action: {
                            stopTimer()
                            onDismiss?()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
                Spacer()
            }

            VStack(spacing: 16) {
                // Celebration Icon
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)

                // Main message
                VStack(spacing: 4) {
                    Text("Great Work!")
                        .font(.system(size: 24, weight: .bold))

                    Text("Here's your progress")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: showContent)

                // Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MiniStatCard(
                        icon: "chart.bar.fill",
                        value: "\(data.totalQueries)",
                        label: "Queries",
                        color: .blue
                    )

                    MiniStatCard(
                        icon: "clock.fill",
                        value: formatTimeSaved(minutes: data.timeSavedMinutes),
                        label: "Time Saved",
                        color: .green
                    )

                    MiniStatCard(
                        icon: "flame.fill",
                        value: "\(data.currentStreak)",
                        label: "Day Streak",
                        color: .orange
                    )
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: showContent)

                // Call to action
                Text("Keep up the momentum!")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.6), value: showContent)
            }
            .padding(24)

            // Particle effects (optional, simple version)
            if showParticles {
                ForEach(0..<10, id: \.self) { index in
                    ParticleView(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showContent = true
            // Delay particle effect slightly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showParticles = true
            }
            // Start countdown timer
            startCountdown()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Countdown Timer

    private func startCountdown() {
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, countdownDuration - elapsed)
            countdownProgress = remaining / countdownDuration

            // Auto-dismiss when countdown reaches 0
            if remaining <= 0 {
                stopTimer()
                onDismiss?()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTimeSaved(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Mini Stat Card

struct MiniStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold))

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Particle View (Simple animation)

struct ParticleView: View {
    let index: Int
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 1

    var body: some View {
        let particleColor = randomColor()

        return Circle()
            .fill(particleColor)
            .frame(width: 6, height: 6)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                animateParticle()
            }
    }

    private func animateParticle() {
        let angle = Double(index) * (360.0 / 10.0) * .pi / 180
        let distance: CGFloat = 50

        withAnimation(.easeOut(duration: 1.5)) {
            offset = CGSize(
                width: cos(angle) * distance,
                height: sin(angle) * distance
            )
            opacity = 0
        }
    }

    private func randomColor() -> Color {
        let colors: [Color] = [.yellow, .orange, .blue, .purple, .pink]
        return colors[index % colors.count]
    }
}
