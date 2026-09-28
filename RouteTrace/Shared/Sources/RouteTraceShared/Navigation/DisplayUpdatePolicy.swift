import Foundation

public struct DisplayUpdatePolicy: Sendable, Equatable {
    public let recenterMinInterval: TimeInterval
    public let recenterMinDistanceMeters: Double
    public let allowsHeadingUpRotation: Bool
    public let updatesWhenMapHidden: Bool

    public init(
        recenterMinInterval: TimeInterval,
        recenterMinDistanceMeters: Double,
        allowsHeadingUpRotation: Bool,
        updatesWhenMapHidden: Bool
    ) {
        self.recenterMinInterval = recenterMinInterval
        self.recenterMinDistanceMeters = recenterMinDistanceMeters
        self.allowsHeadingUpRotation = allowsHeadingUpRotation
        self.updatesWhenMapHidden = updatesWhenMapHidden
    }

    public var allowsImmediateRecenter: Bool {
        recenterMinInterval <= 0 && recenterMinDistanceMeters <= 0
    }
}

@MainActor
public final class DisplayUpdateCoordinator {
    private var lastRecenterAt: Date = .distantPast
    private var lastRecenterCoordinate: GeoCoordinate?

    public init() {}

    public func reset() {
        lastRecenterAt = .distantPast
        lastRecenterCoordinate = nil
    }

    /// Recenters only once both the minimum interval has passed and the position moved by the
    /// minimum distance, so a stationary runner's GPS jitter doesn't keep redrawing the map.
    public func shouldRecenter(
        policy: DisplayUpdatePolicy,
        coordinate: GeoCoordinate,
        isMapVisible: Bool,
        followEnabled: Bool
    ) -> Bool {
        guard followEnabled else { return false }
        if !isMapVisible && !policy.updatesWhenMapHidden {
            return false
        }
        if policy.allowsImmediateRecenter {
            return true
        }
        guard let last = lastRecenterCoordinate else {
            return true
        }

        let intervalElapsed = Date().timeIntervalSince(lastRecenterAt) >= policy.recenterMinInterval
        let movedEnough = MapMath.haversineMeters(from: last, to: coordinate) >= policy.recenterMinDistanceMeters
        return intervalElapsed && movedEnough
    }

    public func recordRecenter(at coordinate: GeoCoordinate) {
        lastRecenterAt = Date()
        lastRecenterCoordinate = coordinate
    }
}
