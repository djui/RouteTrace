import SwiftUI
import SwiftData
import RouteTraceShared

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @Bindable var route: RouteEntity

    @State private var routePackage: RoutePackage?
    @State private var isLoading = true
    @State private var isBuildingOfflinePack = false
    @State private var offlineBuildProgress: OfflinePackBuildProgress?
    @State private var isDeletingOfflinePack = false
    @State private var isSendingToWatch = false
    @State private var isUpdatingActivityKind = false
    @State private var isReversingDirection = false
    @State private var isExporting = false
    @State private var showDeleteConfirmation = false
    @State private var showSourceGPXUnavailable = false
    @State private var exportURL: URL?
    @State private var isSharePresented = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var infoMessage: String?
    @State private var isMapFullscreenPresented = false
    @State private var showRenameAlert = false
    @State private var editedRouteName = ""
    @State private var isRenaming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let routePackage {
                    Button {
                        isMapFullscreenPresented = true
                    } label: {
                        RouteMapPreview(routePoints: routePackage.route)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    if let navigationWarning = routePackage.navigationWarning {
                        Label(navigationWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 260)
                }

                #if canImport(WatchConnectivity)
                watchStatusSection
                #endif

                statsSection
                altitudeSection
                offlineMapSection
            }
            .padding()
            .padding(.bottom, 20)
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                routeActionsMenu
            }
        }
        .sheet(isPresented: $isSharePresented, onDismiss: cleanupExport) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .fullScreenCover(isPresented: $isMapFullscreenPresented) {
            if let routePackage {
                ActivityMapFullscreenView(
                    routeName: route.name,
                    distanceLabel: RouteFormatting.distance(route.distanceMeters),
                    routePoints: routePackage.route,
                    trackPoints: []
                )
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
        .alert("Activity Type Unavailable", isPresented: $showSourceGPXUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original GPX file is not available for this route. Re-import the route to change its activity type.")
        }
        .alert("Offline Map Cleared", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
        .alert("Rename Route", isPresented: $showRenameAlert) {
            TextField("Route Name", text: $editedRouteName)
                .textInputAutocapitalization(.words)
            Button("Save") {
                Task { await renameRoute() }
            }
            .disabled(editedRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a name for this route.")
        }
        .task {
            await loadRoute()
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

    #if canImport(WatchConnectivity)
    private var watchStatusSection: some View {
        WatchStatusRow(
            transferState: route.transferState,
            isSending: isSendingToWatch,
            onSendToWatch: sendToWatchAction
        )
    }
    #endif

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Distance", value: RouteFormatting.distance(route.distanceMeters), symbol: "ruler")
                StatTile(title: "Gain", value: RouteFormatting.elevation(route.elevationGainMeters), symbol: "arrow.up.right")
                StatTile(title: "Loss", value: RouteFormatting.elevation(route.elevationLossMeters), symbol: "arrow.down.right")
                StatTile(
                    title: "Points",
                    value: pointsValue,
                    symbol: "point.3.connected.trianglepath.dotted"
                )

                if let routePackage, routePackage.hasElevationData,
                   let range = elevationRange(from: routePackage.route) {
                    StatTile(
                        title: "Min Elevation",
                        value: RouteFormatting.elevation(range.min),
                        symbol: "arrow.down.to.line"
                    )
                    StatTile(
                        title: "Max Elevation",
                        value: RouteFormatting.elevation(range.max),
                        symbol: "arrow.up.to.line"
                    )
                }

                if let routePackage {
                    StatTile(
                        title: "Turn Cues",
                        value: "\(routePackage.cues.count)",
                        symbol: "signpost.right"
                    )
                }
            }
        }
    }

    private var pointsValue: String {
        if route.originalPointCount > route.simplifiedPointCount {
            return "\(route.simplifiedPointCount) of \(route.originalPointCount)"
        }
        return "\(route.simplifiedPointCount)"
    }

    private func elevationRange(from route: [RoutePoint]) -> (min: Double, max: Double)? {
        let values = route.compactMap(\.elevationMeters)
        guard let min = values.min(), let max = values.max() else { return nil }
        return (min, max)
    }

    @ViewBuilder
    private var altitudeSection: some View {
        if let routePackage, routePackage.hasElevationData {
            VStack(alignment: .leading, spacing: 12) {
                Text("Elevation Profile")
                    .font(.headline)
                AltitudeChartView(routePoints: routePackage.route)
            }
        }
    }

    private var offlineMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline map")
                .font(.headline)

            OfflineMapControls(
                status: route.offlineStatus,
                tileCount: route.offlineTileCount,
                packSizeBytes: route.offlinePackSizeBytes,
                isBuilding: isBuildingOfflinePack,
                buildProgress: offlineBuildProgress,
                isDeleting: isDeletingOfflinePack,
                onBuild: { Task { await buildOfflinePack() } },
                onDelete: route.offlineStatus == .missing ? nil : { Task { await deleteOfflinePack() } }
            )
        }
    }

    private var routeActionsMenu: some View {
        Menu {
            RouteActionMenuItems(
                route: route,
                routePackage: routePackage,
                isExporting: isExporting,
                isSendingToWatch: isSendingToWatch,
                isUpdatingActivityKind: isUpdatingActivityKind,
                isReversingDirection: isReversingDirection,
                onActivityKindChange: { kind in
                    Task { await updateActivityKind(to: kind) }
                },
                onReverseDirection: {
                    Task { await reverseRouteDirection() }
                },
                onSendToWatch: sendToWatchAction,
                onRename: {
                    editedRouteName = route.name
                    showRenameAlert = true
                },
                onShare: shareRoute,
                onDelete: { showDeleteConfirmation = true }
            )
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .disabled(isExporting)
        .confirmationDialog(
            "Delete this route?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Route", role: .destructive) {
                deleteRoute()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the route and any offline map pack from your iPhone.")
        }
    }

    #if canImport(WatchConnectivity)
    private var sendToWatchAction: (() -> Void)? {
        { Task { await sendToWatch() } }
    }
    #else
    private var sendToWatchAction: (() -> Void)? { nil }
    #endif

    @MainActor
    private func renameRoute() async {
        isRenaming = true
        defer { isRenaming = false }

        do {
            _ = try routeStore.renameRoute(for: route, to: editedRouteName)
            routePackage = try routeStore.loadRoutePackage(for: route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadRoute() async {
        isLoading = true
        defer { isLoading = false }
        do {
            routePackage = try routeStore.loadRoutePackage(for: route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if canImport(WatchConnectivity)
    @MainActor
    private func sendToWatch() async {
        isSendingToWatch = true
        defer { isSendingToWatch = false }
        do {
            try connectivityManager.transferRouteToWatch(routeID: route.id)
            successMessage = connectivityManager.lastTransferSuccess
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    @MainActor
    private func buildOfflinePack() async {
        isBuildingOfflinePack = true
        offlineBuildProgress = nil
        defer {
            isBuildingOfflinePack = false
            offlineBuildProgress = nil
        }
        do {
            _ = try await routeStore.buildOfflinePack(for: route) { progress in
                offlineBuildProgress = progress
            }
            routePackage = try routeStore.loadRoutePackage(for: route)
        } catch RouteStoreError.offlinePackSavedArchiveFailed {
            routePackage = try? routeStore.loadRoutePackage(for: route)
            infoMessage = RouteStoreError.offlinePackSavedArchiveFailed.localizedDescription
        } catch {
            errorMessage = RouteActions.offlineMapBuildErrorMessage(for: error)
        }
    }


    @MainActor
    private func deleteOfflinePack() async {
        isDeletingOfflinePack = true
        defer { isDeletingOfflinePack = false }
        do {
            _ = try routeStore.deleteOfflinePack(for: route)
            routePackage = try routeStore.loadRoutePackage(for: route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reverseRouteDirection() async {
        let hadOfflinePack = route.offlineStatus != .missing
        isReversingDirection = true
        defer { isReversingDirection = false }

        do {
            _ = try await routeStore.reverseRoute(for: route)
            routePackage = try routeStore.loadRoutePackage(for: route)
            if hadOfflinePack {
                infoMessage = "Offline map cleared — rebuild when ready."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateActivityKind(to kind: ActivityKind) async {
        guard RouteTracePaths.hasSourceGPX(for: route.id) else {
            showSourceGPXUnavailable = true
            return
        }

        let hadOfflinePack = route.offlineStatus != .missing
        isUpdatingActivityKind = true
        defer { isUpdatingActivityKind = false }

        do {
            _ = try await routeStore.updateActivityHint(for: route, to: kind)
            routePackage = try routeStore.loadRoutePackage(for: route)
            if hadOfflinePack {
                infoMessage = "Offline map cleared — rebuild when ready."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareRoute() {
        guard let routePackage else { return }

        isExporting = true
        defer { isExporting = false }

        do {
            exportURL = try RouteActions.exportGPXURL(for: routePackage, routeID: route.id)
            isSharePresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupExport() {
        RouteActions.cleanupExport(at: exportURL)
        exportURL = nil
    }

    private func deleteRoute() {
        do {
            try routeStore.deleteRoute(route)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if canImport(WatchConnectivity)
private struct WatchStatusRow: View {
    let transferState: TransferState
    let isSending: Bool
    let onSendToWatch: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transferState.systemImage)
                .font(.title3)
                .foregroundStyle(transferState.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Watch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transferState.displayName)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 8)

            trailingContent
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch transferState {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .queued, .transferring:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(transferState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notSent, .failed:
            if let onSendToWatch {
                Button(action: onSendToWatch) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Send to Watch")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isSending)
            }
        }
    }
}
#endif

private struct OfflineMapControls: View {
    let status: OfflinePackStatus
    let tileCount: Int
    let packSizeBytes: Int64
    let isBuilding: Bool
    var buildProgress: OfflinePackBuildProgress?
    var isDeleting: Bool = false
    let onBuild: () -> Void
    var onDelete: (() -> Void)?

    @State private var showDeleteConfirm = false

    var body: some View {
        if isBuilding {
            offlineBuildProgressCard
        } else if status == .missing {
            Button(action: onBuild) {
                Label("Download Offline Map", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(action: onBuild) {
                        Text("Rebuild")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)

                    if let onDelete {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isDeleting)
                        .confirmationDialog("Delete offline map?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                            Button("Delete Map", role: .destructive) {
                                onDelete()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The route stays on your iPhone; only downloaded map tiles are removed.")
                        }
                    }
                }
            }
        }
    }

    private var offlineBuildProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Building offline map…")
                .font(.subheadline.weight(.semibold))

            if let buildProgress {
                ProgressView(value: buildProgress.fractionComplete)
                Text(buildProgress.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusIcon: String {
        switch status {
        case .ready: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .missing: "map"
        }
    }

    private var statusColor: Color {
        switch status {
        case .ready: .green
        case .partial: .orange
        case .missing: .secondary
        }
    }

    private var statusSubtitle: String {
        switch status {
        case .missing:
            "Not downloaded"
        case .partial:
            "Partial · \(tileCount) tiles · \(formattedSize)"
        case .ready:
            "Ready · \(tileCount) tiles · \(formattedSize)"
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: packSizeBytes, countStyle: .file)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
