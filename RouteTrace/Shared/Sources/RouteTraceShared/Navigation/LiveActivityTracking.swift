import Foundation

/// Elapsed activity time from wall-clock timestamps.
///
/// Counting timer ticks undercounts whenever watchOS throttles or suspends the app (wrist down,
/// Always On, no workout session) and loses the time the app was not running after a relaunch.
public struct ActivityClock: Codable, Sendable, Equatable {
    public private(set) var accumulatedSeconds: TimeInterval
    public private(set) var runningSince: Date?

    public init(accumulatedSeconds: TimeInterval = 0, runningSince: Date? = nil) {
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.runningSince = runningSince
    }

    public var isRunning: Bool { runningSince != nil }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func start(at date: Date = Date()) {
        guard runningSince == nil else { return }
        runningSince = date
    }

    public mutating func pause(at date: Date = Date()) {
        guard let runningSince else { return }
        accumulatedSeconds += max(0, date.timeIntervalSince(runningSince))
        self.runningSince = nil
    }
}

/// Current speed, smoothed so pace doesn't jump with every GPS fix, and cleared when fixes stop
/// arriving (with a distance filter, a runner who stops produces no more updates).
public struct SpeedEstimator: Sendable {
    public let timeConstantSeconds: TimeInterval
    public let staleAfterSeconds: TimeInterval
    private var smoothed: Double?
    private var lastUpdate: Date?

    public init(timeConstantSeconds: TimeInterval = 8, staleAfterSeconds: TimeInterval = 15) {
        self.timeConstantSeconds = timeConstantSeconds
        self.staleAfterSeconds = staleAfterSeconds
    }

    public mutating func reset() {
        smoothed = nil
        lastUpdate = nil
    }

    public mutating func add(speedMetersPerSecond speed: Double, at date: Date) {
        guard speed.isFinite, speed >= 0 else { return }
        defer { lastUpdate = date }
        guard let previous = smoothed, let lastUpdate else {
            smoothed = speed
            return
        }
        let dt = max(0, date.timeIntervalSince(lastUpdate))
        // Long gaps (e.g. after a pause) restart the average rather than blending stale data.
        guard dt < staleAfterSeconds else {
            smoothed = speed
            return
        }
        let weight = 1 - exp(-dt / timeConstantSeconds)
        smoothed = previous + weight * (speed - previous)
    }

    public func current(at date: Date = Date()) -> Double? {
        guard let smoothed, let lastUpdate, date.timeIntervalSince(lastUpdate) <= staleAfterSeconds else {
            return nil
        }
        return smoothed
    }
}

/// Distance and climbing as recorded, updated per accepted fix.
///
/// Uses the same gap rules as `ActivityTrackStatistics`, so the watch shows the same distance the
/// iPhone later computes from the saved track, and it can be rebuilt from track points on restore.
public struct LiveTrackStatistics: Sendable {
    public private(set) var distanceMeters: Double = 0
    public private(set) var elevation = ElevationAccumulator(thresholdMeters: ElevationStatistics.recordedThresholdMeters)
    private var previous: TrackPoint?

    public init() {}

    public init(rebuildingFrom trackPoints: [TrackPoint]) {
        for point in trackPoints {
            add(point)
        }
    }

    public var elevationGainMeters: Double? {
        elevation.hasSamples ? elevation.totalGainMeters : nil
    }

    public mutating func add(_ point: TrackPoint) {
        if let previous {
            let gap = point.timestamp.timeIntervalSince(previous.timestamp)
            let step = MapMath.haversineMeters(from: previous.coordinate, to: point.coordinate)
            if gap <= TrackSegmentSplitter.defaultTimeGapSeconds,
               step <= TrackSegmentSplitter.defaultSpatialJumpMeters {
                distanceMeters += step
            }
        }
        if let altitude = point.altitudeMeters {
            elevation.add(altitude)
        }
        previous = point
    }
}

/// Something the runner should feel or hear while navigating.
public enum NavigationAlert: Equatable, Sendable {
    case approachingTurn(RouteCue, distanceMeters: Double)
    case offRoute(distanceMeters: Double)
    case farOffRoute(distanceMeters: Double)
    case backOnRoute
    case arrived
}

/// Decides when to alert, so each turn, departure and arrival is announced exactly once.
public struct NavigationAlertTracker: Sendable {
    private enum OffRouteLevel: Int, Sendable {
        case none
        case warning
        case critical
    }

    public static let arrivalDistanceMeters = 30.0

    private var offRouteLevel: OffRouteLevel = .none
    private var alertedCueIDs: Set<UUID> = []
    private var hasArrived = false

    public init() {}

    public mutating func reset() {
        offRouteLevel = .none
        alertedCueIDs = []
        hasArrived = false
    }

    /// Announce a turn roughly 8 seconds ahead at the current speed, within sensible bounds.
    public static func turnAlertDistance(activity: ActivityKind, speedMetersPerSecond: Double?) -> Double {
        let minimum: Double = activity.speedCategory == .cycling ? 70 : 40
        let lookahead = (speedMetersPerSecond ?? 0) * 8
        return min(150, max(minimum, lookahead))
    }

    public mutating func alerts(
        for snapshot: NavigationSnapshot,
        activity: ActivityKind,
        speedMetersPerSecond: Double?
    ) -> [NavigationAlert] {
        var alerts: [NavigationAlert] = []

        let level: OffRouteLevel = snapshot.isCriticallyOffRoute ? .critical : (snapshot.isOffRoute ? .warning : .none)
        if level.rawValue > offRouteLevel.rawValue {
            alerts.append(level == .critical
                ? .farOffRoute(distanceMeters: snapshot.offRouteDistanceMeters)
                : .offRoute(distanceMeters: snapshot.offRouteDistanceMeters))
        } else if level == .none, offRouteLevel != .none {
            alerts.append(.backOnRoute)
        }
        offRouteLevel = level

        // Turn prompts only make sense while following the route.
        if level == .none,
           let cue = snapshot.nextCue,
           cue.kind != .finish,
           cue.kind != .start,
           let distance = snapshot.distanceToNextCueMeters,
           distance <= Self.turnAlertDistance(activity: activity, speedMetersPerSecond: speedMetersPerSecond),
           !alertedCueIDs.contains(cue.id) {
            alertedCueIDs.insert(cue.id)
            alerts.append(.approachingTurn(cue, distanceMeters: distance))
        }

        let routeLength = snapshot.progressDistanceMeters + snapshot.distanceRemainingMeters
        if !hasArrived,
           routeLength > 0,
           snapshot.progressDistanceMeters > routeLength * 0.5,
           snapshot.distanceRemainingMeters <= Self.arrivalDistanceMeters {
            hasArrived = true
            alerts.append(.arrived)
        }

        return alerts
    }
}
