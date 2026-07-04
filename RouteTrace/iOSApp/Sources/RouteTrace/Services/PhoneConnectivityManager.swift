#if canImport(WatchConnectivity)
import Combine
import Foundation
import SwiftData
import WatchConnectivity
import RouteTraceShared

private struct WatchReplyHandler: @unchecked Sendable {
    let reply: ([String: Any]) -> Void

    func callAsFunction(_ dictionary: [String: Any]) {
        reply(dictionary)
    }
}

private enum IncomingWatchMessage: Sendable {
    case routeInstalled(routeID: UUID, routeName: String)
    case activityRecording(Data)
    case unsupported
}

private nonisolated func parseIncomingWatchMessage(_ message: [String: Any]) -> IncomingWatchMessage {
    if message["type"] as? String == "routeInstalled",
       let routeIDString = message["routeId"] as? String,
       let routeID = UUID(uuidString: routeIDString) {
        let routeName = message["name"] as? String ?? "Route"
        return .routeInstalled(routeID: routeID, routeName: routeName)
    }

    if let payload = message["payload"] as? Data {
        return .activityRecording(payload)
    }

    return .unsupported
}

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    enum ConnectivityError: Error, LocalizedError {
        case sessionUnavailable
        case watchNotPaired
        case watchAppNotInstalled
        case routeNotFound
        case archiveMissing

        var errorDescription: String? {
            switch self {
            case .sessionUnavailable:
                "Apple Watch connectivity is unavailable."
            case .watchNotPaired:
                "No Apple Watch is paired with this iPhone."
            case .watchAppNotInstalled:
                "RouteTrace is not installed on your Apple Watch. Install it from the Watch app, then try again."
            case .routeNotFound:
                "The route could not be found."
            case .archiveMissing:
                "The route pack file is missing."
            }
        }
    }

    private let context: ModelContext
    private let routeStore: RouteStore
    private let session: WCSession?

    @Published private(set) var isActivated = false
    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var lastTransferError: String?
    @Published private(set) var lastTransferSuccess: String?

    init(
        context: ModelContext,
        routeStore: RouteStore,
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) {
        self.context = context
        self.routeStore = routeStore
        self.session = session
        super.init()
    }

    var canTransferToWatch: Bool {
        isWatchPaired && isWatchAppInstalled
    }

    var statusSummary: String {
        if !isWatchPaired {
            return "No Apple Watch paired"
        }
        if !isWatchAppInstalled {
            return "Install RouteTrace on your Watch"
        }
        if isWatchReachable {
            return "Apple Watch connected"
        }
        return "Apple Watch will receive the route in the background"
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            refreshSessionState()
        }
    }

    func refreshSessionState() {
        guard let session else { return }
        isActivated = session.activationState == .activated
        isWatchPaired = session.isPaired
        isWatchReachable = session.isReachable
        #if os(iOS)
        isWatchAppInstalled = session.isWatchAppInstalled
        #else
        isWatchAppInstalled = true
        #endif
    }

    func transferRouteToWatch(routeID: UUID) throws {
        guard let session else { throw ConnectivityError.sessionUnavailable }
        refreshSessionState()
        guard isWatchPaired else { throw ConnectivityError.watchNotPaired }
        guard isWatchAppInstalled else { throw ConnectivityError.watchAppNotInstalled }

        guard let entity = try routeStore.fetchRoute(id: routeID) else {
            throw ConnectivityError.routeNotFound
        }

        let package = try routeStore.loadRoutePackage(for: entity)
        let archiveURL = try routeStore.ensureRoutepackArchive(for: entity)

        let metadata = RouteTransferMetadata(routePackage: package).dictionaryRepresentation
        try routeStore.updateTransferState(for: routeID, state: .queued)
        lastTransferError = nil
        lastTransferSuccess = nil

        session.transferFile(archiveURL, metadata: metadata)
        try routeStore.updateTransferState(for: routeID, state: .transferring)
        lastTransferSuccess = "Route queued for Apple Watch."
    }

    private func receiveActivityData(_ data: Data) -> Bool {
        do {
            let recording = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: data)
            _ = try routeStore.saveActivity(recording)
            return true
        } catch {
            lastTransferError = error.localizedDescription
            return false
        }
    }

    private func handleRouteInstalledAck(routeID: UUID, routeName: String) {
        do {
            try routeStore.updateTransferState(for: routeID, state: .installed)
            lastTransferSuccess = "\"\(routeName)\" is now on your Apple Watch."
            lastTransferError = nil
        } catch {
            lastTransferError = error.localizedDescription
        }
    }

    private func handleIncomingWatchMessage(_ message: IncomingWatchMessage) -> Bool {
        switch message {
        case .routeInstalled(let routeID, let routeName):
            handleRouteInstalledAck(routeID: routeID, routeName: routeName)
            return true
        case .activityRecording(let payload):
            return receiveActivityData(payload)
        case .unsupported:
            return false
        }
    }

    private func handleReceivedFile(url: URL, type: String?) {
        switch type {
        case "activityRecording":
            guard let data = try? Data(contentsOf: url) else { return }
            _ = receiveActivityData(data)
            try? FileManager.default.removeItem(at: url)
        default:
            break
        }
    }

    private func handleTransferCompletion(for routeID: UUID, error: Error?) {
        do {
            if let error {
                lastTransferError = error.localizedDescription
                try routeStore.updateTransferState(for: routeID, state: .failed)
            }
            // Successful delivery to the watch transfer queue; final "installed"
            // state is set when the watch acknowledges installation.
        } catch {
            lastTransferError = error.localizedDescription
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshSessionState()
            if let error {
                lastTransferError = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSessionState()
        }
    }
    #endif

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let incoming = parseIncomingWatchMessage(message)
        let reply = WatchReplyHandler(reply: replyHandler)
        Task { @MainActor in
            let acknowledged = handleIncomingWatchMessage(incoming)
            reply(["acknowledged": acknowledged])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let incoming = parseIncomingWatchMessage(userInfo)
        Task { @MainActor in
            _ = handleIncomingWatchMessage(incoming)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let type = file.metadata?["type"] as? String
        let copiedURL: URL?
        do {
            copiedURL = try WCSessionFileInbox.copyToTemporaryURL(from: file.fileURL, prefix: "phone-inbox")
        } catch {
            copiedURL = nil
        }
        guard let copiedURL else {
            Task { @MainActor in
                lastTransferError = "Failed to copy incoming file from Watch."
            }
            return
        }
        Task { @MainActor in
            handleReceivedFile(url: copiedURL, type: type)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let metadata = fileTransfer.file.metadata ?? [:]
        guard
            metadata["type"] as? String == "routePackage",
            let routeIDString = metadata["routeId"] as? String,
            let routeID = UUID(uuidString: routeIDString)
        else {
            return
        }

        Task { @MainActor in
            handleTransferCompletion(for: routeID, error: error)
        }
    }
}
#endif
