import Foundation
import RouteTraceShared
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

enum RouteNotificationService {
    private static let cueDistanceThresholdMeters = 50.0

    enum OffRouteLevel: Equatable {
        case none
        case warning
        case critical
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    static func notifyOffRouteWarning(distanceMeters: Double) async {
        await deliver(
            identifier: "routetrace.offroute.warning",
            title: "Off Route",
            body: "You are \(RouteFormatting.distance(distanceMeters)) from the planned route.",
            interruptionLevel: .timeSensitive,
            sound: .default
        )
    }

    static func notifyCriticalOffRoute(distanceMeters: Double) async {
        await deliver(
            identifier: "routetrace.offroute.critical",
            title: "Far Off Route",
            body: "You are \(RouteFormatting.distance(distanceMeters)) off route.",
            interruptionLevel: .timeSensitive,
            sound: .default
        )
    }

    static func notifyUpcomingCue(_ cue: RouteCue, distanceMeters: Double) async {
        await deliver(
            identifier: "routetrace.cue.\(cue.id.uuidString)",
            title: "Upcoming Turn",
            body: "\(cue.instruction) in \(RouteFormatting.distance(distanceMeters))",
            interruptionLevel: .active,
            sound: .default
        )
    }

    static func notifyActivityComplete(activityTitle: String, distanceMeters: Double, elapsedSeconds: TimeInterval) async {
        await deliver(
            identifier: "routetrace.activity.complete.\(UUID().uuidString)",
            title: "Activity Complete",
            body: "\(activityTitle): \(RouteFormatting.distance(distanceMeters)) in \(RouteFormatting.duration(elapsedSeconds))",
            interruptionLevel: .passive,
            sound: nil
        )
    }

    static func cueNotificationThresholdMet(distanceMeters: Double?) -> Bool {
        guard let distanceMeters else { return false }
        return distanceMeters <= cueDistanceThresholdMeters
    }

    private static func deliver(
        identifier: String,
        title: String,
        body: String,
        interruptionLevel: UNNotificationInterruptionLevel,
        sound: UNNotificationSound?
    ) async {
        let enabled = await MainActor.run { WatchPreferences.shared.navigationNotificationsEnabled }
        guard enabled else { return }

        let appActive = await MainActor.run {
            #if os(watchOS)
            WKExtension.shared().applicationState == .active
            #else
            false
            #endif
        }
        guard !appActive else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = interruptionLevel
        content.sound = sound
        content.threadIdentifier = "routetrace.navigation"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
