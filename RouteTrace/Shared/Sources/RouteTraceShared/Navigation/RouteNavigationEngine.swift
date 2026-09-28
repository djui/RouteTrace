import Foundation

public struct RouteNavigationUpdate: Sendable {
    public let progressDistanceMeters: Double
    public let distanceRemainingMeters: Double
    public let offRouteDistanceMeters: Double
    public let isOffRoute: Bool
    public let isCriticallyOffRoute: Bool
    public let nextCue: RouteCue?
    public let distanceToNextCueMeters: Double?
    public let segmentIndex: Int
    public let projectedCoordinate: GeoCoordinate
}

public final class RouteNavigationEngine: @unchecked Sendable {
    private let route: [RoutePoint]
    private let cues: [RouteCue]
    private let activityKind: ActivityKind
    private let totalDistanceMeters: Double

    private var lastSegmentIndex = 0
    private var lastProgressMeters = 0.0
    private var completedTrack: [GeoCoordinate] = []
    private var actualTrack: [GeoCoordinate] = []
    private var offRouteUpdateCount = 0
    private var hasMatchedRoute = false

    private static let defaultSearchWindow = 100
    private static let offRouteUpdatesBeforeWidening = 3
    /// Prefer the earliest matching segment within this margin of the closest one, so loops,
    /// out-and-backs and crossings are followed in order instead of skipping ahead.
    private static let continuityToleranceMeters = 20.0

    public init(routePackage: RoutePackage) {
        self.route = routePackage.route
        self.cues = routePackage.cues
        self.activityKind = routePackage.activityHint
        self.totalDistanceMeters = routePackage.navigationDistanceMeters
    }

    public var breadcrumb: [GeoCoordinate] {
        completedTrack
    }

    public var gpsTrack: [GeoCoordinate] {
        actualTrack
    }

    /// - Parameter includeTracks: Pass `false` when the GPS track is persisted elsewhere
    ///   (e.g. in the activity recording) to keep the saved state small.
    public func exportState(includeTracks: Bool = true) -> PersistedNavigationEngineState {
        PersistedNavigationEngineState(
            lastSegmentIndex: lastSegmentIndex,
            lastProgressMeters: lastProgressMeters,
            completedTrack: includeTracks ? completedTrack : [],
            actualTrack: includeTracks ? actualTrack : []
        )
    }

    public func restoreState(_ state: PersistedNavigationEngineState) {
        // Clamp so a state saved for a different version of the route cannot index out of range.
        lastSegmentIndex = min(max(0, state.lastSegmentIndex), max(0, route.count - 2))
        lastProgressMeters = min(max(0, state.lastProgressMeters), totalDistanceMeters)
        completedTrack = state.completedTrack
        actualTrack = state.actualTrack
        hasMatchedRoute = state.lastProgressMeters > 0 || !state.completedTrack.isEmpty
    }

    public func reset() {
        lastSegmentIndex = 0
        lastProgressMeters = 0
        completedTrack = []
        actualTrack = []
        offRouteUpdateCount = 0
        hasMatchedRoute = false
    }

    public func previewUpdate(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double?
    ) -> RouteNavigationUpdate? {
        computeUpdate(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            persist: false
        )
    }

    public func update(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double?
    ) -> RouteNavigationUpdate? {
        computeUpdate(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            persist: true
        )
    }

    public func makeInitialSnapshot(routeId: UUID) -> NavigationSnapshot {
        let progress = lastProgressMeters
        let nextCue = cues.first { $0.distanceFromStartMeters > progress + 5 }
        let distanceToCue = nextCue.map { max(0, $0.distanceFromStartMeters - progress) }
        let projectedCoordinate: GeoCoordinate
        if let first = route.first {
            projectedCoordinate = GeoCoordinate(latitude: first.latitude, longitude: first.longitude)
        } else {
            projectedCoordinate = GeoCoordinate(latitude: 0, longitude: 0)
        }

        let update = RouteNavigationUpdate(
            progressDistanceMeters: progress,
            distanceRemainingMeters: max(0, totalDistanceMeters - progress),
            offRouteDistanceMeters: 0,
            isOffRoute: false,
            isCriticallyOffRoute: false,
            nextCue: nextCue,
            distanceToNextCueMeters: distanceToCue,
            segmentIndex: lastSegmentIndex,
            projectedCoordinate: projectedCoordinate
        )

        return makeSnapshot(
            routeId: routeId,
            coordinate: nil,
            speed: nil,
            update: update
        )
    }

