import RouteTraceShared
import SwiftUI

/// Workout-style metrics: a few large numbers readable at a glance, details below.
struct MetricsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState
    var carouselCrownFocus: FocusState<CarouselCrownFocus?>.Binding

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var speedMode: SpeedDisplayMode {
        preferences.speedDisplayMode(for: viewModel.activityKind)
    }

    private var isCrownEnabled: Bool {
        uiState.selectedPage == .metrics && !uiState.isMapFocus
    }

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MetricLine(
                        value: RouteFormatting.duration(viewModel.elapsedSeconds),
                        tint: viewModel.isPaused ? .orange : .yellow,
                        size: 36
                    )
                    MetricLine(
                        value: MetricText.distanceValue(viewModel.gpsDistanceMeters),
                        unit: MetricText.distanceUnit(viewModel.gpsDistanceMeters)
                    )
                    MetricLine(
                        value: MetricText.speedValue(viewModel.currentSpeedMetersPerSecond, mode: speedMode),
                        unit: (speedMode == .pace ? RouteFormatting.paceSymbol() : RouteFormatting.speedSymbol()).uppercased(),
                        caption: speedMode == .pace ? "PACE" : "SPEED"
                    )
                    MetricLine(
                        value: viewModel.workoutService.heartRateBPM.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "BPM",
                        symbol: "heart.fill",
                        symbolTint: .red
                    )

                    Divider()
                        .padding(.vertical, 8)

                    detailRow("Remaining", RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0), "flag.checkered")
                    detailRow("Route", "\(Int((viewModel.progressFraction * 100).rounded()))%", "point.bottomleft.forward.to.point.topright.scurvepath")
                    detailRow("Climbed", RouteFormatting.elevation(viewModel.elevationGainMeters ?? 0), "arrow.up.right")
                    detailRow(
                        speedMode.averageLabel,
                        RouteFormatting.speedOrPace(viewModel.averageSpeedMetersPerSecond, mode: speedMode),
                        "gauge.with.dots.needle.50percent"
                    )
                    detailRow("Detours", "\(viewModel.recording.offRouteEvents.count)", "location.slash")
                }
                .padding(.horizontal, 10)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .routeScreenBackground()
            .focusable(isCrownEnabled)
            .focused(carouselCrownFocus, equals: .metrics)
        }
    }

    private func detailRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

struct MetricLine: View {
    let value: String
    var unit: String?
    var caption: String?
    var symbol: String?
    var symbolTint: Color = .secondary
    var tint: Color = .primary
    var size: CGFloat = 32

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(symbolTint)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Number and unit separately, for large-number layouts.
enum MetricText {
    static func distanceValue(_ meters: Double, units: DisplayUnits = UnitPreference.shared.units) -> String {
        if usesLargeUnit(meters, units: units) {
            return RouteFormatting.distanceValue(meters, units: units).formatted(.number.precision(.fractionLength(2)))
        }
        let small = units.distance == .miles ? meters / DisplayUnits.metersPerFoot : meters
        return small.formatted(.number.precision(.fractionLength(0)))
    }

    static func distanceUnit(_ meters: Double, units: DisplayUnits = UnitPreference.shared.units) -> String {
        switch units.distance {
        case .kilometers: usesLargeUnit(meters, units: units) ? "KM" : "M"
        case .miles: usesLargeUnit(meters, units: units) ? "MI" : "FT"
        }
    }

    static func speedValue(
        _ metersPerSecond: Double?,
        mode: SpeedDisplayMode,
        units: DisplayUnits = UnitPreference.shared.units
    ) -> String {
        guard let metersPerSecond, metersPerSecond > 0.3 else {
            return mode == .pace ? "--:--" : "--"
        }
        switch mode {
        case .pace:
            let secondsPerUnit = units.metersPerDistanceUnit / metersPerSecond
            guard secondsPerUnit < 60 * 60 else { return "--:--" }
            let total = Int(secondsPerUnit.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        case .speed:
            return (metersPerSecond * 3600 / units.metersPerDistanceUnit).formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// Kilometres from 1 km, miles from a tenth of a mile; metres or feet below that.
    private static func usesLargeUnit(_ meters: Double, units: DisplayUnits) -> Bool {
        switch units.distance {
        case .kilometers: meters >= 1000
        case .miles: meters / DisplayUnits.metersPerMile >= 0.1
        }
    }
}
