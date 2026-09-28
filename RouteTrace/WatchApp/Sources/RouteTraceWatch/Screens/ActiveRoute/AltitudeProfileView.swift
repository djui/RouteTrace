import RouteTraceShared
import SwiftUI

struct AltitudeProfileView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var idleResetTask: Task<Void, Never>?

    private var progressMeters: Double {
        viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
    }

    private var profile: RouteElevationProfile? {
        viewModel.elevationProfile
    }

    private var crownEnabled: Bool {
        uiState.selectedPage == .altitude && !uiState.isMapFocus && profile != nil
    }

    /// The inspected distance: the crown position while scrubbing, otherwise the runner.
    private var markerMeters: Double {
        uiState.isAltitudeScrubbing ? uiState.altitudeCrownMeters : progressMeters
    }

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else {
                ContentUnavailableView {
                    Label("No Elevation", systemImage: "mountain.2")
                } description: {
                    Text("This route’s GPX file has no elevation data.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .routeScreenBackground()
        .focusable(crownEnabled)
        .focused($crownFocused)
        .digitalCrownRotation(
            crownBinding,
            from: 0,
            through: max(profile?.totalDistanceMeters ?? 1, 1),
            by: max(10, (profile?.totalDistanceMeters ?? 0) / 100),
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { requestCrownFocus() }
        .onChange(of: uiState.selectedPage) { _, _ in requestCrownFocus() }
        .onDisappear {
            idleResetTask?.cancel()
            uiState.clearAltitudeInspect()
        }
    }

    private var crownBinding: Binding<Double> {
        Binding(
            get: { uiState.isAltitudeScrubbing ? uiState.altitudeCrownMeters : progressMeters },
            set: { value in
                guard crownEnabled else { return }
                uiState.altitudeCrownMeters = value
                uiState.isAltitudeScrubbing = true
                scheduleReturnToLive()
            }
        )
    }

    private func content(_ profile: RouteElevationProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(profile)

            AltitudeChart(
                profile: profile,
                progressMeters: progressMeters,
                markerMeters: markerMeters,
                isScrubbing: uiState.isAltitudeScrubbing,
                isDimmed: isLuminanceReduced
            )
            .frame(minHeight: 72, maxHeight: .infinity)

            HStack(alignment: .firstTextBaseline) {
                stat("To climb", RouteFormatting.elevation(profile.remainingAscent(after: progressMeters)))
                Spacer(minLength: 4)
                stat("Climbed", RouteFormatting.elevation(viewModel.elevationGainMeters ?? 0), alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func header(_ profile: RouteElevationProfile) -> some View {
        let elevation = RouteFormatting.elevation(profile.elevation(at: markerMeters))
        if uiState.isAltitudeScrubbing {
            let ahead = uiState.altitudeCrownMeters - progressMeters
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(elevation)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(ahead >= 0 ? "in \(RouteFormatting.distance(ahead))" : "\(RouteFormatting.distance(-ahead)) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(elevation)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }

    private func stat(_ title: String, _ value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }

    private func requestCrownFocus() {
        guard crownEnabled else {
            crownFocused = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if crownEnabled { crownFocused = true }
        }
    }

    /// Scrubbing is a quick look ahead; the marker returns to the runner after a pause.
    private func scheduleReturnToLive() {
        idleResetTask?.cancel()
        idleResetTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                uiState.clearAltitudeInspect()
            }
        }
    }
}

/// Elevation profile colored by gradient, with the part already run dimmed.
private struct AltitudeChart: View {
    let profile: RouteElevationProfile
    let progressMeters: Double
    let markerMeters: Double
    let isScrubbing: Bool
    let isDimmed: Bool

    var body: some View {
        Canvas { context, size in
            let range = max(profile.maxElevation - profile.minElevation, 20)
            let floor = profile.minElevation - range * 0.08
            let ceiling = profile.minElevation + range * 1.08
            let total = max(profile.totalDistanceMeters, 1)

            func point(_ sample: RouteElevationProfile.Sample) -> CGPoint {
                CGPoint(
                    x: size.width * sample.distanceMeters / total,
                    y: size.height * (1 - (sample.elevationMeters - floor) / (ceiling - floor))
                )
            }

            // Area under the profile.
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            for sample in profile.samples {
                area.addLine(to: point(sample))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [Color.cyan.opacity(isDimmed ? 0.15 : 0.35), Color.cyan.opacity(0.02)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            // Line segments tinted by steepness.
            for (a, b) in zip(profile.samples, profile.samples.dropFirst()) {
                var segment = Path()
                segment.move(to: point(a))
                segment.addLine(to: point(b))
                let run = b.distanceMeters - a.distanceMeters
                let grade = run > 0 ? (b.elevationMeters - a.elevationMeters) / run : 0
                context.stroke(
                    segment,
                    with: .color(isDimmed ? .gray : Self.color(forGrade: grade)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
            }

            // Already covered: dim it.
            let progressX = size.width * min(1, progressMeters / total)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: progressX, height: size.height)),
                with: .color(.black.opacity(0.45))
            )

            // Marker.
            let markerX = size.width * min(1, max(0, markerMeters / total))
            let elevation = profile.elevation(at: markerMeters) ?? profile.minElevation
            let markerY = size.height * (1 - (elevation - floor) / (ceiling - floor))
            context.stroke(
                Path { $0.move(to: CGPoint(x: markerX, y: 0)); $0.addLine(to: CGPoint(x: markerX, y: size.height)) },
                with: .color(isScrubbing ? .cyan : .white.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, dash: isScrubbing ? [3, 3] : [])
            )
            let dot = CGRect(x: markerX - 5, y: markerY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(isScrubbing ? .cyan : RouteAppearance.routeColor))
            context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 2)
        }
        .accessibilityLabel("Elevation profile")
    }

    /// Flat is green, steep climbs turn orange and red, descents stay neutral.
    static func color(forGrade grade: Double) -> Color {
        switch grade {
        case ..<(-0.02): Color.white.opacity(0.75)
        case ..<0.03: .green
        case ..<0.07: .yellow
        case ..<0.12: .orange
        default: .red
        }
    }
}
