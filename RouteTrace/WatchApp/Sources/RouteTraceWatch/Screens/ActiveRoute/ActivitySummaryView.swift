import RouteTraceShared
import SwiftUI

struct ActivitySummaryView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity Summary")
                    .font(.headline)

                summaryRow("Elapsed", RouteFormatting.duration(viewModel.elapsedSeconds), "clock")
                summaryRow("Distance", RouteFormatting.distance(viewModel.recording.totalDistanceMeters), "ruler")
                summaryRow("Avg Speed", RouteFormatting.speed(viewModel.averageSpeedMetersPerSecond), "speedometer")
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
                    Label("Discard Activity", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 16)
            }
            .padding()
            .padding(.bottom, 48)
        }
        .navigationTitle(viewModel.routePackage?.name ?? "Summary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
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
                    } else {
                        Label("Save", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isSaving)
            }
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
