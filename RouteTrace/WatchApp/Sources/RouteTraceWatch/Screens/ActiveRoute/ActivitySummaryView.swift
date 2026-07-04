import RouteTraceShared
import SwiftUI

struct ActivitySummaryView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSaving = false

    private static let saveBarClearance: CGFloat = 56

    private var speedMode: SpeedDisplayMode {
        preferences.speedDisplayMode(for: viewModel.activityKind)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Summary")
                        .font(.headline)

                    summaryRow("Elapsed", RouteFormatting.duration(viewModel.elapsedSeconds), "clock")
                    summaryRow("Distance", RouteFormatting.distance(viewModel.recording.totalDistanceMeters), "ruler")
                    summaryRow(
                        speedMode.averageLabel,
                        RouteFormatting.speedOrPace(viewModel.averageSpeedMetersPerSecond, mode: speedMode),
                        "speedometer"
                    )
                    summaryRow("Elevation", RouteFormatting.elevation(viewModel.recording.elevationGainMeters), "arrow.up.right")
                    summaryRow("Heart Rate", heartRateLabel, "heart.fill")
                    summaryRow("Off Route", "\(viewModel.recording.offRouteEvents.count)", "location.slash")

                    if let route = viewModel.routePackage {
                        OverviewView(viewModel: viewModel, compact: true)
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(route.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        viewModel.discardActivity()
                        dismiss()
                    } label: {
                        Text("Discard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .padding(.bottom, Self.saveBarClearance)
            }

            saveBar
        }
        .navigationTitle("Finish")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private var saveBar: some View {
        Button {
            Task {
                isSaving = true
                await viewModel.commitFinish(preferences: preferences, connectivity: connectivity)
                isSaving = false
                dismiss()
            }
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(isSaving)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    RouteAppearance.canvas(for: colorScheme).opacity(0),
                    RouteAppearance.canvas(for: colorScheme),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var heartRateLabel: String {
        guard let bpm = viewModel.recording.averageHeartRateBPM else { return "—" }
        return String(format: "%.0f bpm", bpm)
    }

    private func summaryRow(_ title: String, _ value: String, _ symbol: String) -> some View {
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
