import Foundation
import SwiftData
import RouteTraceShared

@Model
final class RouteEntity {
    var id: UUID = UUID()
    var name: String = ""
    var sourceFileName: String = ""
    var importedAt: Date = Date()
    var activityHintRaw: String = ActivityKind.running.rawValue
    var distanceMeters: Double = 0
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    var minLatitude: Double = 0
    var maxLatitude: Double = 0
    var minLongitude: Double = 0
    var maxLongitude: Double = 0
    var originalPointCount: Int = 0
    var simplifiedPointCount: Int = 0
    var transferStateRaw: String = TransferState.notSent.rawValue
    var offlineStatusRaw: String = OfflinePackStatus.missing.rawValue
    var offlineTileCount: Int = 0
    var offlinePackSizeBytes: Int64 = 0
    @Attribute(.externalStorage) var routePackageData: Data = Data()

    init(
        id: UUID = UUID(),
        name: String,
        sourceFileName: String,
        importedAt: Date = Date(),
        activityHint: ActivityKind,
        distanceMeters: Double,
        elevationGainMeters: Double?,
        elevationLossMeters: Double?,
        boundingBox: GeoBoundingBox,
        originalPointCount: Int,
        simplifiedPointCount: Int,
        transferState: TransferState = .notSent,
        offlineStatus: OfflinePackStatus = .missing,
        offlineTileCount: Int = 0,
        offlinePackSizeBytes: Int64 = 0,
        routePackageData: Data = Data()
    ) {
        self.id = id
        self.name = name
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.activityHintRaw = activityHint.rawValue
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.minLatitude = boundingBox.minLatitude
        self.maxLatitude = boundingBox.maxLatitude
        self.minLongitude = boundingBox.minLongitude
        self.maxLongitude = boundingBox.maxLongitude
        self.originalPointCount = originalPointCount
        self.simplifiedPointCount = simplifiedPointCount
        self.transferStateRaw = transferState.rawValue
        self.offlineStatusRaw = offlineStatus.rawValue
        self.offlineTileCount = offlineTileCount
        self.offlinePackSizeBytes = offlinePackSizeBytes
        self.routePackageData = routePackageData
    }

    var activityHint: ActivityKind {
        get { ActivityKind(rawValue: activityHintRaw) ?? .running }
        set { activityHintRaw = newValue.rawValue }
    }

    var transferState: TransferState {
        get { TransferState(rawValue: transferStateRaw) ?? .notSent }
        set { transferStateRaw = newValue.rawValue }
    }

    var offlineStatus: OfflinePackStatus {
        get { OfflinePackStatus(rawValue: offlineStatusRaw) ?? .missing }
        set { offlineStatusRaw = newValue.rawValue }
    }

    var boundingBox: GeoBoundingBox {
        GeoBoundingBox(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }

    var routeDirectoryURL: URL {
        RouteTracePaths.routeDirectory(for: id)
    }

    func apply(_ package: RoutePackage) {
        name = package.name
        sourceFileName = package.sourceFileName
        importedAt = package.importedAt
        activityHint = package.activityHint
        distanceMeters = package.distanceMeters
        elevationGainMeters = package.elevationGainMeters
        elevationLossMeters = package.elevationLossMeters
        minLatitude = package.boundingBox.minLatitude
        maxLatitude = package.boundingBox.maxLatitude
        minLongitude = package.boundingBox.minLongitude
        maxLongitude = package.boundingBox.maxLongitude
        originalPointCount = package.originalPointCount
        simplifiedPointCount = package.simplifiedPointCount
        offlineStatus = package.offlineStatus
        offlineTileCount = package.offlineMapManifest?.tileCount ?? 0
        offlinePackSizeBytes = package.offlineMapManifest?.packSizeBytes ?? 0
        routePackageData = (try? RouteTracePayloadCoding.encode(package)) ?? routePackageData
    }

    func decodedPackage() throws -> RoutePackage? {
        guard !routePackageData.isEmpty else { return nil }
        return try RouteTracePayloadCoding.decode(RoutePackage.self, from: routePackageData)
    }

    static func from(_ package: RoutePackage) -> RouteEntity {
        RouteEntity(
            id: package.id,
            name: package.name,
            sourceFileName: package.sourceFileName,
            importedAt: package.importedAt,
            activityHint: package.activityHint,
            distanceMeters: package.distanceMeters,
            elevationGainMeters: package.elevationGainMeters,
            elevationLossMeters: package.elevationLossMeters,
            boundingBox: package.boundingBox,
            originalPointCount: package.originalPointCount,
            simplifiedPointCount: package.simplifiedPointCount,
            offlineStatus: package.offlineStatus,
            offlineTileCount: package.offlineMapManifest?.tileCount ?? 0,
            offlinePackSizeBytes: package.offlineMapManifest?.packSizeBytes ?? 0,
            routePackageData: (try? RouteTracePayloadCoding.encode(package)) ?? Data()
        )
    }
}

@Model
final class ActivityEntity {
    var id: UUID = UUID()
    var routeId: UUID = UUID()
    var routeName: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var activityKindRaw: String = ActivityKind.running.rawValue
    var totalDistanceMeters: Double = 0
    var elapsedSeconds: Double = 0
    var elevationGainMeters: Double?
    var averageHeartRateBPM: Double?
    var trackPointsData: Data = Data()
    var offRouteEventsData: Data = Data()
    @Attribute(.externalStorage) var activityPayloadData: Data = Data()
    var syncedAt: Date = Date()

