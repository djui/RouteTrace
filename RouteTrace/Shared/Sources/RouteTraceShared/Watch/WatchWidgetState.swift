import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum WatchAppConstants {
    public static let appGroupIdentifier = "group.com.uwe.RouteTrace"
    public static let snapshotUserDefaultsKey = "activeNavigationSnapshot"
    public static let activityStateUserDefaultsKey = "activeActivityState"
    public static let widgetKind = "ActiveRouteWidget"
}

public enum ActiveActivityState: String, Codable, Sendable {
    case idle
    case running
    case paused
}

public struct WatchActivityWidgetPayload: Codable, Sendable {
    public let routeName: String
    public let progressFraction: Double
    public let distanceRemainingMeters: Double
    public let elapsedSeconds: TimeInterval
    public let isPaused: Bool
    public let isOffRoute: Bool
    public let updatedAt: Date

    public init(
        routeName: String,
        progressFraction: Double,
        distanceRemainingMeters: Double,
        elapsedSeconds: TimeInterval,
        isPaused: Bool,
        isOffRoute: Bool,
        updatedAt: Date
    ) {
        self.routeName = routeName
        self.progressFraction = progressFraction
        self.distanceRemainingMeters = distanceRemainingMeters
        self.elapsedSeconds = elapsedSeconds
        self.isPaused = isPaused
        self.isOffRoute = isOffRoute
        self.updatedAt = updatedAt
    }
}

public enum WatchWidgetStateWriter {
    public static func writeSnapshot(
        _ snapshot: NavigationSnapshot,
        routeName: String,
        elapsedSeconds: TimeInterval,
        isPaused: Bool
    ) {
        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        if let data = try? RouteTracePayloadCoding.encode(snapshot) {
            suite.set(data, forKey: WatchAppConstants.snapshotUserDefaultsKey)
        }

        let total = snapshot.progressDistanceMeters + snapshot.distanceRemainingMeters
        let fraction = total > 0 ? snapshot.progressDistanceMeters / total : 0
        let payload = WatchActivityWidgetPayload(
            routeName: routeName,
            progressFraction: fraction,
            distanceRemainingMeters: snapshot.distanceRemainingMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused,
            isOffRoute: snapshot.isOffRoute,
            updatedAt: snapshot.updatedAt
        )
        if let data = try? RouteTracePayloadCoding.encode(payload) {
            suite.set(data, forKey: WatchAppConstants.activityStateUserDefaultsKey)
        }
        reloadWidgetTimelines()
    }

    public static func clear() {
        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        suite.removeObject(forKey: WatchAppConstants.snapshotUserDefaultsKey)
        suite.removeObject(forKey: WatchAppConstants.activityStateUserDefaultsKey)
        reloadWidgetTimelines()
    }

    public static func readWidgetPayload() -> WatchActivityWidgetPayload? {
        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        guard let data = suite.data(forKey: WatchAppConstants.activityStateUserDefaultsKey) else { return nil }
        return try? RouteTracePayloadCoding.decode(WatchActivityWidgetPayload.self, from: data)
    }

    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchAppConstants.widgetKind)
        #endif
    }
}
