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
    /// When running, the moment the elapsed time was zero; lets widgets show a live timer
    /// (`Text(timerInterval:)`) without timeline reloads.
    public let timerStartDate: Date?

    public init(
        routeName: String,
        progressFraction: Double,
        distanceRemainingMeters: Double,
        elapsedSeconds: TimeInterval,
        isPaused: Bool,
        isOffRoute: Bool,
        updatedAt: Date,
        timerStartDate: Date? = nil
    ) {
        self.routeName = routeName
        self.progressFraction = progressFraction
        self.distanceRemainingMeters = distanceRemainingMeters
        self.elapsedSeconds = elapsedSeconds
        self.isPaused = isPaused
        self.isOffRoute = isOffRoute
        self.updatedAt = updatedAt
        self.timerStartDate = timerStartDate
    }
}

public enum WatchWidgetStateWriter {
    nonisolated(unsafe) private static var lastTimelineReloadAt: Date = .distantPast
    nonisolated(unsafe) private static var lastWrittenPayload: WatchActivityWidgetPayload?

    /// Publishes the compact state widgets read. Called often (every fix and timer tick), so it
    /// skips writes that wouldn't change what a widget shows.
    public static func write(
        _ payload: WatchActivityWidgetPayload,
        minReloadInterval: TimeInterval = 15,
        forceTimelineReload: Bool = false
    ) {
        if !forceTimelineReload, let last = lastWrittenPayload, last.isVisuallyEquivalent(to: payload) {
            return
        }
        lastWrittenPayload = payload

        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        if let data = try? RouteTracePayloadCoding.encode(payload) {
            suite.set(data, forKey: WatchAppConstants.activityStateUserDefaultsKey)
        }
        reloadWidgetTimelinesIfNeeded(minInterval: minReloadInterval, force: forceTimelineReload)
    }

    public static func clear() {
        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        // Also drops the full navigation snapshot older versions wrote here.
        suite.removeObject(forKey: WatchAppConstants.snapshotUserDefaultsKey)
        suite.removeObject(forKey: WatchAppConstants.activityStateUserDefaultsKey)
        lastWrittenPayload = nil
        reloadWidgetTimelinesIfNeeded(minInterval: 0, force: true)
    }

    public static func readWidgetPayload() -> WatchActivityWidgetPayload? {
        let suite = UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
        guard let data = suite.data(forKey: WatchAppConstants.activityStateUserDefaultsKey) else { return nil }
        return try? RouteTracePayloadCoding.decode(WatchActivityWidgetPayload.self, from: data)
    }

    private static func reloadWidgetTimelinesIfNeeded(minInterval: TimeInterval, force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastTimelineReloadAt) >= minInterval else { return }
        lastTimelineReloadAt = now
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchAppConstants.widgetKind)
        #endif
    }
}

private extension WatchActivityWidgetPayload {
    /// Widgets show whole percent and the remaining distance at 10 m resolution; the running
    /// timer renders itself from `timerStartDate`.
    func isVisuallyEquivalent(to other: WatchActivityWidgetPayload) -> Bool {
        routeName == other.routeName
            && Int(progressFraction * 100) == Int(other.progressFraction * 100)
            && Int(distanceRemainingMeters / 10) == Int(other.distanceRemainingMeters / 10)
            && isPaused == other.isPaused
            && isOffRoute == other.isOffRoute
            && abs((timerStartDate ?? .distantPast).timeIntervalSince(other.timerStartDate ?? .distantPast)) < 1
            && (timerStartDate != nil || Int(elapsedSeconds) == Int(other.elapsedSeconds))
    }
}
