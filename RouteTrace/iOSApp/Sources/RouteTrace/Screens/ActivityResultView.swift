import SwiftUI
import SwiftData
import RouteTraceShared

struct ActivityResultView: View {
    @EnvironmentObject private var routeStore: RouteStore

    let activity: ActivityEntity

    @State private var plannedRoute: RoutePackage?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isSharePresented = false
    @State private var errorMessage: String?

    private var recording: ActivityRecording {
        activity.recording
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RouteMapPreview(
                    routePoints: plannedRoute?.route ?? [],
                    trackPoints: recording.trackPoints,
                    lineColor: .blue.opacity(0.55),
                    trackColor: .green
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                statsSection

                if let plannedRoute, plannedRoute.hasElevationData {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Planned Elevation")
                            .font(.headline)
                        AltitudeChartView(routePoints: plannedRoute.route)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(activity.routeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportGPX()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)
            }
        }
        .sheet(isPresented: $isSharePresented, onDismiss: cleanupExport) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .alert("Activity Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadPlannedRoute()
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Distance", value: RouteFormatting.distance(recording.totalDistanceMeters), symbol: "ruler")
                StatTile(title: "Duration", value: RouteFormatting.duration(recording.elapsedSeconds), symbol: "clock")
                StatTile(title: "Activity", value: recording.activityKind.displayName, symbol: recording.activityKind.systemImage)
                StatTile(
                    title: "Elevation Gain",
                    value: RouteFormatting.elevation(recording.elevationGainMeters),
                    symbol: "arrow.up.right"
                )
                StatTile(
                    title: "Avg Heart Rate",
                    value: recording.averageHeartRateBPM.map { String(format: "%.0f bpm", $0) } ?? "—",
                    symbol: "heart.fill"
                )
                StatTile(
                    title: "Off Route Events",
                    value: "\(recording.offRouteEvents.count)",
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    @MainActor
    private func loadPlannedRoute() async {
        guard let routeEntity = try? routeStore.fetchRoute(id: recording.routeId) else { return }
        plannedRoute = try? routeStore.loadRoutePackage(for: routeEntity)
    }

    private func exportGPX() {
        isExporting = true
        defer { isExporting = false }

        do {
            let gpx = GPXExporter.exportActivity(recording, route: plannedRoute)
            let url = RouteTracePaths.activitiesRoot
                .appendingPathComponent("\(recording.id.uuidString).gpx")
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
