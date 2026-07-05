import RouteTraceShared
import SwiftData
import SwiftUI
import WatchConnectivity

@main
struct RouteTraceWatchApp: App {
    private let modelContainer = RouteTraceModelContainerFactory.make()

    @State private var routeStore = WatchRouteStore.shared
    @State private var activityStore = WatchActivityStore.shared
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var cloudSync = WatchCloudRouteSyncService.shared
    @State private var preferences = WatchPreferences.shared

    init() {
        try? RouteTracePaths.ensureDirectoriesExist()
        WatchConnectivityManager.shared.activate()
        Task { @MainActor in
            await WatchRouteStore.shared.reload()
            await WatchActivityStore.shared.reload()
        }
    }

    var body: some Scene {
        WindowGroup {
            RouteListView()
                .environment(routeStore)
                .environment(activityStore)
                .environment(connectivity)
                .environment(cloudSync)
                .environment(preferences)
                .background {
                    CloudRouteSyncView()
                }
        }
        .modelContainer(modelContainer)
    }
}
