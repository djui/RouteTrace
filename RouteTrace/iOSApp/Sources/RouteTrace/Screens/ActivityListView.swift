import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityListView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Query(sort: \ActivityEntity.startedAt, order: .reverse) private var activities: [ActivityEntity]

    @State private var errorMessage: String?
    @State private var activityPendingRename: ActivityEntity?
    @State private var activityPendingDelete: ActivityEntity?
    @State private var editedActivityTitle = ""
    @State private var isShowingSettings = false

    private struct MonthSection: Identifiable {
        let month: Date
        let activities: [ActivityEntity]
        var id: Date { month }
    }

    private var sections: [MonthSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activities) { activity in
            calendar.dateInterval(of: .month, for: activity.startedAt)?.start ?? activity.startedAt
        }
        return grouped
            .map { MonthSection(month: $0.key, activities: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activities.isEmpty {
                    ContentUnavailableView {
                        Label("No Activities Yet", systemImage: "figure.run")
                    } description: {
                        Text("Start a route on your Apple Watch. When you finish, the activity appears here with your track, pace, heart rate and elevation.")
                    }
                } else {
                    List {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.activities) { activity in
                                    NavigationLink(value: activity.id) {
                                        ActivityRow(activity: activity, summary: routeStore.summary(for: activity))
                                    }
                                    .contextMenu {
                                        Button {
                                            editedActivityTitle = activity.displayTitle
                                            activityPendingRename = activity
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        ShareLink(
                                            item: GPXDocument.storedActivity(id: activity.id, title: activity.displayTitle),
                                            preview: SharePreview(activity.displayTitle)
                                        ) {
                                            Label("Share GPX", systemImage: "square.and.arrow.up")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            activityPendingDelete = activity
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            activityPendingDelete = activity
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                                    // Attached per row so the popover points at the activity being deleted.
                                    .confirmationDialog(
                                        "Delete this activity?",
                                        isPresented: deleteConfirmationBinding(for: activity),
                                        titleVisibility: .visible
                                    ) {
                                        Button("Delete Activity", role: .destructive) {
                                            delete(activity)
                                        }
                                    } message: {
                                        Text("This removes the activity from RouteTrace on this iPhone. Workouts saved to the Health app are not affected.")
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .navigationDestination(for: UUID.self) { activityID in
                if let activity = activities.first(where: { $0.id == activityID }) {
                    ActivityResultView(activity: activity)
                } else {
                    ContentUnavailableView("Activity Deleted", systemImage: "trash")
                }
            }
            .alert("Couldn’t Complete Action", isPresented: Binding(
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
                    .textInputAutocapitalization(.sentences)
                Button("Save") {
                    if let activity = activityPendingRename {
                        rename(activity)
                    }
                }
                .disabled(editedActivityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func sectionHeader(_ section: MonthSection) -> some View {
        let distance = section.activities.reduce(0) { $0 + routeStore.summary(for: $1).distanceMeters }
        let count = section.activities.count
        return HStack {
            Text(section.month.formatted(.dateTime.month(.wide).year()))
            Spacer()
            Text("\(count) \(count == 1 ? "activity" : "activities") · \(RouteFormatting.distance(distance))")
                .monospacedDigit()
        }
    }

    private func rename(_ activity: ActivityEntity) {
        do {
            try routeStore.renameActivity(for: activity, to: editedActivityTitle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ activity: ActivityEntity) {
        do {
            try routeStore.deleteActivity(activity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteConfirmationBinding(for activity: ActivityEntity) -> Binding<Bool> {
        Binding(
            get: { activityPendingDelete?.id == activity.id },
            set: { isPresented in
                if !isPresented, activityPendingDelete?.id == activity.id {
                    activityPendingDelete = nil
                }
            }
        )
    }
}

private struct ActivityRow: View {
    let activity: ActivityEntity
    let summary: ActivitySummary

    var body: some View {
        HStack(spacing: 14) {
            RouteShapeThumbnail(
                coordinates: summary.thumbnail,
                color: RouteDesign.trackColor,
                size: 58,
                placeholderSymbol: activity.activityKind.systemImage
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(activity.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(RouteFormatting.distance(summary.distanceMeters))
                    Text(RouteFormatting.duration(summary.elapsedSeconds))
                    Text(RouteFormatting.speedOrPace(
                        summary.averageSpeedMetersPerSecond,
                        mode: activity.activityKind.defaultSpeedDisplayMode
                    ))
                }
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
