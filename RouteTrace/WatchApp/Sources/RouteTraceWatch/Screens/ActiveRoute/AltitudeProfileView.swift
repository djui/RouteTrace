import RouteTraceShared
import SwiftUI

struct AltitudeProfileView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var idleResetTask: Task<Void, Never>?

    private static let inspectIdleSeconds: UInt64 = 3

    private var progressMeters: Double {
        viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
    }

    private var markerDistanceMeters: Double {
        uiState.altitudeCrownMeters
    }

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
                stat("Current", markerElevationLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 28)
        .routeScreenBackground()
    }

    private var fullAltitude: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Altitude")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 28)

            if let route = viewModel.routePackage, route.hasElevationData {
                let samples = elevationSamples(from: route)
                ChartContent(
                    samples: samples,
                    progressMeters: progressMeters,
                    markerDistanceMeters: uiState.altitudeCrownMeters,
                    totalMeters: route.distanceMeters
                )
                .id(uiState.altitudeCrownMeters)
                .frame(maxHeight: .infinity)

                HStack {
                    stat("Gain", RouteFormatting.elevation(route.elevationGainMeters))
                    Spacer()
                    stat("Current", markerElevationLabel)
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
        .routeScreenBackground()
        .onChange(of: uiState.isAltitudeScrubbing) { _, isScrubbing in
            if isScrubbing {
                scheduleIdleReset()
            } else {
                idleResetTask?.cancel()
            }
        }
        .onChange(of: uiState.altitudeCrownMeters) { _, _ in
            if uiState.isAltitudeScrubbing {
                scheduleIdleReset()
            }
        }
        .onDisappear {
            idleResetTask?.cancel()
            uiState.clearAltitudeInspect()
        }
    }

    private var markerElevationLabel: String {
        guard let route = viewModel.routePackage, route.hasElevationData else { return "—" }
        let samples = elevationSamples(from: route)
        guard let elevation = ElevationSample.interpolatedElevation(
            at: markerDistanceMeters,
            samples: samples
        ) else {
            return "—"
        }
        return RouteFormatting.elevation(elevation)
    }

    private func scheduleIdleReset() {
        idleResetTask?.cancel()
        idleResetTask = Task {
            try? await Task.sleep(nanoseconds: Self.inspectIdleSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            uiState.clearAltitudeInspect()
        }
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

    static func interpolatedElevation(at distance: Double, samples: [ElevationSample]) -> Double? {
        guard let first = samples.first else { return nil }
        guard let last = samples.last else { return nil }

        if distance <= first.distanceMeters { return first.elevationMeters }
        if distance >= last.distanceMeters { return last.elevationMeters }

        for index in 0..<(samples.count - 1) {
            let start = samples[index]
            let end = samples[index + 1]
            guard distance >= start.distanceMeters, distance <= end.distanceMeters else { continue }

            let span = end.distanceMeters - start.distanceMeters
            guard span > 0 else { return end.elevationMeters }

            let fraction = (distance - start.distanceMeters) / span
            return start.elevationMeters + fraction * (end.elevationMeters - start.elevationMeters)
        }

        return last.elevationMeters
    }
}

private struct ChartContent: View {
    let samples: [ElevationSample]
    let progressMeters: Double
    let markerDistanceMeters: Double
    let totalMeters: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let minElevation = samples.map(\.elevationMeters).min() ?? 0
            let maxElevation = samples.map(\.elevationMeters).max() ?? 1
            let elevationRange = max(1, maxElevation - minElevation)
            let progressX = totalMeters > 0 ? proxy.size.width * CGFloat(progressMeters / totalMeters) : 0
            let markerX = totalMeters > 0 ? proxy.size.width * CGFloat(markerDistanceMeters / totalMeters) : 0
            let markerPoint = markerPosition(
                at: markerDistanceMeters,
                in: proxy.size,
                minElevation: minElevation,
                range: elevationRange
            )
            let markerElevation = ElevationSample.interpolatedElevation(at: markerDistanceMeters, samples: samples)

            ZStack(alignment: .leading) {
                ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                    if index > 0 {
                        let previous = samples[index - 1]
                        let distanceDelta = sample.distanceMeters - previous.distanceMeters
                        if distanceDelta > 0 {
                            Path { path in
                                path.move(to: point(
                                    for: previous,
                                    in: proxy.size,
                                    minElevation: minElevation,
                                    range: elevationRange
                                ))
                                path.addLine(to: point(
                                    for: sample,
                                    in: proxy.size,
                                    minElevation: minElevation,
                                    range: elevationRange
                                ))
                            }
                            .stroke(
                                RouteAppearance.elevationGradeColor(
                                    elevationDelta: sample.elevationMeters - previous.elevationMeters,
                                    distanceDelta: distanceDelta,
                                    colorScheme: colorScheme
                                ),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                }

                if totalMeters > 0 {
                    Rectangle()
                        .fill(RouteAppearance.chartProgressFill(for: colorScheme))
                        .frame(width: progressX)

                    Rectangle()
                        .fill(.blue.opacity(0.9))
                        .frame(width: 2, height: proxy.size.height)
                        .offset(x: max(0, markerX - 1))

                    if let markerPoint, let markerElevation {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .position(markerPoint)

                        Text(RouteFormatting.elevation(markerElevation))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RouteAppearance.overlayText)
                            .position(
                                x: min(max(markerPoint.x, 24), proxy.size.width - 24),
                                y: min(markerPoint.y + 14, proxy.size.height - 8)
                            )
                    }
                }
            }
        }
    }

    private func markerPosition(
        at distance: Double,
        in size: CGSize,
        minElevation: Double,
        range: Double
    ) -> CGPoint? {
        guard totalMeters > 0,
              let elevation = ElevationSample.interpolatedElevation(at: distance, samples: samples) else {
            return nil
        }

        let x = size.width * CGFloat(distance / totalMeters)
        let normalized = (elevation - minElevation) / range
        let y = size.height * (1 - CGFloat(normalized))
        return CGPoint(x: x, y: y)
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

struct AltitudeCrownLayer: View {
    @Bindable var uiState: ActiveRouteUIState
    let routeDistance: Double
    let progressMeters: Double
    var carouselCrownFocus: FocusState<CarouselCrownFocus?>.Binding

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .focused(carouselCrownFocus, equals: .altitude)
            .altitudeCrownInteraction(
                uiState: uiState,
                routeDistance: routeDistance,
                progressMeters: progressMeters
            )
    }
}

private struct AltitudeCrownInteraction: ViewModifier {
    @Bindable var uiState: ActiveRouteUIState
    let routeDistance: Double
    let progressMeters: Double

    @State private var isSyncingCrown = false

    private var crownStep: Double {
        max(5, routeDistance / 80)
    }

    private var isCrownEnabled: Bool {
        routeDistance > 0
    }

    private var altitudeCrownBinding: Binding<Double> {
        Binding(
            get: { uiState.altitudeCrownMeters },
            set: { newValue in
                guard !isSyncingCrown else {
                    uiState.altitudeCrownMeters = newValue
                    return
                }
                uiState.isAltitudeScrubbing = true
                uiState.altitudeCrownMeters = newValue
            }
        )
    }

    func body(content: Content) -> some View {
        if isCrownEnabled {
            content
                .focusable(true)
                .digitalCrownRotation(
                    altitudeCrownBinding,
                    from: 0,
                    through: max(routeDistance, 1),
                    by: crownStep,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onAppear {
                    syncCrownToLiveProgress()
                }
                .onChange(of: progressMeters) { _, _ in
                    if !uiState.isAltitudeScrubbing {
                        syncCrownToLiveProgress()
                    }
                }
                .onChange(of: routeDistance) { _, _ in
                    uiState.altitudeCrownMeters = min(uiState.altitudeCrownMeters, max(routeDistance, 0))
                }
                .onChange(of: uiState.isAltitudeScrubbing) { _, isScrubbing in
                    if !isScrubbing {
                        syncCrownToLiveProgress()
                    }
                }
        } else {
            content
        }
    }

    private var clampedProgress: Double {
        min(max(progressMeters, 0), max(routeDistance, 0))
    }

    private func syncCrownToLiveProgress() {
        isSyncingCrown = true
        uiState.altitudeCrownMeters = clampedProgress
        isSyncingCrown = false
    }
}

private extension View {
    func altitudeCrownInteraction(
        uiState: ActiveRouteUIState,
        routeDistance: Double,
        progressMeters: Double
    ) -> some View {
        modifier(AltitudeCrownInteraction(
            uiState: uiState,
            routeDistance: routeDistance,
            progressMeters: progressMeters
        ))
    }
}
