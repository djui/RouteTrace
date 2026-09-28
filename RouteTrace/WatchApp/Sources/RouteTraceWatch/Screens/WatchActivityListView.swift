import RouteTraceShared
import SwiftUI

struct WatchActivityRowView: View {
    let activity: ActivityRecording

    @Environment(WatchActivityStore.self) private var activityStore

    var body: some View {
        let summary = activityStore.summary(for: activity)
        HStack(spacing: 10) {
            RouteShapeThumbnail(coordinates: summary.thumbnail, color: RouteAppearance.trackColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text("\(RouteFormatting.distance(summary.distanceMeters)) · \(RouteFormatting.duration(activity.elapsedSeconds))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(activity.startedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
