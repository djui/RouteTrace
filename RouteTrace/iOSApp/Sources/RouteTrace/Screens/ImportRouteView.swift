import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import RouteTraceShared

struct ImportRouteView: View {
    @ObservedObject var routeStore: RouteStore
    @ObservedObject var incomingGPX: IncomingGPXCoordinator
    let initialFileURL: URL?

    @Environment(\.dismiss) private var dismiss

    @State private var importService: RouteImportService?
    @State private var settings: AppSettingsEntity?

    @State private var isImporterPresented = false
    @State private var selectedFileURL: URL?
    @State private var routeName = ""
    @State private var selectedActivity: ActivityKind = .running
    @State private var buildOfflinePack = false
    @State private var reverseDirection = false
    @State private var isImporting = false
    @State private var importProgress: OfflinePackBuildProgress?
    @State private var errorMessage: String?
    @State private var navigationWarning: String?

    init(
        routeStore: RouteStore,
        incomingGPX: IncomingGPXCoordinator,
        initialFileURL: URL? = nil
    ) {
        self.routeStore = routeStore
        self.incomingGPX = incomingGPX
        self.initialFileURL = initialFileURL
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GPX File") {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(
                            selectedFileURL?.lastPathComponent ?? "Choose GPX File",
                            systemImage: "doc.badge.plus"
                        )
                    }

                    TextField("Route Name", text: $routeName)
                        .textInputAutocapitalization(.words)
                }

                Section("Activity") {
                    Picker("Activity Type", selection: $selectedActivity) {
                        ForEach(ActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .onChange(of: selectedActivity) { _, _ in
                        Task { await previewNavigationWarning() }
                    }
                }

                if let navigationWarning {
                    Section {
                        Label(navigationWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                Section("Options") {
                    Toggle("Reverse Direction", isOn: $reverseDirection)
                        .onChange(of: reverseDirection) { _, _ in
                            Task { await previewNavigationWarning() }
                        }
                    Toggle("Build Offline Map Pack", isOn: $buildOfflinePack)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Route")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        incomingGPX.clearPending()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveRoute() }
                    }
                    .disabled(selectedFileURL == nil || isImporting)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [GPXDocumentSupport.gpxType, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    applySelectedFile(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .overlay {
                if isImporting {
                    importProgressOverlay
                }
            }
            .onAppear {
                configureImport()
            }
        }
    }

    private func configureImport() {
        if importService == nil {
            importService = RouteImportService(routeStore: routeStore)
        }
        if settings == nil {
            settings = try? routeStore.loadSettings()
            if let settings {
                selectedActivity = settings.defaultActivityKind
                buildOfflinePack = settings.buildOfflinePacksByDefault
            }
        }
        if let initialFileURL, selectedFileURL == nil {
            applySelectedFile(initialFileURL)
        }
    }

    private func applySelectedFile(_ url: URL) {
        selectedFileURL = url
        if routeName.isEmpty {
            routeName = url.deletingPathExtension().lastPathComponent
        }
        Task { await previewNavigationWarning() }
    }

    @MainActor
    private func previewNavigationWarning() async {
        navigationWarning = nil
        guard let url = selectedFileURL else { return }

        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let parsed = try GPXParser().parse(data: data)
            let package = RouteProcessor().makeRoutePackage(
                from: parsed,
                sourceFileName: url.lastPathComponent,
                activityHint: selectedActivity,
                customName: routeName.nilIfEmpty,
                reverseDirection: reverseDirection
            )
            navigationWarning = package.navigationWarning
        } catch {
            navigationWarning = nil
        }
    }

    @MainActor
    private func saveRoute() async {
        guard let url = selectedFileURL else { return }
        isImporting = true
        importProgress = nil
        errorMessage = nil
        defer {
            isImporting = false
            importProgress = nil
        }

        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            _ = try await importService?.importGPX(
                data: data,
                fileName: url.lastPathComponent,
                customName: routeName,
                activityHint: selectedActivity,
                buildOfflinePack: buildOfflinePack,
                reverseDirection: reverseDirection,
                onOfflineBuildProgress: { progress in
                    importProgress = progress
                }
            )
            incomingGPX.clearPending()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var importProgressOverlay: some View {
        VStack(spacing: 10) {
            if let importProgress {
                Text("Building offline map…")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: importProgress.fractionComplete)
                Text(importProgress.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Importing route…")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
