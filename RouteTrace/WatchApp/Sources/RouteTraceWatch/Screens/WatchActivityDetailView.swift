import RouteTraceShared
import SwiftUI

struct WatchActivityDetailView: View {
    let activity: ActivityRecording

    private var speedMode: SpeedDisplayMode {
        activity.activityKind.defaultSpeedDisplayMode
    }

    private var averageSpeedMetersPerSecond: Double? {
        guard activity.elapsedSeconds > 0 else { return nil }
        return activity.totalDistanceMeters / activity.elapsedSeconds
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ActivityTrackThumbnail(trackPoints: activity.trackPoints, size: 48)

                Text(activity.displayTitle)
                    .font(.headline)

                Text(activity.routeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                detailRow("Date", activity.startedAt.formatted(date: .abbreviated, time: .shortened), "calendar")
                detailRow("Elapsed", RouteFormatting.duration(activity.elapsedSeconds), "clock")
                detailRow("Distance", RouteFormatting.distance(activity.totalDistanceMeters), "ruler")
                detailRow(
                    speedMode.averageLabel,
                    RouteFormatting.speedOrPace(averageSpeedMetersPerSecond, mode: speedMode),
                    "speedometer"
                )
                detailRow("Elevation", RouteFormatting.elevation(activity.elevationGainMeters), "arrow.up.right")
                detailRow("Heart Rate", heartRateLabel, "heart.fill")
                detailRow("Off Route", "\(activity.offRouteEvents.count)", "location.slash")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heartRateLabel: String {
        guard let bpm = activity.averageHeartRateBPM else { return "—" }
        return String(format: "%.0f bpm", bpm)
    }

    private func detailRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            Spacer(minLength: 0)
        }
    }
}
