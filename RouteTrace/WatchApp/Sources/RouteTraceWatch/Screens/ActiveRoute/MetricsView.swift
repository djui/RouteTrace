import RouteTraceShared
import SwiftUI

struct MetricsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @FocusState private var metricsScrollFocused: Bool

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var speedMode: SpeedDisplayMode {
        preferences.speedDisplayMode(for: viewModel.activityKind)
    }

    private var isCrownEnabled: Bool {
        uiState.selectedPage == .metrics && !uiState.isMapFocus
    }

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    metricRow("Remaining", RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0), "arrow.right")
                    metricRow(
                        speedMode.shortLabel,
                        RouteFormatting.speedOrPace(viewModel.navigationSnapshot?.currentSpeedMetersPerSecond, mode: speedMode),
                        "speedometer"
                    )
                    metricRow("Elevation Gain", RouteFormatting.elevation(viewModel.recording.elevationGainMeters), "arrow.up.right")
                    metricRow("Heart Rate", heartRateLabel, "heart.fill")
                    metricRow("Off Route Events", "\(viewModel.recording.offRouteEvents.count)", "location.slash")
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .routeScreenBackground()
            .focusable(isCrownEnabled)
            .focused($metricsScrollFocused)
            .onAppear {
                requestMetricsCrownFocus()
            }
            .onChange(of: uiState.selectedPage) { _, _ in
                requestMetricsCrownFocus()
            }
        }
    }

    private func requestMetricsCrownFocus() {
        guard isCrownEnabled else {
            metricsScrollFocused = false
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if isCrownEnabled {
                metricsScrollFocused = true
            }
        }
    }

    private var heartRateLabel: String {
        guard let bpm = viewModel.workoutService.heartRateBPM ?? viewModel.recording.averageHeartRateBPM else {
            return "—"
        }
        return String(format: "%.0f bpm", bpm)
    }

    private func metricRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
            }
            Spacer()
        }
    }
}
