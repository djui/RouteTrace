import RouteTraceShared
import SwiftData
import SwiftUI

/// One model container per process, shared by the app and its intents.
@MainActor
enum AppModelContainer {
    static let shared = RouteTraceModelContainerFactory.make()
}

@main
struct RouteTraceApp: App {
    private let container: ModelContainer
    @StateObject private var incomingGPX = IncomingGPXCoordinator()

    init() {
        try? RouteTracePaths.ensureDirectoriesExist()
        container = AppModelContainer.shared
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
        #if canImport(WatchConnectivity)
        // Shared with intents, which may have set them up already in the background.
        let services = AppServices.shared
        services.start()
        let store = services.routeStore
        connectivityManager = services.connectivity
        #else
        let store = RouteStore(context: modelContext)
        _ = try? store.loadSettings()
        #endif
        routeStore = store

        #if DEBUG
        DemoData.seedIfRequested(into: store)
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
