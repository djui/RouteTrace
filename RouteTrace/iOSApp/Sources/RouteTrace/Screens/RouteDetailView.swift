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
    @State private var isDeletingOfflinePack = false
    @State private var showDeleteOfflineConfirm = false
    @State private var isSendingToWatch = false
    @State private var isUpdatingActivityKind = false
    @State private var isExporting = false
    @State private var showDeleteConfirmation = false
    @State private var showSourceGPXUnavailable = false
    @State private var exportURL: URL?
    @State private var isSharePresented = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let routePackage {
                    RouteMapPreview(routePoints: routePackage.route)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 260)
                }

                statsSection
                altitudeSection
                offlineMapSection
            }
            .padding()
            .padding(.bottom, 80)
        }
        #if canImport(WatchConnectivity)
        .overlay(alignment: .bottomTrailing) {
            sendToWatchFAB
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
        #endif
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

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Distance", value: RouteFormatting.distance(route.distanceMeters), symbol: "ruler")
                StatTile(title: "Points", value: "\(route.simplifiedPointCount)", symbol: "point.3.connected.trianglepath.dotted")
                StatTile(title: "Gain", value: RouteFormatting.elevation(route.elevationGainMeters), symbol: "arrow.up.right")
                StatTile(title: "Loss", value: RouteFormatting.elevation(route.elevationLossMeters), symbol: "arrow.down.right")
                StatTile(title: "Watch", value: route.transferState.displayName, symbol: route.transferState.systemImage)
                ActivityTypeTile(
                    activityKind: activityKindBinding,
                    isUpdating: isUpdatingActivityKind
                )
            }
        }
    }

    private var activityKindBinding: Binding<ActivityKind> {
        Binding(
            get: { route.activityHint },
            set: { newKind in
                guard newKind != route.activityHint else { return }
                Task { await updateActivityKind(to: newKind) }
            }
        )
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
            Text("Offline Map")
                .font(.headline)

            OfflineMapActionRow(
                status: route.offlineStatus,
                tileCount: route.offlineTileCount,
                packSizeBytes: route.offlinePackSizeBytes,
                isBuilding: isBuildingOfflinePack,
                isDeleting: isDeletingOfflinePack,
                onAction: { Task { await buildOfflinePack() } },
                onDelete: route.offlineStatus == .missing ? nil : { showDeleteOfflineConfirm = true }
            )
        }
        .confirmationDialog("Delete offline map?", isPresented: $showDeleteOfflineConfirm, titleVisibility: .visible) {
            Button("Delete Map", role: .destructive) {
                Task { await deleteOfflinePack() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The route stays on your iPhone; only downloaded map tiles are removed.")
        }
    }

    private var routeActionsMenu: some View {
        Menu {
            Button {
                shareRoute()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting || routePackage == nil)

            Button {
                Task { await buildOfflinePack() }
            } label: {
                Label(offlineMapActionLabel, systemImage: "map.fill")
            }
            .disabled(isBuildingOfflinePack)

            #if canImport(WatchConnectivity)
            Button {
                Task { await sendToWatch() }
            } label: {
                Label("Send to Apple Watch", systemImage: "applewatch.and.arrow.forward")
            }
            .disabled(isSendingToWatch)
            #endif

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(isExporting)
    }

    private var offlineMapActionLabel: String {
        route.offlineStatus == .missing ? "Build Offline Map" : "Rebuild Offline Map"
    }

    #if canImport(WatchConnectivity)
    private var sendToWatchFAB: some View {
        Button {
            Task { await sendToWatch() }
        } label: {
            Group {
                if isSendingToWatch {
                    ProgressView()
                } else {
                    Image(systemName: "applewatch.and.arrow.forward")
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .disabled(isSendingToWatch)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
    #endif

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
        defer { isBuildingOfflinePack = false }
        do {
            _ = try await routeStore.buildOfflinePack(for: route)
            routePackage = try routeStore.loadRoutePackage(for: route)
        } catch RouteStoreError.offlinePackSavedArchiveFailed {
            routePackage = try? routeStore.loadRoutePackage(for: route)
            infoMessage = RouteStoreError.offlinePackSavedArchiveFailed.localizedDescription
        } catch {
            errorMessage = offlineMapBuildErrorMessage(for: error)
        }
    }

    private func offlineMapBuildErrorMessage(for error: Error) -> String {
        if let buildError = error as? OfflinePackBuilder.BuildError {
            return buildError.localizedDescription
        }
        if (error as NSError).domain == NSCocoaErrorDomain,
           (error as NSError).code == NSFileReadNoSuchFileError {
            return "Failed to package the offline map for Watch transfer. Try building again."
        }
        return error.localizedDescription
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
            let gpx = GPXExporter.exportRoute(routePackage)
            let url = RouteTracePaths.routesRoot
                .appendingPathComponent("\(route.id.uuidString)-export.gpx")
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            isSharePresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupExport() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
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

private struct OfflineMapActionRow: View {
    let status: OfflinePackStatus
    let tileCount: Int
    let packSizeBytes: Int64
    let isBuilding: Bool
    var isDeleting: Bool = false
    let onAction: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Offline map")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let onDelete, status != .missing {
                Button(action: onDelete) {
                    Text("Delete")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting || isBuilding)
            }

            Button(action: onAction) {
                HStack(spacing: 4) {
                    if isBuilding {
                        ProgressView()
                            .controlSize(.small)
                        Text("Building…")
                    } else {
                        Text(actionLabel)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(isBuilding || isDeleting)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var actionLabel: String {
        status == .missing ? "Build" : "Rebuild"
    }

    private var subtitle: String {
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

private struct ActivityTypeTile: View {
    @Binding var activityKind: ActivityKind
    let isUpdating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Activity Type", systemImage: activityKind.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Activity Type", selection: $activityKind) {
                ForEach(ActivityKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.headline)
            .disabled(isUpdating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
}
