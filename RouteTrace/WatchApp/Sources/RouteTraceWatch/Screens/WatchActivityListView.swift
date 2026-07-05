import RouteTraceShared
import SwiftUI

struct WatchActivityRowView: View {
    let activity: ActivityRecording

    var body: some View {
        HStack(spacing: 10) {
            ActivityTrackThumbnail(trackPoints: activity.trackPoints)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                HStack {
                    Label(RouteFormatting.distance(activity.totalDistanceMeters), systemImage: "ruler")
                    Spacer()
                    Label(activity.activityKind.displayName, systemImage: activity.activityKind.systemImage)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
