import AppIntents
import Foundation
import RouteTraceShared

enum RouteTraceIntentNotifications {
    static let startLastRoute = Notification.Name("RouteTrace.startLastRoute")
    static let toggleMapDirections = Notification.Name("RouteTrace.toggleMapDirections")
    static let pauseResumeActivity = Notification.Name("RouteTrace.pauseResumeActivity")
}

struct StartLastRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Last Route"
    static let description = IntentDescription("Start navigating your most recently used route.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: RouteTraceIntentNotifications.startLastRoute, object: nil)
        return .result()
    }
}

struct ToggleMapDirectionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Map / Directions"
    static let description = IntentDescription("Switch between map and directions display mode.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let preferences = WatchPreferences.shared
            switch preferences.mapDisplayMode {
            case .onlineNative, .offlineCorridor:
                preferences.mapDisplayMode = .routeOnly
            case .routeOnly:
                preferences.mapDisplayMode = .onlineNative
            }
        }
        NotificationCenter.default.post(name: RouteTraceIntentNotifications.toggleMapDirections, object: nil)
        return .result()
    }
}

struct PauseResumeActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Activity"
    static let description = IntentDescription("Pause or resume the current route activity.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: RouteTraceIntentNotifications.pauseResumeActivity, object: nil)
        return .result()
    }
}

struct RouteTraceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartLastRouteIntent(),
            phrases: [
                "Start last route in \(.applicationName)",
                "Navigate last route with \(.applicationName)"
            ],
            shortTitle: "Start Last Route",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: ToggleMapDirectionsIntent(),
            phrases: [
                "Toggle map in \(.applicationName)",
                "Switch directions in \(.applicationName)"
            ],
            shortTitle: "Map / Directions",
            systemImageName: "map"
        )
        AppShortcut(
            intent: PauseResumeActivityIntent(),
            phrases: [
                "Pause activity in \(.applicationName)",
                "Resume activity in \(.applicationName)"
            ],
            shortTitle: "Pause / Resume",
            systemImageName: "pause.fill"
        )
    }
}
