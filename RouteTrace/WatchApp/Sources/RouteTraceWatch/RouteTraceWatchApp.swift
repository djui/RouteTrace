import RouteTraceShared
import SwiftUI
import WatchConnectivity

@main
struct RouteTraceWatchApp: App {
    @State private var routeStore = WatchRouteStore.shared
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var preferences = WatchPreferences.shared

    init() {
        WatchConnectivityManager.shared.activate()
        Task { @MainActor in
            await WatchRouteStore.shared.reload()
        }
    }

    var body: some Scene {
        WindowGroup {
            RouteListView()
                .environment(routeStore)
                .environment(connectivity)
                .environment(preferences)
        }
    }
}