    init(
        id: UUID = UUID(),
        routeId: UUID,
        routeName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        activityKind: ActivityKind,
        totalDistanceMeters: Double,
        elapsedSeconds: TimeInterval,
        elevationGainMeters: Double? = nil,
        averageHeartRateBPM: Double? = nil,
        trackPoints: [TrackPoint] = [],
        offRouteEvents: [OffRouteEvent] = [],
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.routeId = routeId
        self.routeName = routeName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activityKindRaw = activityKind.rawValue
        self.totalDistanceMeters = totalDistanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRateBPM = averageHeartRateBPM
        self.syncedAt = syncedAt
        self.trackPointsData = (try? RouteTracePayloadCoding.encode(trackPoints)) ?? Data()
        self.offRouteEventsData = (try? RouteTracePayloadCoding.encode(offRouteEvents)) ?? Data()
        self.activityPayloadData = (try? RouteTracePayloadCoding.encode(ActivityRecording(
            id: id,
            routeId: routeId,
            routeName: routeName,
            startedAt: startedAt,
            endedAt: endedAt,
            activityKind: activityKind,
            trackPoints: trackPoints,
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            offRouteEvents: offRouteEvents,
            elevationGainMeters: elevationGainMeters,
            averageHeartRateBPM: averageHeartRateBPM
        ))) ?? Data()
    }

    var activityKind: ActivityKind {
        get { ActivityKind(rawValue: activityKindRaw) ?? .running }
        set { activityKindRaw = newValue.rawValue }
    }

    var trackPoints: [TrackPoint] {
        get { (try? RouteTracePayloadCoding.decode([TrackPoint].self, from: trackPointsData)) ?? [] }
        set { trackPointsData = (try? RouteTracePayloadCoding.encode(newValue)) ?? Data() }
    }

    var offRouteEvents: [OffRouteEvent] {
        get { (try? RouteTracePayloadCoding.decode([OffRouteEvent].self, from: offRouteEventsData)) ?? [] }
        set { offRouteEventsData = (try? RouteTracePayloadCoding.encode(newValue)) ?? Data() }
    }

    func decodedRecording() throws -> ActivityRecording? {
        if !activityPayloadData.isEmpty {
            return try RouteTracePayloadCoding.decode(ActivityRecording.self, from: activityPayloadData)
        }
        return recording
    }

    var recording: ActivityRecording {
        ActivityRecording(
            id: id,
            routeId: routeId,
            routeName: routeName,
            startedAt: startedAt,
            endedAt: endedAt,
            activityKind: activityKind,
            trackPoints: trackPoints,
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            offRouteEvents: offRouteEvents,
            elevationGainMeters: elevationGainMeters,
            averageHeartRateBPM: averageHeartRateBPM
        )
    }

    static func from(_ recording: ActivityRecording) -> ActivityEntity {
        ActivityEntity(
            id: recording.id,
            routeId: recording.routeId,
            routeName: recording.routeName,
            startedAt: recording.startedAt,
            endedAt: recording.endedAt,
            activityKind: recording.activityKind,
            totalDistanceMeters: recording.totalDistanceMeters,
            elapsedSeconds: recording.elapsedSeconds,
            elevationGainMeters: recording.elevationGainMeters,
            averageHeartRateBPM: recording.averageHeartRateBPM,
            trackPoints: recording.trackPoints,
            offRouteEvents: recording.offRouteEvents
        )
    }
}

@Model
final class AppSettingsEntity {
    var id: UUID = UUID()
    var defaultActivityKindRaw: String = ActivityKind.running.rawValue
    var batteryModeRaw: String = BatteryMode.normal.rawValue
    var mapDisplayModeRaw: String = MapDisplayMode.onlineNative.rawValue
    var buildOfflinePacksByDefault: Bool = false

    init(
        id: UUID = UUID(),
        defaultActivityKind: ActivityKind = .running,
        batteryMode: BatteryMode = .normal,
        mapDisplayMode: MapDisplayMode = .onlineNative,
        buildOfflinePacksByDefault: Bool = false
    ) {
        self.id = id
        self.defaultActivityKindRaw = defaultActivityKind.rawValue
        self.batteryModeRaw = batteryMode.rawValue
        self.mapDisplayModeRaw = mapDisplayMode.rawValue
        self.buildOfflinePacksByDefault = buildOfflinePacksByDefault
    }

    var defaultActivityKind: ActivityKind {
        get { ActivityKind(rawValue: defaultActivityKindRaw) ?? .running }
        set { defaultActivityKindRaw = newValue.rawValue }
    }

    var batteryMode: BatteryMode {
        get { BatteryMode(rawValue: batteryModeRaw) ?? .normal }
        set { batteryModeRaw = newValue.rawValue }
    }

    var mapDisplayMode: MapDisplayMode {
        get { MapDisplayMode(rawValue: mapDisplayModeRaw) ?? .onlineNative }
        set { mapDisplayModeRaw = newValue.rawValue }
    }
}

enum RouteTracePaths {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var routesRoot: URL {
        documentsDirectory.appendingPathComponent("Routes", isDirectory: true)
    }

    static var activitiesRoot: URL {
        documentsDirectory.appendingPathComponent("Activities", isDirectory: true)
    }

    static func routeDirectory(for routeID: UUID) -> URL {
        routesRoot.appendingPathComponent(routeID.uuidString, isDirectory: true)
    }

    static func sourceGPXURL(for routeID: UUID) -> URL {
        routeDirectory(for: routeID).appendingPathComponent("source.gpx")
    }

    static func hasSourceGPX(for routeID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: sourceGPXURL(for: routeID).path)
    }

    static func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: routesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activitiesRoot, withIntermediateDirectories: true)
    }
}
