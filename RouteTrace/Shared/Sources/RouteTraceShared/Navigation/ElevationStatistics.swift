import Foundation

/// Elevation gain/loss with a dead band, so sensor and DEM noise does not inflate totals.
///
/// Summing every positive delta of a noisy profile overstates climbing badly (a flat route
/// quantized to 1 m alternates 35/36/35/36… and "gains" a meter per point). Changes only count
/// once the elevation has moved by at least `thresholdMeters` from the last committed reference.
public enum ElevationStatistics {
    /// Planned routes carry smooth DEM elevation, so a small band removes quantization noise only.
    public static let routeThresholdMeters = 2.0
    /// Watch altitude (GPS fused with the barometer) jitters by a few meters between fixes.
    public static let recordedThresholdMeters = 3.0

    public static func gainAndLoss(
        of elevations: [Double],
        thresholdMeters: Double
    ) -> (gain: Double, loss: Double) {
        var accumulator = ElevationAccumulator(thresholdMeters: thresholdMeters)
        for elevation in elevations {
            accumulator.add(elevation)
        }
        return (accumulator.totalGainMeters, accumulator.totalLossMeters)
    }
}

/// Incremental dead-band accumulator, usable for live recording and batch statistics.
public struct ElevationAccumulator: Codable, Sendable, Equatable {
    public let thresholdMeters: Double
    public private(set) var committedGainMeters: Double = 0
    public private(set) var committedLossMeters: Double = 0
    private var reference: Double?
    private var latest: Double?

    public init(thresholdMeters: Double = ElevationStatistics.recordedThresholdMeters) {
        self.thresholdMeters = thresholdMeters
    }

    public var hasSamples: Bool { latest != nil }

    /// Gain including the not-yet-committed movement since the last reference point.
    public var totalGainMeters: Double {
        committedGainMeters + max(0, pendingDelta)
    }

    /// Loss including the not-yet-committed movement since the last reference point.
    public var totalLossMeters: Double {
        committedLossMeters + max(0, -pendingDelta)
    }

    private var pendingDelta: Double {
        guard let reference, let latest else { return 0 }
        return latest - reference
    }

    public mutating func add(_ elevation: Double) {
        guard elevation.isFinite else { return }
        latest = elevation
        guard let reference else {
            self.reference = elevation
            return
        }

        let delta = elevation - reference
        if delta >= thresholdMeters {
            committedGainMeters += delta
            self.reference = elevation
        } else if -delta >= thresholdMeters {
            committedLossMeters += -delta
            self.reference = elevation
        }
    }
}
