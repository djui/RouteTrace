import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore

    let activity: ActivityEntity

    @State private var plannedRoute: RoutePackage?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isSharePresented = false
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var editedActivityTitle = ""
    @State private var isRenaming = false
    @State private var isMapFullscreenPresented = false
    @State private var errorMessage: String?

    private var recording: ActivityRecording {
        activity.recording
    }

    private var gpsDistanceMeters: Double {
        ActivityTrackStatistics.gpsDistanceMeters(from: recording.trackPoints)
    }

    private var routeProgressMeters: Double {
        ActivityTrackStatistics.routeProgressMeters(
            from: recording.trackPoints,
            fallbackRouteProgress: recording.totalDistanceMeters
        )
    }

    private var elevationGainMeters: Double? {
        ActivityTrackStatistics.elevationGainMeters(
            from: recording.trackPoints,
            fallback: recording.elevationGainMeters
        )
    }

    private var showsRouteProgress: Bool {
        ActivityTrackStatistics.routeProgressDiffersMeaningfully(
            gpsDistanceMeters: gpsDistanceMeters,
            routeProgressMeters: routeProgressMeters
        )
    }

    private var speedDisplayMode: SpeedDisplayMode {
        recording.activityKind.defaultSpeedDisplayMode
    }

    private var averageSpeedMetersPerSecond: Double? {
        ActivityTrackStatistics.averageSpeedMetersPerSecond(
            gpsDistanceMeters: gpsDistanceMeters,
            elapsedSeconds: recording.elapsedSeconds
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    isMapFullscreenPresented = true
                } label: {
                    RouteMapPreview(
                        routePoints: plannedRoute?.route ?? [],
                        trackPoints: recording.trackPoints,
                        lineColor: .blue.opacity(0.55),
                        trackColor: .green
                    )
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                statsSection

                if recording.trackPoints.contains(where: { $0.altitudeMeters != nil }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Elevation Profile")
                            .font(.headline)
                        ActivityElevationChartView(trackPoints: recording.trackPoints)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(activity.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editedActivityTitle = activity.displayTitle
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        exportGPX()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog(
                    "Delete this activity?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Activity", role: .destructive) {
                        deleteActivity()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the activity from your iPhone.")
                }
            }
        }
        .fullScreenCover(isPresented: $isMapFullscreenPresented) {
            ActivityMapFullscreenView(
                routeName: activity.displayTitle,
                distanceLabel: RouteFormatting.distance(gpsDistanceMeters),
                routePoints: plannedRoute?.route ?? [],
                trackPoints: recording.trackPoints
            )
        }
        .sheet(isPresented: $isSharePresented, onDismiss: { RouteActions.cleanupExport(at: exportURL) }) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .alert("Activity Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Activity", isPresented: $showRenameAlert) {
            TextField("Activity Name", text: $editedActivityTitle)
                .textInputAutocapitalization(.words)
            Button("Save") {
                Task { await renameActivity() }
            }
            .disabled(editedActivityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a name for this activity.")
        }
        .task {
            await loadPlannedRoute()
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Distance", value: RouteFormatting.distance(gpsDistanceMeters), symbol: "ruler")
                if showsRouteProgress {
                    StatTile(
                        title: "Route Progress",
                        value: RouteFormatting.distance(routeProgressMeters),
                        symbol: "point.bottomleft.forward.to.point.topright.scurvepath"
                    )
                }
                StatTile(title: "Duration", value: RouteFormatting.duration(recording.elapsedSeconds), symbol: "stopwatch")
                StatTile(
                    title: speedDisplayMode.averageLabel,
                    value: RouteFormatting.speedOrPace(averageSpeedMetersPerSecond, mode: speedDisplayMode),
                    symbol: "speedometer"
                )
                StatTile(title: "Activity", value: recording.activityKind.displayName, symbol: recording.activityKind.systemImage)
                StatTile(
                    title: "Elevation Gain",
                    value: RouteFormatting.elevation(elevationGainMeters),
                    symbol: "arrow.up.right"
                )
                StatTile(
                    title: "Avg Heart Rate",
                    value: recording.averageHeartRateBPM.map { String(format: "%.0f bpm", $0) } ?? "—",
                    symbol: "heart.fill"
                )
                StatTile(
                    title: "Off Route Events",
                    value: "\(recording.offRouteEvents.count)",
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    @MainActor
    private func loadPlannedRoute() async {
        guard let routeEntity = try? routeStore.fetchRoute(id: recording.routeId) else { return }
        plannedRoute = try? routeStore.loadRoutePackage(for: routeEntity)
    }

    private func exportGPX() {
        isExporting = true
        defer { isExporting = false }

        do {
            exportURL = try RouteActions.exportActivityGPXURL(for: recording, route: plannedRoute)
            isSharePresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteActivity() {
        do {
            try routeStore.deleteActivity(activity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renameActivity() async {
        isRenaming = true
        defer { isRenaming = false }

        do {
            _ = try routeStore.renameActivity(for: activity, to: editedActivityTitle)
            showRenameAlert = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
