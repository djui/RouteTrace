import Foundation

public enum ActivityTrackStatistics {
    public static func gpsDistanceMeters(from trackPoints: [TrackPoint]) -> Double {
        guard trackPoints.count >= 2 else { return 0 }

        var total = 0.0
        for index in 1..<trackPoints.count {
            total += MapMath.haversineMeters(
                from: trackPoints[index - 1].coordinate,
                to: trackPoints[index].coordinate
            )
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

        var gain = 0.0
        for index in 1..<altitudes.count {
            let delta = altitudes[index] - altitudes[index - 1]
            if delta > 0 {
                gain += delta
            }
        }
        return gain > 0 ? gain : fallback
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