    private func computeUpdate(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        persist: Bool
    ) -> RouteNavigationUpdate? {
        guard MapMath.isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

        let location = GeoCoordinate(latitude: latitude, longitude: longitude)
        if persist {
            actualTrack.append(location)
        }

        // Until the first on-route fix, search the whole route so starting mid-route works.
        // After persistent off-route fixes, search the rest of the route to find where we rejoined.
        let searchStart: Int
        let searchWindow: Int
        if !hasMatchedRoute {
            searchStart = 0
            searchWindow = route.count
        } else if offRouteUpdateCount >= Self.offRouteUpdatesBeforeWidening {
            searchStart = max(0, lastSegmentIndex - 2)
            searchWindow = route.count
        } else {
            searchStart = max(0, lastSegmentIndex - 2)
            searchWindow = Self.defaultSearchWindow
        }

        guard let nearest = MapMath.nearestPointOnPolyline(
            to: location,
            route: route,
            searchStartIndex: searchStart,
            searchWindow: searchWindow,
            preferEarliestWithinMeters: Self.continuityToleranceMeters
        ) else { return nil }

        let accuracyAdjustedOffRoute = max(0, nearest.distanceMeters - max(0, horizontalAccuracyMeters - 10))
        let warningThreshold = activityKind.offRouteWarningMeters
        let criticalThreshold = activityKind.offRouteCriticalMeters

        // Far from the route the nearest segment says little about progress; hold it until we rejoin.
        let isNearRoute = accuracyAdjustedOffRoute <= criticalThreshold * 2
        let advances = isNearRoute && nearest.segmentIndex >= lastSegmentIndex
        let progress = advances ? max(lastProgressMeters, nearest.distanceAlongRouteMeters) : lastProgressMeters

        if persist, advances {
            lastSegmentIndex = nearest.segmentIndex
            lastProgressMeters = progress
            completedTrack.append(nearest.projectedCoordinate)
            hasMatchedRoute = true
        }

        let remaining = max(0, totalDistanceMeters - progress)
        let isOffRoute = accuracyAdjustedOffRoute > warningThreshold
        let isCritical = accuracyAdjustedOffRoute > criticalThreshold

        if persist {
            if isOffRoute {
                offRouteUpdateCount += 1
            } else {
                offRouteUpdateCount = 0
            }
        }

        let nextCue = cues.first { $0.distanceFromStartMeters > progress + 5 }
        let distanceToCue = nextCue.map { max(0, $0.distanceFromStartMeters - progress) }

        return RouteNavigationUpdate(
            progressDistanceMeters: progress,
            distanceRemainingMeters: remaining,
            offRouteDistanceMeters: accuracyAdjustedOffRoute,
            isOffRoute: isOffRoute,
            isCriticallyOffRoute: isCritical,
            nextCue: nextCue,
            distanceToNextCueMeters: distanceToCue,
            segmentIndex: nearest.segmentIndex,
            projectedCoordinate: nearest.projectedCoordinate
        )
    }

    public func makeSnapshot(
        routeId: UUID,
        coordinate: GeoCoordinate?,
        speed: Double?,
        update: RouteNavigationUpdate
    ) -> NavigationSnapshot {
        NavigationSnapshot(
            routeId: routeId,
            progressDistanceMeters: update.progressDistanceMeters,
            distanceRemainingMeters: update.distanceRemainingMeters,
            offRouteDistanceMeters: update.offRouteDistanceMeters,
            isOffRoute: update.isOffRoute,
            isCriticallyOffRoute: update.isCriticallyOffRoute,
            nextCue: update.nextCue,
            distanceToNextCueMeters: update.distanceToNextCueMeters,
            currentSpeedMetersPerSecond: speed,
            currentCoordinate: coordinate,
            completedTrack: completedTrack,
            actualTrack: actualTrack,
            updatedAt: Date()
        )
    }
}
