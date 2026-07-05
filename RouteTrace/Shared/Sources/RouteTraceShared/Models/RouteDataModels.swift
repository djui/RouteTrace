import Foundation
import SwiftData

@Model
public final class RouteEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var sourceFileName: String = ""
    public var importedAt: Date = Date()
    public var activityHintRaw: String = ActivityKind.running.rawValue
    public var distanceMeters: Double = 0
    public var elevationGainMeters: Double?
    public var elevationLossMeters: Double?
    public var minLatitude: Double = 0
    public var maxLatitude: Double = 0
    public var minLongitude: Double = 0
    public var maxLongitude: Double = 0
    public var originalPointCount: Int = 0
    public var simplifiedPointCount: Int = 0
    public var transferStateRaw: String = TransferState.notSent.rawValue
    public var offlineStatusRaw: String = OfflinePackStatus.missing.rawValue
    public var offlineTileCount: Int = 0
    public var offlinePackSizeBytes: Int64 = 0
    @Attribute(.externalStorage) public var routePackageData: Data = Data()

    public init(
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

    public var activityHint: ActivityKind {
        get { ActivityKind(rawValue: activityHintRaw) ?? .running }
        set { activityHintRaw = newValue.rawValue }
    }

    public var transferState: TransferState {
        get { TransferState(rawValue: transferStateRaw) ?? .notSent }
        set { transferStateRaw = newValue.rawValue }
    }

    public var offlineStatus: OfflinePackStatus {
        get { OfflinePackStatus(rawValue: offlineStatusRaw) ?? .missing }
        set { offlineStatusRaw = newValue.rawValue }
    }

    public var boundingBox: GeoBoundingBox {
        GeoBoundingBox(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }

    public var routeDirectoryURL: URL {
        RouteTracePaths.routeDirectory(for: id)
    }

    public func apply(_ package: RoutePackage) {
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

    public func decodedPackage() throws -> RoutePackage? {
        guard !routePackageData.isEmpty else { return nil }
        return try RouteTracePayloadCoding.decode(RoutePackage.self, from: routePackageData)
    }

    public static func from(_ package: RoutePackage) -> RouteEntity {
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
public final class ActivityEntity {
    public var id: UUID = UUID()
    public var routeId: UUID = UUID()
    public var routeName: String = ""
    public var title: String?
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var activityKindRaw: String = ActivityKind.running.rawValue
    public var totalDistanceMeters: Double = 0
    public var elapsedSeconds: Double = 0
    public var elevationGainMeters: Double?
    public var averageHeartRateBPM: Double?
    public var trackPointsData: Data = Data()
    public var offRouteEventsData: Data = Data()
    public var plannedRoutePointsData: Data = Data()
    @Attribute(.externalStorage) public var activityPayloadData: Data = Data()
    public var syncedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        routeId: UUID,
        routeName: String,
        title: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        activityKind: ActivityKind,
        totalDistanceMeters: Double,
        elapsedSeconds: TimeInterval,
        elevationGainMeters: Double? = nil,
        averageHeartRateBPM: Double? = nil,
        trackPoints: [TrackPoint] = [],
        offRouteEvents: [OffRouteEvent] = [],
        plannedRoutePoints: [RoutePoint]? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.routeId = routeId
        self.routeName = routeName
        self.title = title
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
        self.plannedRoutePointsData = (try? RouteTracePayloadCoding.encode(plannedRoutePoints)) ?? Data()
        self.activityPayloadData = (try? RouteTracePayloadCoding.encode(ActivityRecording(
            id: id,
            routeId: routeId,
            routeName: routeName,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            activityKind: activityKind,
            trackPoints: trackPoints,
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            offRouteEvents: offRouteEvents,
            elevationGainMeters: elevationGainMeters,
            averageHeartRateBPM: averageHeartRateBPM,
            plannedRoutePoints: plannedRoutePoints
        ))) ?? Data()
    }

    public var activityKind: ActivityKind {
        get { ActivityKind(rawValue: activityKindRaw) ?? .running }
        set { activityKindRaw = newValue.rawValue }
    }

    public var trackPoints: [TrackPoint] {
        get { (try? RouteTracePayloadCoding.decode([TrackPoint].self, from: trackPointsData)) ?? [] }
        set { trackPointsData = (try? RouteTracePayloadCoding.encode(newValue)) ?? Data() }
    }

    public var offRouteEvents: [OffRouteEvent] {
        get { (try? RouteTracePayloadCoding.decode([OffRouteEvent].self, from: offRouteEventsData)) ?? [] }
        set { offRouteEventsData = (try? RouteTracePayloadCoding.encode(newValue)) ?? Data() }
    }

    public var plannedRoutePoints: [RoutePoint]? {
        get {
            guard !plannedRoutePointsData.isEmpty else { return nil }
            return try? RouteTracePayloadCoding.decode([RoutePoint].self, from: plannedRoutePointsData)
        }
        set { plannedRoutePointsData = (try? RouteTracePayloadCoding.encode(newValue)) ?? Data() }
    }

    public func decodedRecording() throws -> ActivityRecording? {
        if !activityPayloadData.isEmpty {
            return try RouteTracePayloadCoding.decode(ActivityRecording.self, from: activityPayloadData)
        }
        return recording
    }

    public var displayTitle: String {
        title ?? routeName
    }

    public var recording: ActivityRecording {
        ActivityRecording(
            id: id,
            routeId: routeId,
            routeName: routeName,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            activityKind: activityKind,
            trackPoints: trackPoints,
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            offRouteEvents: offRouteEvents,
            elevationGainMeters: elevationGainMeters,
            averageHeartRateBPM: averageHeartRateBPM,
            plannedRoutePoints: plannedRoutePoints
        )
    }

    public static func from(_ recording: ActivityRecording) -> ActivityEntity {
        ActivityEntity(
            id: recording.id,
            routeId: recording.routeId,
            routeName: recording.routeName,
            title: recording.title,
            startedAt: recording.startedAt,
            endedAt: recording.endedAt,
            activityKind: recording.activityKind,
            totalDistanceMeters: recording.totalDistanceMeters,
            elapsedSeconds: recording.elapsedSeconds,
            elevationGainMeters: recording.elevationGainMeters,
            averageHeartRateBPM: recording.averageHeartRateBPM,
            trackPoints: recording.trackPoints,
            offRouteEvents: recording.offRouteEvents,
            plannedRoutePoints: recording.plannedRoutePoints
        )
    }
}

@Model
public final class AppSettingsEntity {
    public var id: UUID = UUID()
    public var defaultActivityKindRaw: String = ActivityKind.running.rawValue
    public var batteryModeRaw: String = BatteryMode.normal.rawValue
    public var mapDisplayModeRaw: String = MapDisplayMode.onlineNative.rawValue
    public var buildOfflinePacksByDefault: Bool = false

    public init(
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

    public var defaultActivityKind: ActivityKind {
        get { ActivityKind(rawValue: defaultActivityKindRaw) ?? .running }
        set { defaultActivityKindRaw = newValue.rawValue }
    }

    public var batteryMode: BatteryMode {
        get { BatteryMode(rawValue: batteryModeRaw) ?? .normal }
        set { batteryModeRaw = newValue.rawValue }
    }

    public var mapDisplayMode: MapDisplayMode {
        get { MapDisplayMode(rawValue: mapDisplayModeRaw) ?? .onlineNative }
        set { mapDisplayModeRaw = newValue.rawValue }
    }
}

public enum RouteTracePaths {
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static var routesRoot: URL {
        documentsDirectory.appendingPathComponent("Routes", isDirectory: true)
    }

    public static var activitiesRoot: URL {
        documentsDirectory.appendingPathComponent("Activities", isDirectory: true)
    }

    public static func routeDirectory(for routeID: UUID) -> URL {
        routesRoot.appendingPathComponent(routeID.uuidString, isDirectory: true)
    }

    public static func sourceGPXURL(for routeID: UUID) -> URL {
        routeDirectory(for: routeID).appendingPathComponent("source.gpx")
    }

    public static func hasSourceGPX(for routeID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: sourceGPXURL(for: routeID).path)
    }

    public static func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: routesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activitiesRoot, withIntermediateDirectories: true)
    }
}
