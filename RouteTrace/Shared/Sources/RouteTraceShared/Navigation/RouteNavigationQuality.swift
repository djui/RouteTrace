import Foundation

public enum RouteNavigationQuality {
    public static let sparsePointCountThreshold = 10
    public static let sparseDistanceThresholdMeters = 5_000.0

    public static func warning(
        distanceMeters: Double,
        originalPointCount: Int,
        simplifiedPointCount: Int
    ) -> String? {
        guard distanceMeters > sparseDistanceThresholdMeters,
              simplifiedPointCount < sparsePointCountThreshold else {
            return nil
        }

        let distanceLabel = RouteFormatting.distance(distanceMeters)
        return "This route has only \(simplifiedPointCount) navigation points across \(distanceLabel). Progress and off-route detection may be less accurate."
    }
}
