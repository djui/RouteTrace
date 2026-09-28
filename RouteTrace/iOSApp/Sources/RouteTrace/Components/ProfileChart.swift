import Charts
import RouteTraceShared
import SwiftUI

struct ProfilePoint: Identifiable, Hashable {
    let id: Int
    let distanceKm: Double
    let value: Double
}

/// Distance-based profile (elevation, heart rate, …) with drag-to-inspect.
///
/// Series are downsampled and the axis domains computed once up front; the previous charts
/// recomputed every sample for every mark, which made long activities take seconds to render.
struct ProfileChart: View {
    let points: [ProfilePoint]
    let color: Color
    let seriesName: String
    let unit: String
    var height: CGFloat = 190
    var fillsArea = true

    private let valueDomain: ClosedRange<Double>
    private let distanceDomain: ClosedRange<Double>

    /// Explicit, because the default trailing-axis labels were barely legible in Dark Mode.
    private static let axisLabelColor = Color(uiColor: .secondaryLabel)

    @State private var selectedDistanceKm: Double?

    init(
        points: [ProfilePoint],
        color: Color,
        seriesName: String,
        unit: String,
        height: CGFloat = 190,
        fillsArea: Bool = true,
        maxPoints: Int = 300
    ) {
        let thinned = ProfileDownsampler.downsample(points, maxCount: maxPoints)
        self.points = thinned
        self.color = color
        self.seriesName = seriesName
        self.unit = unit
        self.height = height
        self.fillsArea = fillsArea

        let values = thinned.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max(maxValue - minValue, 10) * 0.12
        valueDomain = (minValue - padding)...(maxValue + padding)
        distanceDomain = 0...max(thinned.last?.distanceKm ?? 1, 0.01)
    }

    private var selectedPoint: ProfilePoint? {
        guard let selectedDistanceKm else { return nil }
        return points.min { abs($0.distanceKm - selectedDistanceKm) < abs($1.distanceKm - selectedDistanceKm) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                if fillsArea {
                    AreaMark(
                        x: .value("Distance", point.distanceKm),
                        yStart: .value("Baseline", valueDomain.lowerBound),
                        yEnd: .value(seriesName, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.32), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                LineMark(
                    x: .value("Distance", point.distanceKm),
                    y: .value(seriesName, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.distanceKm))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        selectionCallout(for: selectedPoint)
                    }

                PointMark(
                    x: .value("Distance", selectedPoint.distanceKm),
                    y: .value(seriesName, selectedPoint.value)
                )
                .foregroundStyle(color)
                .symbolSize(70)
            }
        }
        .chartXScale(domain: distanceDomain)
        .chartYScale(domain: valueDomain)
        .chartXSelection(value: $selectedDistanceKm)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text("\(km.formatted(.number.precision(.fractionLength(0...1)))) km")
                    }
                }
                .foregroundStyle(Self.axisLabelColor)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number.rounded())) \(unit)")
                    }
                }
                .foregroundStyle(Self.axisLabelColor)
            }
        }
        .frame(height: height)
        .accessibilityLabel(seriesName)
        .accessibilityValue(accessibilitySummary)
    }

    private func selectionCallout(for point: ProfilePoint) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(point.value.rounded())) \(unit)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(RouteFormatting.distance(point.distanceKm * 1000))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var accessibilitySummary: String {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "" }
        return "From \(Int(low.rounded())) to \(Int(high.rounded())) \(unit) over \(RouteFormatting.distance((points.last?.distanceKm ?? 0) * 1000))"
    }
}

extension ProfilePoint {
    static func elevation(from route: [RoutePoint]) -> [ProfilePoint] {
        route.compactMap { point in
            guard let elevation = point.elevationMeters else { return nil }
            return ProfilePoint(id: point.id, distanceKm: point.distanceFromStartMeters / 1000, value: elevation)
        }
    }

    static func series(
        from samples: [ActivityProfileSample],
        value: (ActivityProfileSample) -> Double?
    ) -> [ProfilePoint] {
        samples.enumerated().compactMap { index, sample in
            guard let number = value(sample), number.isFinite else { return nil }
            return ProfilePoint(id: index, distanceKm: sample.distanceMeters / 1000, value: number)
        }
    }
}

extension Array where Element == ProfilePoint {
    /// Centered moving average; sensor series such as heart rate jitter sample to sample.
    func smoothed(window: Int) -> [ProfilePoint] {
        guard window > 1, count > window else { return self }
        let half = window / 2
        var prefix = [0.0]
        prefix.reserveCapacity(count + 1)
        for point in self {
            prefix.append(prefix[prefix.count - 1] + point.value)
        }
        return indices.map { index in
            let lower = Swift.max(0, index - half)
            let upper = Swift.min(count - 1, index + half)
            let mean = (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
            return ProfilePoint(id: self[index].id, distanceKm: self[index].distanceKm, value: mean)
        }
    }
}
