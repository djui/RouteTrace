import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityListView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Query(sort: \ActivityEntity.startedAt, order: .reverse) private var activities: [ActivityEntity]

    @State private var errorMessage: String?
    @State private var activityPendingRename: ActivityEntity?
    @State private var editedActivityTitle = ""
    @State private var isRenaming = false
    @State private var exportURL: URL?
    @State private var isSharePresented = false

    var body: some View {
        NavigationStack {
            Group {
                if activities.isEmpty {
                    ContentUnavailableView {
                        Label("No Activities", systemImage: "figure.run")
                    } description: {
                        Text("Completed workouts from your Apple Watch will appear here.")
                    }
                } else {
                    List(activities) { activity in
                        ActivityListRow(
                            activity: activity,
                            onRename: { activity in
                                editedActivityTitle = activity.displayTitle
                                activityPendingRename = activity
                            },
                            onShare: { shareActivity($0) },
                            onDelete: { deleteActivity($0) }
                        )
                    }
                }
            }
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { activityID in
                if let activity = activities.first(where: { $0.id == activityID }) {
                    ActivityResultView(activity: activity)
                }
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
            .alert("Rename Activity", isPresented: Binding(
                get: { activityPendingRename != nil },
                set: { if !$0 { activityPendingRename = nil } }
            )) {
                TextField("Activity Name", text: $editedActivityTitle)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    if let activity = activityPendingRename {
                        Task { await renameActivity(activity) }
                    }
                }
                .disabled(editedActivityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
                Button("Cancel", role: .cancel) {
                    activityPendingRename = nil
                }
            } message: {
                Text("Choose a name for this activity.")
            }
        }
    }

    private func shareActivity(_ activity: ActivityEntity) {
        let recording = activity.recording
        let plannedRoute = (try? routeStore.fetchRoute(id: recording.routeId))
            .flatMap { try? routeStore.loadRoutePackage(for: $0) }

        do {
            exportURL = try RouteActions.exportActivityGPXURL(for: recording, route: plannedRoute)
            isSharePresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteActivity(_ activity: ActivityEntity) {
        do {
            try routeStore.deleteActivity(activity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renameActivity(_ activity: ActivityEntity) async {
        isRenaming = true
        defer { isRenaming = false }

        do {
            _ = try routeStore.renameActivity(for: activity, to: editedActivityTitle)
            activityPendingRename = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActivityListRow: View {
    let activity: ActivityEntity
    let onRename: (ActivityEntity) -> Void
    let onShare: (ActivityEntity) -> Void
    let onDelete: (ActivityEntity) -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationLink(value: activity.id) {
            ActivityRowView(activity: activity)
        }
        .contextMenu {
            Button {
                onRename(activity)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                onShare(activity)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .none) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .confirmationDialog(
            "Delete this activity?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Activity", role: .destructive) {
                showDeleteConfirmation = false
                onDelete(activity)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the activity from your iPhone.")
        }
    }
}

private struct ActivityRowView: View {
    let activity: ActivityEntity

    private var gpsDistanceMeters: Double {
        ActivityTrackStatistics.gpsDistanceMeters(from: activity.recording.trackPoints)
    }

    var body: some View {
        HStack(spacing: 10) {
            ActivityTrackThumbnail(trackPoints: activity.recording.trackPoints)

            VStack(alignment: .leading, spacing: 6) {
                Text(activity.displayTitle)
                    .font(.headline)

                HStack(spacing: 8) {
                    metadataLabel(
                        RouteFormatting.distance(gpsDistanceMeters),
                        systemImage: "ruler"
                    )
                    metadataLabel(
                        RouteFormatting.duration(activity.elapsedSeconds),
                        systemImage: "stopwatch"
                    )
                    metadataLabel(
                        activity.activityKind.displayName,
                        systemImage: activity.activityKind.systemImage
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metadataLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .fixedSize()
    }
}
