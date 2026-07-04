import Charts
import SwiftUI
import RouteTraceShared

struct ActivityElevationChartView: View {
    let trackPoints: [TrackPoint]

    private struct Sample: Identifiable {
        let id: Int
        let distanceMeters: Double
        let elevationMeters: Double
    }

    private var samples: [Sample] {
        guard trackPoints.count >= 2 else { return [] }

        var result: [Sample] = []
        var cumulativeDistance = 0.0

        for index in trackPoints.indices {
            guard let elevation = trackPoints[index].altitudeMeters else { continue }

            if index > 0 {
                cumulativeDistance += MapMath.haversineMeters(
                    from: trackPoints[index - 1].coordinate,
                    to: trackPoints[index].coordinate
                )
            }

            result.append(
                Sample(
                    id: index,
                    distanceMeters: cumulativeDistance,
                    elevationMeters: elevation
                )
            )
        }
        return result
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
                        yStart: .value("Baseline", elevationYDomain.lowerBound),
                        yEnd: .value("Elevation", sample.elevationMeters)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.35), Color.green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Distance", sample.distanceMeters / 1000),
                        y: .value("Elevation", sample.elevationMeters)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxisLabel("Distance (km)")
                .chartYAxisLabel("Elevation (m)")
                .chartYScale(domain: elevationYDomain)
                .clipped()
            } else {
                ContentUnavailableView(
                    "No Elevation Data",
                    systemImage: "mountain.2",
                    description: Text("This activity has no recorded elevation.")
                )
            }
        }
        .frame(minHeight: 180)
    }
}
