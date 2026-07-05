import Foundation

public struct DisplayCoordinateSmoother: Sendable {
    public static let maxBlendWeight = 0.6
    public static let emaAlpha = 0.35

    private var smoothed: GeoCoordinate?

    public init() {}

    public mutating func reset() {
        smoothed = nil
    }

    public mutating func coordinate(
        raw: GeoCoordinate,
        projected: GeoCoordinate?,
        horizontalAccuracyMeters: Double,
        isOffRoute: Bool,
        recordingAccuracyThresholdMeters: Double
    ) -> GeoCoordinate {
        guard !isOffRoute,
              horizontalAccuracyMeters <= recordingAccuracyThresholdMeters,
              let projected else {
            smoothed = raw
            return raw
        }

        let accuracyRatio = min(horizontalAccuracyMeters / recordingAccuracyThresholdMeters, 1)
        let blendWeight = Self.maxBlendWeight * (1 - accuracyRatio)
        let target = GeoCoordinate(
            latitude: raw.latitude + (projected.latitude - raw.latitude) * blendWeight,
            longitude: raw.longitude + (projected.longitude - raw.longitude) * blendWeight
        )

        if let previous = smoothed {
            smoothed = GeoCoordinate(
                latitude: previous.latitude + Self.emaAlpha * (target.latitude - previous.latitude),
                longitude: previous.longitude + Self.emaAlpha * (target.longitude - previous.longitude)
            )
        } else {
            smoothed = target
        }

        return smoothed ?? raw
    }
}
