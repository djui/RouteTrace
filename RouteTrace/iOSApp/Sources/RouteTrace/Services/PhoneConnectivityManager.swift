#if canImport(WatchConnectivity)
import Combine
import Foundation
import os
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
    case routeRemoved(routeID: UUID)
    case routeOrder(RouteOrder)
    case activityRecording(Data)
    case unsupported
}

private nonisolated func parseIncomingWatchMessage(_ message: [String: Any]) -> IncomingWatchMessage {
    if let order = RouteOrder(dictionary: message) {
        return .routeOrder(order)
    }
    let type = message["type"] as? String
    if let routeIDString = message["routeId"] as? String,
       let routeID = UUID(uuidString: routeIDString) {
        switch type {
        case WatchMessageType.routeInstalled:
            return .routeInstalled(routeID: routeID, routeName: message["name"] as? String ?? "Route")
        case WatchMessageType.routeRemoved:
            return .routeRemoved(routeID: routeID)
        default:
            break
        }
    }

    if let payload = message["payload"] as? Data {
        return .activityRecording(payload)
    }

    return .unsupported
}

/// Something worth telling the user about, shown as a transient banner rather than an alert.
struct WatchTransferEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case installed
        case activityReceived
        case failed
    }

    let id = UUID()
    let kind: Kind
    let message: String
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

    private nonisolated static let logger = Logger(subsystem: "com.uwe.RouteTrace", category: "WatchConnectivity")

    private let context: ModelContext
    private let routeStore: RouteStore
    private let session: WCSession?
    /// The current transfer per route. A newer request (e.g. the route plus its freshly built
    /// offline map) cancels and replaces an older one that is still queued.
    private var inFlightTransfers: [UUID: WCSessionFileTransfer] = [:]
    private var inFlightTransferFiles: [UUID: URL] = [:]

    @Published private(set) var isActivated = false
    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var lastEvent: WatchTransferEvent?

    var onSessionActivated: (() -> Void)?

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
            return "RouteTrace isn’t installed on your Apple Watch"
        }
        if isWatchReachable {
            return "Connected"
        }
        return "Routes are delivered in the background"
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            refreshSessionState()
            onSessionActivated?()
        }
    }

    func refreshSessionState() {
        guard let session else { return }
        isActivated = session.activationState == .activated
        isWatchPaired = session.isPaired
        isWatchReachable = session.isReachable
        isWatchAppInstalled = session.isWatchAppInstalled
    }

    func syncSettingsToWatch(batteryMode: BatteryMode, unitSystem: UnitSystem = UnitPreference.shared.system) {
        // Without a paired watch this fails by design; that is not something to alert about.
        guard let session, session.activationState == .activated, canTransferToWatch else { return }
        let payload = SettingsSyncPayload(batteryMode: batteryMode, unitSystem: unitSystem)
        do {
            try session.updateApplicationContext(payload.dictionaryRepresentation)
        } catch {
            Self.logger.error("Settings sync failed: \(error.localizedDescription, privacy: .public)")
        }
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
        let transferURL = try WCSessionFileInbox.copyToTemporaryURL(from: archiveURL, prefix: "watch-transfer")
        let metadata = RouteTransferMetadata(routePackage: package).dictionaryRepresentation

        cancelInFlightTransfer(for: routeID)
        inFlightTransferFiles[routeID] = transferURL
        inFlightTransfers[routeID] = session.transferFile(transferURL, metadata: metadata)
        try routeStore.updateTransferState(for: routeID, state: .transferring)
    }

    /// Sends the route order to the watch. Queued until the watch app runs; the newer order wins.
    func sendRouteOrder(_ order: RouteOrder) {
        guard let session, session.activationState == .activated, canTransferToWatch else { return }
        session.transferUserInfo(order.dictionaryRepresentation)
    }

    /// Asks the watch to start navigating a route. Queued until the watch app runs; the watch
    /// ignores it once stale.
    func requestRouteStart(_ routeID: UUID) throws {
        guard let session, session.activationState == .activated else { throw ConnectivityError.sessionUnavailable }
        session.transferUserInfo(RouteStartRequest(routeID: routeID).dictionaryRepresentation)
    }

    /// Tells the watch to drop a route deleted on this iPhone. Queued until the watch app runs.
    func notifyRouteDeleted(_ routeID: UUID) {
        cancelInFlightTransfer(for: routeID)
        guard let session, session.activationState == .activated, canTransferToWatch else { return }
        session.transferUserInfo([
            "type": WatchMessageType.routeDeleted,
            "routeId": routeID.uuidString
        ])
    }

    private func cancelInFlightTransfer(for routeID: UUID) {
        if let transfer = inFlightTransfers.removeValue(forKey: routeID), transfer.isTransferring {
            transfer.cancel()
        }
        if let file = inFlightTransferFiles.removeValue(forKey: routeID) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func receiveActivityData(_ data: Data) -> Bool {
        do {
            let recording = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: data)
            let isNew = (try? routeStore.fetchActivity(id: recording.id)) == nil
            _ = try routeStore.saveActivity(recording)
            if isNew {
                lastEvent = WatchTransferEvent(kind: .activityReceived, message: "\(recording.displayTitle) synced from Apple Watch")
            }
            return true
        } catch {
            Self.logger.error("Failed to save activity from watch: \(error.localizedDescription, privacy: .public)")
            lastEvent = WatchTransferEvent(kind: .failed, message: "Couldn’t save an activity from Apple Watch.")
            return false
        }
    }

    private func handleRouteInstalledAck(routeID: UUID, routeName: String) {
        do {
            try routeStore.updateTransferState(for: routeID, state: .installed)
            lastEvent = WatchTransferEvent(kind: .installed, message: "\(routeName) is on your Apple Watch")
        } catch {
            Self.logger.error("Failed to record install ack: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleIncomingWatchMessage(_ message: IncomingWatchMessage) -> Bool {
        switch message {
        case .routeInstalled(let routeID, let routeName):
            handleRouteInstalledAck(routeID: routeID, routeName: routeName)
            return true
        case .routeRemoved(let routeID):
            // Deleted on the watch: don't auto-send it back, but keep it one tap away.
            try? routeStore.updateTransferState(for: routeID, state: .removedFromWatch)
            return true
        case .routeOrder(let order):
            RouteOrderStore.shared.apply(order)
            return true
        case .activityRecording(let payload):
            return receiveActivityData(payload)
        case .unsupported:
            return false
        }
    }

    private func handleReceivedFile(url: URL, type: String?) {
        defer { try? FileManager.default.removeItem(at: url) }
        switch type {
        case WatchMessageType.activityRecording:
            guard let data = try? Data(contentsOf: url) else { return }
            _ = receiveActivityData(data)
        default:
            break
        }
    }

    private func handleTransferCompletion(for routeID: UUID, transfer: WCSessionFileTransfer, error: Error?) {
        // Ignore completions of transfers that were superseded by a newer one.
        guard inFlightTransfers[routeID] === transfer else { return }
        inFlightTransfers.removeValue(forKey: routeID)
        if let transferURL = inFlightTransferFiles.removeValue(forKey: routeID) {
            try? FileManager.default.removeItem(at: transferURL)
        }

        guard let error else {
            // Delivered to the watch's queue; "installed" follows once the watch acknowledges.
            return
        }
        if (error as? WCError)?.code == .transferTimedOut || (error as NSError).code == NSUserCancelledError {
            Self.logger.info("Route transfer cancelled or timed out: \(error.localizedDescription, privacy: .public)")
        }
        try? routeStore.updateTransferState(for: routeID, state: .failed)
        let name = (try? routeStore.fetchRoute(id: routeID))?.name ?? "Route"
        lastEvent = WatchTransferEvent(kind: .failed, message: "Couldn’t send \(name) to Apple Watch")
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
            if activationState == .activated {
                syncSettingsToWatch(batteryMode: (try? routeStore.loadSettings())?.batteryMode ?? .normal)
                onSessionActivated?()
            }
            if let error {
                Self.logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSessionState()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasTransferable = canTransferToWatch
            refreshSessionState()
            // The watch app was just installed (or a watch paired): deliver pending routes.
            if !wasTransferable, canTransferToWatch {
                onSessionActivated?()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let incoming = parseIncomingWatchMessage(message)
        Task { @MainActor in
            _ = handleIncomingWatchMessage(incoming)
        }
    }

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
        // WCSession deletes the file when this method returns, so copy it synchronously.
        guard let copiedURL = try? WCSessionFileInbox.copyToTemporaryURL(from: file.fileURL, prefix: "phone-inbox") else {
            Self.logger.error("Failed to copy incoming file from watch")
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
            metadata["type"] as? String == WatchMessageType.routePackage,
            let routeIDString = metadata["routeId"] as? String,
            let routeID = UUID(uuidString: routeIDString)
        else {
            return
        }

        let transfer = UncheckedSendable(fileTransfer)
        Task { @MainActor in
            handleTransferCompletion(for: routeID, transfer: transfer.value, error: error)
        }
    }
}

/// Carries a non-Sendable WatchConnectivity object across to the main actor, where it is only
/// compared by identity.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
#endif
