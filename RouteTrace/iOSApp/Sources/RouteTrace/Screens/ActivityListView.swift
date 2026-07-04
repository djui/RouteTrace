import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityListView: View {
    @Query(sort: \ActivityEntity.startedAt, order: .reverse) private var activities: [ActivityEntity]

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
                        NavigationLink(value: activity.id) {
                            ActivityRowView(activity: activity)
                        }
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
        }
    }
}

private struct ActivityRowView: View {
    let activity: ActivityEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.routeName)
                .font(.headline)

            HStack(spacing: 12) {
                Label(RouteFormatting.distance(activity.totalDistanceMeters), systemImage: "ruler")
                Label(RouteFormatting.duration(activity.elapsedSeconds), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
