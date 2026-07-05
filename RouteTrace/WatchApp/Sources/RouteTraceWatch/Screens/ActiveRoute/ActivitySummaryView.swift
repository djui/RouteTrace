import RouteTraceShared
import SwiftUI

struct ActivitySummaryView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(WatchActivityStore.self) private var activityStore

    @State private var isSaving = false

    private static let contentHorizontalPadding: CGFloat = 16
    private static let floatingSaveClearance: CGFloat = 72

    private var speedMode: SpeedDisplayMode {
        preferences.speedDisplayMode(for: viewModel.activityKind)
    }

    private var activityTitle: String {
        ActivityNaming.title(
            startedAt: viewModel.recording.startedAt,
            activityKind: viewModel.activityKind,
            routeName: viewModel.recording.routeName
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(activityTitle)
                        .font(.headline)
                        .lineLimit(2)

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
                    } label: {
                        Text("Discard")
                            .frame(maxWidth: .infinity)
                    }
                    .routeGlassButton(tint: .red)
                    .disabled(isSaving)
                }
                .padding(.horizontal, Self.contentHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, Self.floatingSaveClearance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: isSaving ? 4 : 0)
            .allowsHitTesting(!isSaving)

            if isSaving {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !isSaving {
                saveButton
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .padding(.bottom, RouteAppearance.watchFloatingButtonBottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Finish")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                RouteGlassIconButton(systemName: "xmark") {
                    viewModel.cancelSummary()
                }
                .disabled(isSaving)
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                isSaving = true
                await viewModel.commitFinish(
                    preferences: preferences,
                    connectivity: connectivity,
                    activityStore: activityStore
                )
                isSaving = false
            }
        } label: {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .routeGlassButton(prominent: true, tint: .green)
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
