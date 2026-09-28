import Foundation
import RouteTraceShared
import UserNotifications
import WatchKit

/// Turns navigation events into haptics and, when the app isn't on screen, notifications.
///
/// Haptics are the primary channel: a workout app can play them with the wrist down, and the
/// left/right turn patterns are recognizable without looking. Notifications add the text for
/// when the wrist comes up, but only while the app is in the background; while frontmost (also
/// in Always On) banners would be suppressed anyway and the haptic already fired.
@MainActor
enum RouteNotificationService {
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

    /// Keeps a zone haptic from running into a turn haptic, which would blur both patterns.
    private static let zoneAlertQuietSeconds: TimeInterval = 8
    private static var lastNavigationHapticAt: Date?

    static func deliver(_ alert: NavigationAlert) {
        guard WatchPreferences.shared.navigationNotificationsEnabled else { return }

        WKInterfaceDevice.current().play(haptic(for: alert))
        lastNavigationHapticAt = Date()

        guard WKApplication.shared().applicationState == .background else { return }
        let (identifier, title, body) = notificationContent(for: alert)
        Task {
            await post(identifier: identifier, title: title, body: body, interruptionLevel: .timeSensitive)
        }
    }

    static func isQuietForZoneAlert(at date: Date) -> Bool {
        guard let lastNavigationHapticAt else { return true }
        return date.timeIntervalSince(lastNavigationHapticAt) >= zoneAlertQuietSeconds
    }

    /// Haptic only: rising or falling tones say which way the heart rate moved, and the
    /// Metrics page shows the zone.
    static func deliverZoneChange(_ change: ZoneChangeAlertPolicy.Change) {
        guard WatchPreferences.shared.zoneAlertsEnabled else { return }
        switch change {
        case .up: WKInterfaceDevice.current().play(.directionUp)
        case .down: WKInterfaceDevice.current().play(.directionDown)
        }
    }

    static func notifyActivityComplete(activityTitle: String, distanceMeters: Double, elapsedSeconds: TimeInterval) async {
        guard WKApplication.shared().applicationState == .background else { return }
        await post(
            identifier: "routetrace.activity.complete.\(UUID().uuidString)",
            title: "Activity Saved",
            body: "\(activityTitle): \(RouteFormatting.distance(distanceMeters)) in \(RouteFormatting.duration(elapsedSeconds))",
            interruptionLevel: .passive
        )
    }

    static func haptic(for alert: NavigationAlert) -> WKHapticType {
        switch alert {
        case .approachingTurn(let cue, _):
            switch cue.kind {
            case .slightLeft, .turnLeft, .sharpLeft: .navigationLeftTurn
            case .slightRight, .turnRight, .sharpRight: .navigationRightTurn
            default: .navigationGenericManeuver
            }
        case .offRoute:
            .retry
        case .farOffRoute:
            .failure
        case .backOnRoute:
            .success
        case .arrived:
            .success
        }
    }

    private static func notificationContent(for alert: NavigationAlert) -> (String, String, String) {
        switch alert {
        case .approachingTurn(let cue, let distance):
            ("routetrace.cue.\(cue.id.uuidString)", cue.instruction, "In \(RouteFormatting.distance(distance))")
        case .offRoute(let distance):
            ("routetrace.offroute", "Off Route", "The route is \(RouteFormatting.distance(distance)) away.")
        case .farOffRoute(let distance):
            ("routetrace.offroute", "Far Off Route", "The route is \(RouteFormatting.distance(distance)) away.")
        case .backOnRoute:
            ("routetrace.offroute", "Back on Route", "Keep following the blue line.")
        case .arrived:
            ("routetrace.arrived", "You Made It", "End of the route. Finish the activity to save it.")
        }
    }

    private static func post(
        identifier: String,
        title: String,
        body: String,
        interruptionLevel: UNNotificationInterruptionLevel
    ) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = interruptionLevel
        content.threadIdentifier = "routetrace.navigation"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
