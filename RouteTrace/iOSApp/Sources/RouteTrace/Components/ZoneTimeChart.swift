import RouteTraceShared
import SwiftUI

/// Time in each zone as horizontal bars, hardest zone on top.
struct ZoneTimeChart: View {
    let zones: WorkoutZones

    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array((0..<zones.zoneCount).reversed()), id: \.self) { index in
                row(index)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let fraction = zones.fraction(ofZone: index)
        let percent = Int((fraction * 100).rounded())
        let duration = RouteFormatting.duration(zones.secondsInZone[index])
        let range = "\(zones.rangeLabel(ofZone: index)) \(zones.metric.unitSymbol)"

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(WorkoutZones.name(ofZone: index))
                    .font(.subheadline.weight(.semibold))
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: labelWidth, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(zones.color(forZone: index))
                        .frame(width: fraction > 0 ? max(6, proxy.size.width * fraction) : 0)
                }
            }
            .frame(height: 10)

            VStack(alignment: .trailing, spacing: 1) {
                Text(duration)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("\(percent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: valueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WorkoutZones.name(ofZone: index)), \(range)")
        .accessibilityValue("\(duration), \(percent) percent")
    }
}
