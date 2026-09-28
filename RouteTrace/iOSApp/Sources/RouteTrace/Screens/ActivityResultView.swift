import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore

    let activity: ActivityEntity

    /// Decoded once; `ActivityEntity.recording` decodes JSON on every access.
    @State private var recording: ActivityRecording?
    @State private var plannedRoute: [RoutePoint] = []
    @State private var profile: [ActivityProfileSample] = []
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var editedActivityTitle = ""
    @State private var isMapFullscreenPresented = false
    @State private var errorMessage: String?

    private var summary: ActivitySummary {
        routeStore.summary(for: activity)
    }

    private var speedDisplayMode: SpeedDisplayMode {
        activity.activityKind.defaultSpeedDisplayMode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroMap
                summaryCard
                statsCard
                chartsSection
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activity.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: GPXDocument.storedActivity(id: activity.id, title: activity.displayTitle),
                    preview: SharePreview(activity.displayTitle)
                ) {
                    Label("Share GPX", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editedActivityTitle = activity.displayTitle
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive) {
                deleteActivity()
            }
        } message: {
            Text("This removes the activity from RouteTrace on this iPhone. Workouts saved to the Health app are not affected.")
        }
        .fullScreenCover(isPresented: $isMapFullscreenPresented) {
            RouteMapFullscreenView(
                title: activity.displayTitle,
                subtitle: "\(RouteFormatting.distance(summary.distanceMeters)) · \(RouteFormatting.duration(summary.elapsedSeconds))",
                routePoints: plannedRoute,
                trackPoints: recording?.trackPoints ?? []
            )
        }
        .alert("Couldn’t Complete Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Activity", isPresented: $showRenameAlert) {
            TextField("Activity Name", text: $editedActivityTitle)
                .textInputAutocapitalization(.sentences)
            Button("Save") { renameActivity() }
                .disabled(editedActivityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .task(id: activity.id) {
            await load()
        }
    }

    // MARK: - Sections

    private var heroMap: some View {
        Button {
            isMapFullscreenPresented = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let recording {
                    RouteMapPreview(
                        routePoints: plannedRoute,
                        trackPoints: recording.trackPoints,
                        routeColor: RouteDesign.routeColor.opacity(0.55)
                    )
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { ProgressView() }
                }

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .padding(12)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: RouteDesign.cardCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: RouteDesign.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show activity map")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StatusChip(
                    title: activity.activityKind.displayName,
                    systemImage: activity.activityKind.systemImage,
                    tint: activity.activityKind.tint
                )
                Spacer()
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HeadlineStat(title: "Distance", value: RouteFormatting.distance(summary.distanceMeters))
                HeadlineStat(title: "Time", value: RouteFormatting.duration(summary.elapsedSeconds))
                HeadlineStat(
                    title: speedDisplayMode == .pace ? "Avg Pace" : "Avg Speed",
                    value: RouteFormatting.speedOrPace(summary.averageSpeedMetersPerSecond, mode: speedDisplayMode)
                )
            }

            if activity.routeName != activity.displayTitle {
                Label(activity.routeName, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var statsCard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            StatCell(
                title: "Elevation Gain",
                value: RouteFormatting.elevation(summary.elevationGainMeters),
                systemImage: "arrow.up.right",
                tint: .orange
            )
            StatCell(
                title: "Avg Heart Rate",
                value: summary.averageHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "—",
                systemImage: "heart.fill",
                tint: .red
            )
            StatCell(
                title: "Detours",
                value: "\(recording?.offRouteEvents.count ?? 0)",
                systemImage: "location.slash.fill",
                tint: (recording?.offRouteEvents.isEmpty ?? true) ? .green : .orange
            )
            StatCell(
                title: "Route Completed",
                value: routeCompletionText,
                systemImage: "flag.checkered",
                tint: .blue
            )
        }
        .card()
    }

    @ViewBuilder
    private var chartsSection: some View {
        let elevation = ProfilePoint.series(from: profile) { $0.altitudeMeters }
        let heartRate = ProfilePoint.series(from: profile) { $0.heartRateBPM }.smoothed(window: 7)

        if elevation.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Elevation", systemImage: "mountain.2.fill")
                ProfileChart(points: elevation, color: RouteDesign.trackColor, seriesName: "Elevation", valueUnit: .elevation)
            }
            .card()
        }

        if heartRate.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    title: "Heart Rate",
                    systemImage: "heart.fill",
                    trailing: heartRateRangeText(heartRate)
                )
                ProfileChart(points: heartRate, color: .red, seriesName: "Heart Rate", valueUnit: .fixed("bpm"), fillsArea: false)
            }
            .card()
        }
    }

    // MARK: - Derived values

    private var routeCompletionText: String {
        guard let recording, let total = plannedRoute.last?.distanceFromStartMeters, total > 0 else { return "—" }
        let progress = ActivityTrackStatistics.routeProgressMeters(
            from: recording.trackPoints,
            fallbackRouteProgress: recording.totalDistanceMeters
        )
        return "\(Int((min(1, progress / total) * 100).rounded()))%"
    }

    private func heartRateRangeText(_ points: [ProfilePoint]) -> String? {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max() else { return nil }
        return "\(Int(min.rounded()))–\(Int(max.rounded())) bpm"
    }

    // MARK: - Actions

    private func load() async {
        let decoded = routeStore.recording(for: activity)
        recording = decoded

        let liveRoute = (try? routeStore.fetchRoute(id: decoded.routeId))
            .flatMap { try? routeStore.loadRoutePackage(for: $0) }
        plannedRoute = decoded.resolvedPlannedRoutePoints(liveRoute: liveRoute)

        let trackPoints = decoded.trackPoints
        profile = await Task.detached(priority: .userInitiated) {
            ActivityTrackStatistics.profileSamples(from: trackPoints)
        }.value
    }

    private func deleteActivity() {
        do {
            try routeStore.deleteActivity(activity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameActivity() {
        do {
            try routeStore.renameActivity(for: activity, to: editedActivityTitle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
