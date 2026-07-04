import RouteTraceShared
import SwiftUI

struct AltitudeProfileView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            dimmedAltitude
        } else {
            fullAltitude
        }
    }

    private var dimmedAltitude: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Altitude")
                .font(.headline)
            HStack {
                stat("Gain", RouteFormatting.elevation(viewModel.routePackage?.elevationGainMeters))
                Spacer()
                stat("Current", currentElevationLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 28)
        .background(Color.black)
    }

    private var fullAltitude: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Altitude")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 28)

            if let route = viewModel.routePackage, route.hasElevationData {
                ChartContent(
                    samples: elevationSamples(from: route),
                    progressMeters: viewModel.navigationSnapshot?.progressDistanceMeters ?? 0,
                    totalMeters: route.distanceMeters
                )
                .frame(maxHeight: .infinity)

                HStack {
                    stat("Gain", RouteFormatting.elevation(route.elevationGainMeters))
                    Spacer()
                    stat("Current", currentElevationLabel)
                }
            } else {
                Spacer()
                Text("No elevation data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var currentElevationLabel: String {
        guard let last = viewModel.recording.trackPoints.last?.altitudeMeters else {
            return "—"
        }
        return RouteFormatting.elevation(last)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
        }
    }

    private func elevationSamples(from route: RoutePackage) -> [ElevationSample] {
        route.route.compactMap { point in
            guard let elevation = point.elevationMeters else { return nil }
            return ElevationSample(distanceMeters: point.distanceFromStartMeters, elevationMeters: elevation)
        }
    }
}

private struct ElevationSample: Identifiable {
    let id = UUID()
    let distanceMeters: Double
    let elevationMeters: Double
}

private struct ChartContent: View {
    let samples: [ElevationSample]
    let progressMeters: Double
    let totalMeters: Double

    var body: some View {
        GeometryReader { proxy in
            let minElevation = samples.map(\.elevationMeters).min() ?? 0
            let maxElevation = samples.map(\.elevationMeters).max() ?? 1
            let elevationRange = max(1, maxElevation - minElevation)
            let progressX = totalMeters > 0 ? proxy.size.width * CGFloat(progressMeters / totalMeters) : 0
            let markerPoint = markerPosition(in: proxy.size, minElevation: minElevation, range: elevationRange)

            ZStack(alignment: .leading) {
                Path { path in
                    guard let first = samples.first else { return }
                    path.move(to: point(for: first, in: proxy.size, minElevation: minElevation, range: elevationRange))
                    for sample in samples.dropFirst() {
                        path.addLine(to: point(for: sample, in: proxy.size, minElevation: minElevation, range: elevationRange))
                    }
                }
                .stroke(.blue, lineWidth: 2)

                if totalMeters > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: progressX)

                    Rectangle()
                        .fill(.yellow.opacity(0.9))
                        .frame(width: 2, height: proxy.size.height)
                        .offset(x: max(0, progressX - 1))

                    if let markerPoint {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 8, height: 8)
                            .position(markerPoint)
                    }
                }
            }
        }
    }

    private func markerPosition(in size: CGSize, minElevation: Double, range: Double) -> CGPoint? {
        guard totalMeters > 0, !samples.isEmpty else { return nil }
        let nearest = samples.min(by: {
            abs($0.distanceMeters - progressMeters) < abs($1.distanceMeters - progressMeters)
        })
        guard let nearest else { return nil }
        return point(for: nearest, in: size, minElevation: minElevation, range: range)
    }

    private func point(
        for sample: ElevationSample,
        in size: CGSize,
        minElevation: Double,
        range: Double
    ) -> CGPoint {
        let x = totalMeters > 0 ? size.width * CGFloat(sample.distanceMeters / totalMeters) : 0
        let normalized = (sample.elevationMeters - minElevation) / range
        let y = size.height * (1 - CGFloat(normalized))
        return CGPoint(x: x, y: y)
    }
}
