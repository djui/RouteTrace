import SwiftUI
import SwiftData
import RouteTraceShared

/// Confirms an import: shows the route on a map with its key numbers before saving.
struct ImportRouteView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Environment(\.dismiss) private var dismiss

    let candidate: GPXImportCandidate
    var onImported: (RouteEntity) -> Void

    @State private var name: String
    @State private var activity: ActivityKind = .running
    @State private var reverseDirection = false
    @State private var buildOfflineMap = false
    @State private var preview: RoutePackage?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var didApplyDefaults = false

    init(candidate: GPXImportCandidate, onImported: @escaping (RouteEntity) -> Void) {
        self.candidate = candidate
        self.onImported = onImported
        _name = State(initialValue: candidate.suggestedName)
    }

    private struct PreviewKey: Hashable {
        let activity: ActivityKind
        let reverse: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    previewHeader
                        .listRowInsets(EdgeInsets())
                }

                Section("Name") {
                    TextField("Route Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }

                Section {
                    Picker(selection: $activity) {
                        ForEach(ActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    } label: {
                        Label("Activity", systemImage: activity.systemImage)
                    }
                } footer: {
                    Text("Off-route alerts after \(Int(activity.offRouteWarningMeters)) m. The offline map covers \(RouteFormatting.distance(activity.corridorBufferMeters)) on either side of the route.")
                }

                Section {
                    Toggle(isOn: $reverseDirection) {
                        Label("Reverse Direction", systemImage: "arrow.left.arrow.right")
                    }
                    Toggle(isOn: $buildOfflineMap) {
                        Label("Download Offline Map", systemImage: "map")
                    }
                } footer: {
                    Text("The offline map is prepared on this iPhone in the background and sent to your Apple Watch, so the map works without a connection.")
                }

                if let warning = preview?.navigationWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("Import") {
                            Task { await importRoute() }
                        }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preview == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isImporting)
            .task {
                applyDefaultsIfNeeded()
            }
            .task(id: PreviewKey(activity: activity, reverse: reverseDirection)) {
                preview = await candidate.previewPackage(activity: activity, reverseDirection: reverseDirection)
            }
        }
    }

    @ViewBuilder
    private var previewHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                if let preview {
                    RouteMapPreview(routePoints: preview.route)
                        .id(reverseDirection)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { ProgressView() }
                }
            }
            .frame(height: 230)

            HStack(spacing: 12) {
                HeadlineStat(
                    title: "Distance",
                    value: preview.map { RouteFormatting.distance($0.distanceMeters) } ?? "—"
                )
                HeadlineStat(
                    title: "Ascent",
                    value: RouteFormatting.elevation(preview?.elevationGainMeters)
                )
                HeadlineStat(
                    title: "Descent",
                    value: RouteFormatting.elevation(preview?.elevationLossMeters)
                )
            }
            .padding(16)
        }
    }

    private func applyDefaultsIfNeeded() {
        guard !didApplyDefaults else { return }
        didApplyDefaults = true
        if let settings = try? routeStore.loadSettings() {
            activity = settings.defaultActivityKind
            buildOfflineMap = settings.buildOfflinePacksByDefault
        }
    }

    private func importRoute() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let entity = try await RouteImportService(routeStore: routeStore).importRoute(
                candidate,
                name: name,
                activityHint: activity,
                reverseDirection: reverseDirection,
                buildOfflinePack: buildOfflineMap
            )
            onImported(entity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
