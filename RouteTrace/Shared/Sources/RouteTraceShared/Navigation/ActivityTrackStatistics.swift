import Foundation

public enum ActivityTrackStatistics {
    /// Distance actually covered, summed within continuous recording periods only, so the jump
    /// across a pause or a GPS dropout is not counted as movement.
    public static func gpsDistanceMeters(from trackPoints: [TrackPoint]) -> Double {
        guard trackPoints.count >= 2 else { return 0 }

        var total = 0.0
        for segment in TrackSegmentSplitter.continuousSegments(from: trackPoints) where segment.count >= 2 {
            for index in 1..<segment.count {
                total += MapMath.haversineMeters(
                    from: segment[index - 1].coordinate,
                    to: segment[index].coordinate
                )
            }
        }
        return total
    }

    public static func routeProgressMeters(
        from trackPoints: [TrackPoint],
        fallbackRouteProgress: Double
    ) -> Double {
        let snappedMax = trackPoints.compactMap(\.snappedDistanceFromStartMeters).max() ?? 0
        return max(snappedMax, fallbackRouteProgress)
    }

    public static func elevationGainMeters(
        from trackPoints: [TrackPoint],
        fallback: Double?
    ) -> Double? {
        let altitudes = trackPoints.compactMap(\.altitudeMeters)
        guard altitudes.count >= 2 else { return fallback }

        let gain = ElevationStatistics.gainAndLoss(
            of: altitudes,
            thresholdMeters: ElevationStatistics.recordedThresholdMeters
        ).gain
        return gain > 0 ? gain : fallback
    }

    /// Distance-indexed samples for charts, thinned to at most `maxSamples` points.
    public static func profileSamples(
        from trackPoints: [TrackPoint],
        maxSamples: Int = 400
    ) -> [ActivityProfileSample] {
        guard trackPoints.count >= 2 else { return [] }

        var samples: [ActivityProfileSample] = []
        samples.reserveCapacity(trackPoints.count)
        var cumulative = 0.0
        var previous: TrackPoint?

        for point in trackPoints {
            if let previous {
                let step = MapMath.haversineMeters(from: previous.coordinate, to: point.coordinate)
                let gap = point.timestamp.timeIntervalSince(previous.timestamp)
                // Pauses and dropouts are not distance travelled (matches gpsDistanceMeters).
                if gap <= TrackSegmentSplitter.defaultTimeGapSeconds,
                   step <= TrackSegmentSplitter.defaultSpatialJumpMeters {
                    cumulative += step
                }
            }
            samples.append(ActivityProfileSample(
                distanceMeters: cumulative,
                elapsedSeconds: point.timestamp.timeIntervalSince(trackPoints[0].timestamp),
                altitudeMeters: point.altitudeMeters,
                heartRateBPM: point.heartRateBPM,
                speedMetersPerSecond: point.speedMetersPerSecond
            ))
            previous = point
        }

        return ProfileDownsampler.downsample(samples, maxCount: maxSamples)
    }

    /// True when route-snapped progress differs from GPS distance by more than 5%.
    public static func routeProgressDiffersMeaningfully(
        gpsDistanceMeters: Double,
        routeProgressMeters: Double
    ) -> Bool {
        guard gpsDistanceMeters > 0, routeProgressMeters > 0 else { return false }
        let difference = abs(routeProgressMeters - gpsDistanceMeters)
        return difference / gpsDistanceMeters > 0.05
    }

    public static func averageSpeedMetersPerSecond(
        gpsDistanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Double? {
        guard elapsedSeconds > 0, gpsDistanceMeters > 0 else { return nil }
        return gpsDistanceMeters / elapsedSeconds
    }
}

public struct ActivityProfileSample: Sendable, Hashable {
    public let distanceMeters: Double
    public let elapsedSeconds: TimeInterval
    public let altitudeMeters: Double?
    public let heartRateBPM: Double?
    public let speedMetersPerSecond: Double?

    public init(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        altitudeMeters: Double?,
        heartRateBPM: Double?,
        speedMetersPerSecond: Double?
    ) {
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.altitudeMeters = altitudeMeters
        self.heartRateBPM = heartRateBPM
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

/// Evenly thins long series for charting; drawing thousands of marks is slow on iPhone and Watch.
public enum ProfileDownsampler {
    public static func downsample<T>(_ values: [T], maxCount: Int) -> [T] {
        guard maxCount >= 2, values.count > maxCount else { return values }
        let stride = Double(values.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { values[Int((Double($0) * stride).rounded())] }
    }
}
