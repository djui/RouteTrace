import RouteTraceShared
import SwiftUI

struct WatchActivityDetailView: View {
    let activity: ActivityRecording

    @Environment(WatchActivityStore.self) private var activityStore

    private var speedMode: SpeedDisplayMode {
        activity.activityKind.defaultSpeedDisplayMode
    }

    var body: some View {
        let summary = activityStore.summary(for: activity)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                RouteShapeThumbnail(coordinates: summary.thumbnail, color: RouteAppearance.trackColor, size: 64)

                Text(activity.displayTitle)
                    .font(.headline)
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        stat("Time", RouteFormatting.duration(activity.elapsedSeconds), tint: .yellow)
                        stat("Distance", RouteFormatting.distance(summary.distanceMeters))
                    }
                    GridRow {
                        stat(speedMode.averageLabel, RouteFormatting.speedOrPace(summary.averageSpeedMetersPerSecond, mode: speedMode))
                        stat("Climbed", RouteFormatting.elevation(summary.elevationGainMeters ?? 0))
                    }
                    GridRow {
                        stat("Avg Heart", activity.averageHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "—", tint: .red)
                        stat("Detours", "\(activity.offRouteEvents.count)")
                    }
                }

                ForEach(activity.workoutZones ?? [], id: \.metric) { zones in
                    ZoneTimeBar(zones: zones)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ title: String, _ value: String, tint: Color = .primary) -> some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
