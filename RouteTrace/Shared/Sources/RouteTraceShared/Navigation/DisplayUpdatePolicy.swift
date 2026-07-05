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

        let now = Date()
        if now.timeIntervalSince(lastRecenterAt) >= policy.recenterMinInterval {
            return true
        }

        if let last = lastRecenterCoordinate {
            let distance = MapMath.haversineMeters(from: last, to: coordinate)
            if distance >= policy.recenterMinDistanceMeters {
                return true
            }
        } else {
            return true
        }

        return false
    }

    public func recordRecenter(at coordinate: GeoCoordinate) {
        lastRecenterAt = Date()
        lastRecenterCoordinate = coordinate
    }
}
