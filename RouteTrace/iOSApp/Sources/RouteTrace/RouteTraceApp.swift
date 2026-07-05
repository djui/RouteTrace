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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var incomingGPX: IncomingGPXCoordinator

    @State private var routeStore: RouteStore?
    #if canImport(WatchConnectivity)
    @State private var connectivityManager: PhoneConnectivityManager?
    @State private var watchAutoTransfer: RouteWatchAutoTransfer?
    #endif
    @State private var didActivateConnectivity = false

    private var shouldShowImportSheet: Bool {
        incomingGPX.pendingImport != nil && routeStore != nil
    }

    var body: some View {
        Group {
            #if canImport(WatchConnectivity)
            if let routeStore, let connectivityManager {
                mainTabs(routeStore: routeStore, connectivityManager: connectivityManager)
            } else {
                loadingView
            }
            #else
            if let routeStore {
                mainTabs(routeStore: routeStore)
            } else {
                loadingView
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sheet(isPresented: Binding(
            get: { shouldShowImportSheet },
            set: { isPresented in
                if !isPresented { incomingGPX.clearPending() }
            }
        )) {
            if let routeStore, let pendingURL = incomingGPX.pendingImport?.url {
                ImportRouteView(
                    routeStore: routeStore,
                    incomingGPX: incomingGPX,
                    initialFileURL: pendingURL
                )
            }
        }
        .task {
            if routeStore == nil {
                routeStore = RouteStore(context: modelContext)
                _ = try? routeStore?.loadSettings()
                try? await routeStore?.restoreCloudBackedFilesIfNeeded()
            }

            guard !didActivateConnectivity else { return }
            didActivateConnectivity = true

            #if canImport(WatchConnectivity)
            if connectivityManager == nil, let routeStore {
                let manager = PhoneConnectivityManager(
                    context: modelContext,
                    routeStore: routeStore
                )
                connectivityManager = manager
                let autoTransfer = RouteWatchAutoTransfer(
                    routeStore: routeStore,
                    connectivityManager: manager
                )
                autoTransfer.registerWithRouteStore()
                watchAutoTransfer = autoTransfer
                manager.onSessionActivated = { [weak autoTransfer] in
                    autoTransfer?.transferPendingRoutes()
                }
                manager.activate()
            }
            #endif

            #if canImport(WatchConnectivity)
            watchAutoTransfer?.transferPendingRoutes()
            #endif
        }
    }

    private var loadingView: some View {
        ProgressView("Loading RouteTrace…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if canImport(WatchConnectivity)
    @ViewBuilder
    private func mainTabs(
        routeStore: RouteStore,
        connectivityManager: PhoneConnectivityManager
    ) -> some View {
        TabView {
            Tab("Routes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                RouteLibraryView()
            }

            Tab("Activities", systemImage: "figure.run") {
                ActivityListView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environmentObject(routeStore)
        .environmentObject(connectivityManager)
    }
    #else
    @ViewBuilder
    private func mainTabs(routeStore: RouteStore) -> some View {
        TabView {
            Tab("Routes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                RouteLibraryView()
            }

            Tab("Activities", systemImage: "figure.run") {
                ActivityListView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environmentObject(routeStore)
    }
    #endif
}
