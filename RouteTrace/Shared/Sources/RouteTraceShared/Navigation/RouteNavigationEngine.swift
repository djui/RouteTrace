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

    private static let defaultSearchWindow = 100
    private static let widenedSearchWindow = 500
    private static let offRouteUpdatesBeforeWidening = 3

    public init(routePackage: RoutePackage) {
        self.route = routePackage.route
        self.cues = routePackage.cues
        self.activityKind = routePackage.activityHint
        self.totalDistanceMeters = routePackage.distanceMeters
    }

    public var breadcrumb: [GeoCoordinate] {
        completedTrack
    }

    public var gpsTrack: [GeoCoordinate] {
        actualTrack
    }

    public func exportState() -> PersistedNavigationEngineState {
        PersistedNavigationEngineState(
            lastSegmentIndex: lastSegmentIndex,
            lastProgressMeters: lastProgressMeters,
            completedTrack: completedTrack,
            actualTrack: actualTrack
        )
    }

    public func restoreState(_ state: PersistedNavigationEngineState) {
        lastSegmentIndex = state.lastSegmentIndex
        lastProgressMeters = state.lastProgressMeters
        completedTrack = state.completedTrack
        actualTrack = state.actualTrack
    }

    public func reset() {
        lastSegmentIndex = 0
        lastProgressMeters = 0
        completedTrack = []
        actualTrack = []
        offRouteUpdateCount = 0
    }

    public func update(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double?
    ) -> RouteNavigationUpdate? {
        guard MapMath.isValidCoordinate(latitude: latitude, longitude: longitude) else { return nil }

        let location = GeoCoordinate(latitude: latitude, longitude: longitude)
        actualTrack.append(location)

        let searchWindow = offRouteUpdateCount >= Self.offRouteUpdatesBeforeWidening
            ? Self.widenedSearchWindow
            : Self.defaultSearchWindow

        guard let nearest = MapMath.nearestPointOnPolyline(
            to: location,
            route: route,
            searchStartIndex: max(0, lastSegmentIndex - 2),
            searchWindow: searchWindow
        ) else { return nil }

        let accuracyAdjustedOffRoute = max(0, nearest.distanceMeters - max(0, horizontalAccuracyMeters - 10))
        let progress = max(lastProgressMeters, nearest.distanceAlongRouteMeters)

        if nearest.segmentIndex >= lastSegmentIndex {
            lastSegmentIndex = nearest.segmentIndex
            lastProgressMeters = progress
            completedTrack.append(nearest.projectedCoordinate)
        }

        let remaining = max(0, totalDistanceMeters - progress)
        let warningThreshold = activityKind.offRouteWarningMeters
        let criticalThreshold = activityKind.offRouteCriticalMeters

        let isOffRoute = accuracyAdjustedOffRoute > warningThreshold
        let isCritical = accuracyAdjustedOffRoute > criticalThreshold

        if isOffRoute {
            offRouteUpdateCount += 1
        } else {
            offRouteUpdateCount = 0
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
