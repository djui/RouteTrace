import Foundation
import Observation
import RouteTraceShared
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private(set) var isReachable = false
    private(set) var isActivated = false
    private(set) var pendingTransferCount = 0
    private(set) var lastSyncMessage: String?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    /// Activities not yet delivered to the iPhone. WatchConnectivity retries queued transfers,
    /// but a transfer that fails (or whose temp file was purged) would otherwise be lost.
    private static let pendingActivitiesKey = "watch.pendingActivityUploads"

    private override init() {
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            isActivated = true
            isReachable = session.isReachable
            if let settings = SettingsSyncPayload(dictionary: session.receivedApplicationContext) {
                applySyncedSettings(settings)
            }
            resendPendingActivities()
        }
    }

    private func applySyncedSettings(_ settings: SettingsSyncPayload) {
        WatchPreferences.shared.applySyncedBatteryMode(settings.batteryMode)
        if UnitPreference.shared.system != settings.unitSystem {
            UnitPreference.shared.system = settings.unitSystem
            // Complications show distances too.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Activities

    func sendActivityRecording(_ recording: ActivityRecording) async {
        markActivityPending(recording.id)
        transfer(recording)
    }

    private func transfer(_ recording: ActivityRecording) {
        guard let session, session.activationState == .activated else { return }

        let alreadyQueued = session.outstandingFileTransfers.contains {
            $0.file.metadata?["activityId"] as? String == recording.id.uuidString
        }
        guard !alreadyQueued else { return }

        do {
            let data = try RouteTracePayloadCoding.encode(recording)
            // Application Support survives until delivery; tmp may be purged by the system.
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Outbox", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("activity-\(recording.id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)

            let metadata: [String: String] = [
                "type": WatchMessageType.activityRecording,
                "activityId": recording.id.uuidString,
                "routeId": recording.routeId.uuidString,
                "routeName": recording.routeName,
                "schemaVersion": "1"
            ]

            pendingTransferCount += 1
            session.transferFile(fileURL, metadata: metadata)
        } catch {
            lastSyncMessage = error.localizedDescription
        }
    }

    private func resendPendingActivities() {
        let pending = Self.pendingActivityIDs
        guard !pending.isEmpty else { return }
        for recording in WatchActivityStore.shared.activities where pending.contains(recording.id) {
            transfer(recording)
        }
    }

    private func markActivityPending(_ id: UUID) {
        var pending = Self.pendingActivityIDs
        pending.insert(id)
        Self.pendingActivityIDs = pending
    }

    private func markActivityDelivered(_ id: UUID) {
        var pending = Self.pendingActivityIDs
        pending.remove(id)
        Self.pendingActivityIDs = pending
    }

    private static var pendingActivityIDs: Set<UUID> {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: pendingActivitiesKey) ?? []
            return Set(strings.compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: pendingActivitiesKey)
        }
    }

    // MARK: - Routes

    private func acknowledgeRouteInstalled(package: RoutePackage) {
        send([
            "type": WatchMessageType.routeInstalled,
            "routeId": package.id.uuidString,
            "name": package.name,
            "schemaVersion": RouteTransferMetadata.schemaVersion
        ])
    }

    /// Lets the iPhone show the route as no longer on the watch (and not re-send it on its own).
    func notifyRouteRemoved(_ routeID: UUID) {
        send([
            "type": WatchMessageType.routeRemoved,
            "routeId": routeID.uuidString
        ])
    }

    /// Sends immediately when the iPhone is reachable, otherwise queues for guaranteed delivery.
    private func send(_ payload: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        let userInfo = UncheckedPayload(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                Task { @MainActor in
                    _ = self.session?.transferUserInfo(userInfo.value)
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func handleIncomingFile(url: URL, type: String?) async {
        let resolvedType = type ?? WatchMessageType.routePackage
        switch resolvedType {
        case WatchMessageType.routePackage, RoutePackaging.routepackExtension:
            do {
                let package = try await WatchRouteStore.shared.installRoutePackage(from: url)
                acknowledgeRouteInstalled(package: package)
            } catch {
                lastSyncMessage = "Failed to install route: \(error.localizedDescription)"
            }
        default:
            lastSyncMessage = "Ignored unknown transfer type: \(resolvedType)"
        }

        try? FileManager.default.removeItem(at: url)
    }

    private func handleUserInfo(_ userInfo: [String: Any]) async {
        if let request = RouteStartRequest(dictionary: userInfo) {
            RouteStartRequests.shared.receive(request)
            return
        }
        guard userInfo["type"] as? String == WatchMessageType.routeDeleted,
              let idString = userInfo["routeId"] as? String,
              let routeID = UUID(uuidString: idString) else { return }
        try? await WatchRouteStore.shared.deleteRoute(id: routeID, origin: .iPhone)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let activated = activationState == .activated
        let reachable = session.isReachable
        let message = error?.localizedDescription
        let settings = activated ? SettingsSyncPayload(dictionary: session.receivedApplicationContext) : nil
        Task { @MainActor in
            isActivated = activated
            isReachable = reachable
            if let settings {
                applySyncedSettings(settings)
            }
            lastSyncMessage = message
            if activated {
                resendPendingActivities()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let settings = SettingsSyncPayload(dictionary: applicationContext)
        Task { @MainActor in
            if let settings {
                applySyncedSettings(settings)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let payload = UncheckedPayload(userInfo)
        Task { @MainActor in
            await handleUserInfo(payload.value)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let type = file.metadata?["type"] as? String
        // WCSession deletes the file when this method returns, so copy it synchronously.
        guard let copiedURL = try? WCSessionFileInbox.copyToTemporaryURL(from: file.fileURL, prefix: "watch-inbox") else {
            Task { @MainActor in
                lastSyncMessage = "Failed to copy incoming file."
            }
            return
        }
        Task { @MainActor in
            await handleIncomingFile(url: copiedURL, type: type)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata ?? [:]
        let activityID = (metadata["activityId"] as? String).flatMap(UUID.init(uuidString:))
        let fileURL = fileTransfer.file.fileURL
        Task { @MainActor in
            pendingTransferCount = max(0, pendingTransferCount - 1)
            if let error {
                lastSyncMessage = "Transfer failed: \(error.localizedDescription)"
                return
            }
            if let activityID {
                markActivityDelivered(activityID)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

/// WatchConnectivity dictionaries are property-list values, safe to hand across actors.
private struct UncheckedPayload: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
