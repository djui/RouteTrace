import RouteTraceShared
import SwiftUI

struct ActivitySummaryView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(WatchActivityStore.self) private var activityStore

    @State private var isSaving = false
    @State private var showDiscardConfirmation = false

    private static let contentHorizontalPadding: CGFloat = 14
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(activityTitle)
                        .font(.headline)
                        .lineLimit(3)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            summaryStat("Time", RouteFormatting.duration(viewModel.elapsedSeconds), tint: .yellow)
                            summaryStat("Distance", RouteFormatting.distance(viewModel.gpsDistanceMeters))
                        }
                        GridRow {
                            summaryStat(speedMode.averageLabel, RouteFormatting.speedOrPace(viewModel.averageSpeedMetersPerSecond, mode: speedMode))
                            summaryStat("Climbed", RouteFormatting.elevation(viewModel.elevationGainMeters ?? 0))
                        }
                        GridRow {
                            summaryStat("Avg Heart", viewModel.averageHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "—", tint: .red)
                            summaryStat("Route", "\(Int((viewModel.progressFraction * 100).rounded()))%")
                        }
                    }

                    if viewModel.routePackage != nil {
                        OverviewView(viewModel: viewModel, compact: true)
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button(role: .destructive) {
                        showDiscardConfirmation = true
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .routeGlassButton(tint: .red)
                    .disabled(isSaving)
                }
                .padding(.horizontal, Self.contentHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, Self.floatingSaveClearance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: isSaving ? 4 : 0)
            .allowsHitTesting(!isSaving)

            if isSaving {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                saveButton
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .padding(.bottom, RouteAppearance.watchFloatingButtonBottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Back to the paused activity.
                RouteGlassIconButton(systemName: "chevron.backward") {
                    viewModel.cancelSummary()
                }
                .disabled(isSaving)
                .accessibilityLabel("Resume Activity")
            }
        }
        .confirmationDialog("Discard this activity?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                viewModel.discardActivity()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The route and time recorded won’t be saved, here or in Health.")
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
            Label("Save", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .routeGlassButton(prominent: true, tint: .green)
    }

    private func summaryStat(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
