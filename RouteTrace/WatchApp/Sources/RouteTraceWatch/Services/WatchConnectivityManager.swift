import Foundation
import Observation
import RouteTraceShared
import WatchConnectivity

@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private(set) var isReachable = false
    private(set) var isActivated = false
    private(set) var pendingTransferCount = 0
    private(set) var lastSyncMessage: String?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

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
        }
    }

    func sendActivityRecording(_ recording: ActivityRecording) async {
        guard let session, session.activationState == .activated else {
            lastSyncMessage = "Watch Connectivity unavailable."
            return
        }

        do {
            let data = try RouteTracePayloadCoding.encode(recording)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("activity-\(recording.id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)

            let metadata: [String: String] = [
                "type": "activityRecording",
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

    private func acknowledgeRouteInstalled(package: RoutePackage) {
        guard let session, session.activationState == .activated else { return }

        let payload: [String: Any] = [
            "type": "routeInstalled",
            "routeId": package.id.uuidString,
            "name": package.name,
            "schemaVersion": RouteTransferMetadata.schemaVersion
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                Task { @MainActor in
                    self.transferUserInfoAcknowledgement(payload)
                }
            }
        } else {
            transferUserInfoAcknowledgement(payload)
        }
    }

    private func transferUserInfoAcknowledgement(_ payload: [String: Any]) {
        _ = session?.transferUserInfo(payload)
    }

    private func handleIncomingFile(url: URL, type: String?) async {
        let resolvedType = type ?? "routePackage"
        switch resolvedType {
        case "routePackage", RoutePackaging.routepackExtension:
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
        Task { @MainActor in
            isActivated = activated
            isReachable = reachable
            if let message {
                lastSyncMessage = message
            } else if !activated {
                lastSyncMessage = nil
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let type = file.metadata?["type"] as? String
        let copiedURL: URL?
        do {
            copiedURL = try WCSessionFileInbox.copyToTemporaryURL(from: file.fileURL, prefix: "watch-inbox")
        } catch {
            copiedURL = nil
        }
        guard let copiedURL else {
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
        Task { @MainActor in
            pendingTransferCount = max(0, pendingTransferCount - 1)
            if let error {
                lastSyncMessage = "Transfer failed: \(error.localizedDescription)"
            }
        }
    }
}
