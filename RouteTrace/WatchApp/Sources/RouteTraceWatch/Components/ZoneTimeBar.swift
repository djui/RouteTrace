import RouteTraceShared
import SwiftUI

/// Time in each zone as one stacked bar, with the zone that got the most time.
struct ZoneTimeBar: View {
    let zones: WorkoutZones

    private static let segmentSpacing: CGFloat = 2

    private var visibleZones: [Int] {
        (0..<zones.zoneCount).filter { zones.fraction(ofZone: $0) > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let zonesShown = visibleZones
                let available = proxy.size.width - Self.segmentSpacing * CGFloat(max(zonesShown.count - 1, 0))
                HStack(spacing: Self.segmentSpacing) {
                    ForEach(zonesShown, id: \.self) { index in
                        zones.color(forZone: index)
                            .frame(width: max(2, available * zones.fraction(ofZone: index)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            if let dominant = zones.dominantZoneIndex {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(WorkoutZones.name(ofZone: dominant))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(zones.color(forZone: dominant))
                    Text("\(Int((zones.fraction(ofZone: dominant) * 100).rounded()))%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(zones.metric.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zones.metric.displayName)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        visibleZones.map { index in
            "\(WorkoutZones.name(ofZone: index)) \(Int((zones.fraction(ofZone: index) * 100).rounded())) percent"
        }
        .joined(separator: ", ")
    }
}
