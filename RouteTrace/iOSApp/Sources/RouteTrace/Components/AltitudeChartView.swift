import Charts
import SwiftUI
import RouteTraceShared

struct AltitudeChartView: View {
    let routePoints: [RoutePoint]

    private struct Sample: Identifiable {
        let id: Int
        let distanceMeters: Double
        let elevationMeters: Double
    }

    private var samples: [Sample] {
        routePoints.compactMap { point in
            guard let elevation = point.elevationMeters else { return nil }
            return Sample(id: point.id, distanceMeters: point.distanceFromStartMeters, elevationMeters: elevation)
        }
    }

    private var hasData: Bool {
        samples.count >= 2
    }

    private var elevationYDomain: ClosedRange<Double> {
        let elevations = samples.map(\.elevationMeters)
        let minElevation = elevations.min() ?? 0
        let maxElevation = elevations.max() ?? minElevation
        let range = max(maxElevation - minElevation, 1)
        let margin = range * 0.08
        return (minElevation - margin)...(maxElevation + margin)
    }

    var body: some View {
        Group {
            if hasData {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("Distance", sample.distanceMeters / 1000),
                        y: .value("Elevation", sample.elevationMeters)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Distance", sample.distanceMeters / 1000),
                        y: .value("Elevation", sample.elevationMeters)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxisLabel("Distance (km)")
                .chartYAxisLabel("Elevation (m)")
                .chartYScale(domain: elevationYDomain)
            } else {
                ContentUnavailableView(
                    "No Elevation Data",
                    systemImage: "mountain.2",
                    description: Text("This route has no elevation profile.")
                )
            }
        }
        .frame(minHeight: 180)
    }
}
