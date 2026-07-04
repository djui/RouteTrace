import RouteTraceShared
import SwiftUI

struct StatsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    headerBar

                    statRow("Elapsed", RouteFormatting.duration(viewModel.elapsedSeconds), "clock")
                    statRow(
                        "Distance",
                        RouteFormatting.distance(viewModel.navigationSnapshot?.progressDistanceMeters ?? viewModel.recording.totalDistanceMeters),
                        "ruler"
                    )
                    statRow(
                        "Remaining",
                        RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0),
                        "arrow.right"
                    )
                    statRow(
                        "Speed",
                        RouteFormatting.speed(viewModel.navigationSnapshot?.currentSpeedMetersPerSecond),
                        "speedometer"
                    )
                    statRow(
                        "Elevation Gain",
                        RouteFormatting.elevation(viewModel.recording.elevationGainMeters),
                        "arrow.up.right"
                    )
                    statRow(
                        "Heart Rate",
                        heartRateLabel,
                        "heart.fill"
                    )
                    statRow(
                        "Off Route Events",
                        "\(viewModel.recording.offRouteEvents.count)",
                        "location.slash"
                    )

                    if case .unavailable(let message) = viewModel.workoutService.status {
                        Text("Workout: \(message)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.routePackage?.name ?? "Stats")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("Live activity stats")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
    }

    private var heartRateLabel: String {
        guard let bpm = viewModel.workoutService.heartRateBPM ?? viewModel.recording.averageHeartRateBPM else {
            return "—"
        }
        return String(format: "%.0f bpm", bpm)
    }

    private func statRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            Spacer()
        }
    }
}
