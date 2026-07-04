import SwiftUI
import SwiftData
import RouteTraceShared

struct RouteLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var routeStore: RouteStore
    @EnvironmentObject private var incomingGPX: IncomingGPXCoordinator
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @Query(sort: \RouteEntity.importedAt, order: .reverse) private var routes: [RouteEntity]

    @State private var isShowingImport = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var routePendingDelete: RouteEntity?
    @State private var exportURL: URL?
    @State private var isSharePresented = false
    @State private var isExporting = false
    @State private var buildingRouteID: UUID?
    @State private var sendingRouteID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("No Routes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    } description: {
                        Text("Import a GPX file to get started.")
                    } actions: {
                        Button("Import GPX") {
                            isShowingImport = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(routes) { route in
                        NavigationLink(value: route.id) {
                            RouteRowView(route: route)
                        }
                        .contextMenu {
                            RouteActionMenuItems(
                                route: route,
                                routePackage: (try? routeStore.loadRoutePackage(for: route)),
                                isExporting: isExporting,
                                isBuildingOfflinePack: buildingRouteID == route.id,
                                isSendingToWatch: sendingRouteID == route.id,
                                onRebuildOfflineMap: { Task { await buildOfflinePack(for: route) } },
                                onSendToWatch: sendToWatchAction(for: route),
                                onShare: { shareRoute(route) },
                                onDelete: { routePendingDelete = route }
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                routePendingDelete = route
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .confirmationDialog(
                            "Delete this route?",
                            isPresented: Binding(
                                get: { routePendingDelete?.id == route.id },
                                set: { if !$0 { routePendingDelete = nil } }
                            ),
                            titleVisibility: .visible
                        ) {
                            Button("Delete Route", role: .destructive) {
                                deleteRoute(route)
                                routePendingDelete = nil
                            }
                            Button("Cancel", role: .cancel) {
                                routePendingDelete = nil
                            }
                        } message: {
                            Text("This removes the route and any offline map pack from your iPhone.")
                        }
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingImport = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { routeID in
                if let route = routes.first(where: { $0.id == routeID }) {
                    RouteDetailView(route: route)
                }
            }
            .sheet(isPresented: $isShowingImport) {
                ImportRouteView(routeStore: routeStore, incomingGPX: incomingGPX)
            }
            .sheet(isPresented: $isSharePresented, onDismiss: { RouteActions.cleanupExport(at: exportURL) }) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .alert("Route Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Sent to Watch", isPresented: Binding(
                get: { successMessage != nil },
                set: { if !$0 { successMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage ?? "")
            }
            #if canImport(WatchConnectivity)
            .onAppear {
                connectivityManager.refreshSessionState()
            }
            .onChange(of: connectivityManager.lastTransferSuccess) { _, message in
                if let message { successMessage = message }
            }
            .onChange(of: connectivityManager.lastTransferError) { _, message in
                if let message { errorMessage = message }
            }
            #endif
        }
    }

    #if canImport(WatchConnectivity)
    private func sendToWatchAction(for route: RouteEntity) -> (() -> Void)? {
        { Task { await sendToWatch(route) } }
    }
    #else
    private func sendToWatchAction(for route: RouteEntity) -> (() -> Void)? { nil }
    #endif

    @MainActor
    private func buildOfflinePack(for route: RouteEntity) async {
        buildingRouteID = route.id
        defer { buildingRouteID = nil }
        do {
            _ = try await routeStore.buildOfflinePack(for: route)
        } catch RouteStoreError.offlinePackSavedArchiveFailed {
            errorMessage = RouteStoreError.offlinePackSavedArchiveFailed.localizedDescription
        } catch {
            errorMessage = RouteActions.offlineMapBuildErrorMessage(for: error)
        }
    }

    #if canImport(WatchConnectivity)
    @MainActor
    private func sendToWatch(_ route: RouteEntity) async {
        sendingRouteID = route.id
        defer { sendingRouteID = nil }
        do {
            try connectivityManager.transferRouteToWatch(routeID: route.id)
            successMessage = connectivityManager.lastTransferSuccess
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    private func shareRoute(_ route: RouteEntity) {
        isExporting = true
        defer { isExporting = false }

        do {
            let package = try routeStore.loadRoutePackage(for: route)
            exportURL = try RouteActions.exportGPXURL(for: package, routeID: route.id)
            isSharePresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRoute(_ route: RouteEntity) {
        do {
            try routeStore.deleteRoute(route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RouteRowView: View {
    let route: RouteEntity

    var body: some View {
        HStack(spacing: 10) {
            RouteShapeThumbnailLoader(route: route)

            VStack(alignment: .leading, spacing: 6) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    metadataLabel(
                        RouteFormatting.distance(route.distanceMeters),
                        systemImage: "ruler"
                    )
                    metadataLabel(
                        route.activityHint.displayName,
                        systemImage: route.activityHint.systemImage
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TransferStateBadge(state: route.transferState)
                    OfflineStatusBadge(status: route.offlineStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func metadataLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .fixedSize()
    }
}

struct TransferStateBadge: View {
    let state: TransferState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.systemImage)
            Text(state.displayName)
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.tint.opacity(0.15), in: Capsule())
        .foregroundStyle(state.tint)
    }
}

struct OfflineStatusBadge: View {
    let status: OfflinePackStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            Text(status.displayName)
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.15), in: Capsule())
        .foregroundStyle(status.tint)
    }
}

private extension TransferState {
    var displayName: String {
        switch self {
        case .notSent: "Not Sent"
        case .queued: "Queued"
        case .transferring: "Transferring"
        case .installed: "On Watch"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .notSent: "applewatch.slash"
        case .queued: "clock"
        case .transferring: "arrow.up.circle"
        case .installed: "applewatch"
        case .failed: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .notSent: .secondary
        case .queued, .transferring: .orange
        case .installed: .green
        case .failed: .red
        }
    }
}

private extension OfflinePackStatus {
    var displayName: String {
        switch self {
        case .missing: "No Offline Map"
        case .partial: "Partial Offline"
        case .ready: "Offline Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .missing: "map"
        case .partial: "map.fill"
        case .ready: "map.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .missing: .secondary
        case .partial: .orange
        case .ready: .blue
        }
    }
}
