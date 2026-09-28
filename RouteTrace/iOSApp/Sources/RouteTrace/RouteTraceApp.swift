import RouteTraceShared
import SwiftData
import SwiftUI

@main
struct RouteTraceApp: App {
    private let container: ModelContainer
    @StateObject private var incomingGPX = IncomingGPXCoordinator()

    init() {
        try? RouteTracePaths.ensureDirectoriesExist()
        container = RouteTraceModelContainerFactory.make()
    }

    var body: some Scene {
        WindowGroup {
            RouteTraceRootView()
                .environmentObject(incomingGPX)
                .onOpenURL { url in
                    incomingGPX.handleIncomingURL(url)
                }
        }
        .modelContainer(container)
    }
}

struct RouteTraceRootView: View {
    private enum AppTab: Hashable {
        case routes
        case activities
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var incomingGPX: IncomingGPXCoordinator

    @State private var routeStore: RouteStore?
    #if canImport(WatchConnectivity)
    @State private var connectivityManager: PhoneConnectivityManager?
    @State private var watchAutoTransfer: RouteWatchAutoTransfer?
    #endif
    @State private var selectedTab: AppTab = .routes

    var body: some View {
        Group {
            #if canImport(WatchConnectivity)
            if let routeStore, let connectivityManager {
                tabView
                    .environmentObject(routeStore)
                    .environmentObject(connectivityManager)
            } else {
                loadingView
            }
            #else
            if let routeStore {
                tabView
                    .environmentObject(routeStore)
            } else {
                loadingView
            }
            #endif
        }
        .onChange(of: incomingGPX.pendingImport?.id) { _, id in
            if id != nil {
                selectedTab = .routes
            }
        }
        .task {
            await start()
        }
    }

    private func start() async {
        guard routeStore == nil else { return }
        let store = RouteStore(context: modelContext)
        _ = try? store.loadSettings()
        routeStore = store

        #if DEBUG
        DemoData.seedIfRequested(into: store)
        #endif

        #if canImport(WatchConnectivity)
        let manager = PhoneConnectivityManager(context: modelContext, routeStore: store)
        let autoTransfer = RouteWatchAutoTransfer(routeStore: store, connectivityManager: manager)
        autoTransfer.registerWithRouteStore()
        manager.onSessionActivated = { [weak autoTransfer, weak manager] in
            autoTransfer?.transferPendingRoutes()
            // Catches a watch that installed the app after the last reorder.
            if let order = RouteOrderStore.shared.order {
                manager?.sendRouteOrder(order)
            }
        }
        connectivityManager = manager
        watchAutoTransfer = autoTransfer
        manager.activate()
        #endif

        try? await store.restoreCloudBackedFilesIfNeeded()
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Routes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", value: AppTab.routes) {
                RouteLibraryView()
            }

            Tab("Activities", systemImage: "figure.run", value: AppTab.activities) {
                ActivityListView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
