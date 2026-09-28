import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// What a set of training zones divides up.
public enum WorkoutZoneMetric: String, Codable, Sendable, CaseIterable {
    case heartRate
    case cyclingPower

    /// Zones worth asking HealthKit for: power only means something on a bike.
    public static func metrics(for activityKind: ActivityKind) -> [WorkoutZoneMetric] {
        switch activityKind.speedCategory {
        case .running: [.heartRate]
        case .cycling: [.heartRate, .cyclingPower]
        }
    }

    public var displayName: String {
        switch self {
        case .heartRate: "Heart Rate Zones"
        case .cyclingPower: "Power Zones"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .heartRate: "bpm"
        case .cyclingPower: "W"
        }
    }

    public var systemImage: String {
        switch self {
        case .heartRate: "heart.fill"
        case .cyclingPower: "bolt.fill"
        }
    }
}

/// Training zones for one metric and the time spent in each, as HealthKit recorded them.
///
/// Zones are indexed from 0 here; people see them as Zone 1…N.
public struct WorkoutZones: Codable, Sendable, Hashable {
    /// Who defined the zones: computed by Health, set in Health settings, or supplied by an app.
    public enum Source: String, Codable, Sendable {
        case system
        case user
        case app
    }

    public let metric: WorkoutZoneMetric
    /// Where zones 2…N start, ascending, in the metric's unit (bpm or watts). Zone 1 has no lower
    /// bound and the last zone no upper bound, so there is one boundary fewer than zones.
    public let boundaries: [Double]
    /// Seconds spent in each zone, one entry per zone.
    public let secondsInZone: [Double]
    public let source: Source?

    /// Fails unless the boundaries are finite and strictly ascending. Missing or extra durations
    /// are padded with zero or dropped, so the counts always match.
    public init?(
        metric: WorkoutZoneMetric,
        boundaries: [Double],
        secondsInZone: [Double] = [],
        source: Source? = nil
    ) {
        guard !boundaries.isEmpty,
              boundaries.allSatisfy(\.isFinite),
              zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return nil
        }
        let zoneCount = boundaries.count + 1
        let durations = secondsInZone.prefix(zoneCount).map { $0.isFinite ? max(0, $0) : 0 }

        self.metric = metric
        self.boundaries = boundaries
        self.secondsInZone = durations + Array(repeating: 0, count: zoneCount - durations.count)
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let zones = WorkoutZones(
            metric: try container.decode(WorkoutZoneMetric.self, forKey: .metric),
            boundaries: try container.decode([Double].self, forKey: .boundaries),
            secondsInZone: try container.decodeIfPresent([Double].self, forKey: .secondsInZone) ?? [],
            source: try container.decodeIfPresent(Source.self, forKey: .source)
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .boundaries,
                in: container,
                debugDescription: "Zone boundaries must be finite and ascending."
            )
        }
        self = zones
    }

    public var zoneCount: Int { boundaries.count + 1 }

    public var totalSeconds: Double { secondsInZone.reduce(0, +) }

    /// Zone a reading falls in. A reading on a boundary belongs to the zone above it.
    public func zoneIndex(for value: Double) -> Int {
        boundaries.firstIndex { value < $0 } ?? boundaries.count
    }

    /// Share of the recorded time spent in a zone, 0…1.
    public func fraction(ofZone index: Int) -> Double {
        let total = totalSeconds
        guard total > 0, secondsInZone.indices.contains(index) else { return 0 }
        return secondsInZone[index] / total
    }

    /// Zone with the most time; nil until any time is recorded.
    public var dominantZoneIndex: Int? {
        guard totalSeconds > 0 else { return nil }
        return secondsInZone.indices.max { secondsInZone[$0] < secondsInZone[$1] }
    }

    public static func name(ofZone index: Int) -> String {
        "Zone \(index + 1)"
    }

    /// Range of a zone without its unit: "< 120", "120–139" or "≥ 170".
    ///
    /// Whole-number zones end one below the next zone's start, so neighbours don't appear to overlap.
    public func rangeLabel(ofZone index: Int) -> String {
        guard index > 0 else { return "< \(Self.format(boundaries[0]))" }
        guard index < boundaries.count else { return "≥ \(Self.format(boundaries[boundaries.count - 1]))" }

        let lower = boundaries[index - 1]
        var upper = boundaries[index]
        if lower.rounded() == lower, upper.rounded() == upper, upper - 1 >= lower {
            upper -= 1
        }
        return "\(Self.format(lower))–\(Self.format(upper))"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// Zone colours from easy to hard: blue, green, yellow, orange, red, spread over however many
/// zones there are, so the track, bars and live badge all agree.
public enum WorkoutZonePalette {
    public typealias RGB = (red: Double, green: Double, blue: Double)

    private static let stops: [RGB] = [
        (0.27, 0.62, 1.00),
        (0.20, 0.80, 0.47),
        (1.00, 0.80, 0.12),
        (1.00, 0.55, 0.12),
        (1.00, 0.25, 0.32)
    ]

    public static func rgb(forZone index: Int, of count: Int) -> RGB {
        guard count > 1 else { return stops[0] }
        let clamped = min(max(index, 0), count - 1)
        let position = Double(clamped) / Double(count - 1) * Double(stops.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, stops.count - 1)
        let t = position - Double(lower)
        let a = stops[lower]
        let b = stops[upper]
        return (
            a.red + (b.red - a.red) * t,
            a.green + (b.green - a.green) * t,
            a.blue + (b.blue - a.blue) * t
        )
    }
}

#if canImport(SwiftUI)
extension WorkoutZonePalette {
    public static func color(forZone index: Int, of count: Int) -> Color {
        let rgb = rgb(forZone: index, of: count)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension WorkoutZones {
    public func color(forZone index: Int) -> Color {
        WorkoutZonePalette.color(forZone: index, of: zoneCount)
    }
}
#endif
