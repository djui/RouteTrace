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

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("No Routes", systemImage: "map")
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
            .alert("Route Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct RouteRowView: View {
    let route: RouteEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(route.name)
                .font(.headline)

            HStack(spacing: 12) {
                Label(RouteFormatting.distance(route.distanceMeters), systemImage: "ruler")
                Label(route.activityHint.displayName, systemImage: route.activityHint.systemImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TransferStateBadge(state: route.transferState)
                OfflineStatusBadge(status: route.offlineStatus)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransferStateBadge: View {
    let state: TransferState

    var body: some View {
        Label(state.displayName, systemImage: state.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(state.tint)
    }
}

struct OfflineStatusBadge: View {
    let status: OfflinePackStatus

    var body: some View {
        Label(status.displayName, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
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
