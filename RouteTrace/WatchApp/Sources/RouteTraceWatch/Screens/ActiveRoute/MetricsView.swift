import RouteTraceShared
import SwiftUI

struct MetricsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    metricRow("Remaining", RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0), "arrow.right")
                    metricRow("Speed", RouteFormatting.speed(viewModel.navigationSnapshot?.currentSpeedMetersPerSecond), "speedometer")
                    metricRow("Elevation Gain", RouteFormatting.elevation(viewModel.recording.elevationGainMeters), "arrow.up.right")
                    metricRow("Heart Rate", heartRateLabel, "heart.fill")
                    metricRow("Off Route Events", "\(viewModel.recording.offRouteEvents.count)", "location.slash")
                }
                .padding(.horizontal, 8)
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .routeScreenBackground()
            .focusable(uiState.selectedPage == .metrics && !uiState.isMapFocus)
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
