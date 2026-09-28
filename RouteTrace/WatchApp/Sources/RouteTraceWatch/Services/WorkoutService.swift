import CoreLocation
import Foundation
import HealthKit
import Observation
import RouteTraceShared

enum WorkoutServiceStatus: Sendable, Equatable {
    case unavailable(String)
    case ready
    case running
    case paused
}

@MainActor
@Observable
final class WorkoutService: NSObject {
    private(set) var status: WorkoutServiceStatus = .ready
    private(set) var heartRateBPM: Double?
    private(set) var isHealthKitAvailable = HKHealthStore.isHealthDataAvailable()
    /// Zones HealthKit uses for this workout, with the time in each so far (watchOS 27 and later).
    private(set) var zones: [WorkoutZoneMetric: WorkoutZones] = [:]

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var workoutStartDate: Date?
    private var activityKind: ActivityKind = .running
    private var insertedLocationCount = 0
    /// Zone HealthKit last reported per metric; it only reports changes.
    private var reportedZoneIndices: [WorkoutZoneMetric: Int] = [:]

    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

    /// Workout zones need HealthKit from watchOS 27, and the SDK that ships with Xcode 27.
    static var supportsWorkoutZones: Bool {
        #if compiler(>=6.4)
        if #available(watchOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    var isSessionActive: Bool {
        switch status {
        case .running, .paused: true
        default: false
        }
    }

    /// Average heart rate as HealthKit computed it over the whole workout.
    var averageHeartRateBPM: Double? {
        guard let builder, let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return builder.statistics(for: type)?.averageQuantity()?.doubleValue(for: Self.heartRateUnit)
    }

    var heartRateZones: WorkoutZones? {
        zones[.heartRate]
    }

    /// Current heart-rate zone. Until HealthKit reports one (it only reports changes, and not
    /// again after a relaunch), the latest reading decides.
    var heartRateZoneIndex: Int? {
        guard let heartRateZones else { return nil }
        return reportedZoneIndices[.heartRate] ?? heartRateBPM.map(heartRateZones.zoneIndex(for:))
    }

    func requestAuthorization(for activityKind: ActivityKind) async {
        guard isHealthKitAvailable else {
            status = .unavailable("HealthKit is not available on this device.")
            return
        }

        var typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        var typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        var identifiers: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .distanceWalkingRunning, .distanceCycling]
        if activityKind.speedCategory == .cycling {
            // Lets the workout record a paired power meter, which power zones are based on.
            identifiers.append(.cyclingPower)
        }
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                typesToShare.insert(type)
                typesToRead.insert(type)
            }
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRate)
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            if case .unavailable = status {
                status = .ready
            }
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func startWorkout(activityKind: ActivityKind, startDate: Date) async {
        guard isHealthKitAvailable else {
            status = .unavailable("HealthKit unavailable.")
            return
        }

        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = Self.hkActivityType(for: activityKind)
            configuration.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            adopt(session: session, builder: builder, activityKind: activityKind, startDate: startDate)

            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            status = .running
            Task { await loadZones(for: builder) }
        } catch {
            reset()
            status = .unavailable(error.localizedDescription)
        }
    }

    /// Reattaches to the workout session watchOS kept running while the app was relaunched.
    /// Starting a second session would fail and lose heart rate and the Health record.
    @discardableResult
    func recoverActiveWorkout(activityKind: ActivityKind, startDate: Date) async -> Bool {
        guard isHealthKitAvailable, session == nil else { return session != nil }
        let recovered: HKWorkoutSession? = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        guard let recovered else { return false }

        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: recovered.workoutConfiguration)
        adopt(session: recovered, builder: builder, activityKind: activityKind, startDate: startDate)
        status = recovered.state == .paused ? .paused : .running
        Task { await loadZones(for: builder) }
        return true
    }

    func pauseWorkout() {
        session?.pause()
        if session != nil {
            status = .paused
        }
    }

    func resumeWorkout() {
        session?.resume()
        if session != nil {
            status = .running
        }
    }

    func insertRouteLocation(_ location: CLLocation) async {
        guard let routeBuilder else { return }
        do {
            try await routeBuilder.insertRouteData([location])
            insertedLocationCount += 1
        } catch {
            // A failed route sample doesn't invalidate the workout; keep recording.
        }
    }

    /// Ends the session and saves the workout (with its route) to Health. Returns the time in
    /// zones HealthKit recorded, which is empty before watchOS 27.
    @discardableResult
    func finishWorkout(
        endDate: Date,
        title: String,
        activityId: UUID,
        gpsDistanceMeters: Double
    ) async -> [WorkoutZones] {
        guard let session, let builder else { return [] }
        defer { reset() }

        session.end()

        do {
            try await builder.endCollection(at: endDate)
            try await addDistanceIfMissing(gpsDistanceMeters, to: builder, endDate: endDate)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: activityId.uuidString,
                HKMetadataKeyWorkoutBrandName: title
            ])

            guard let workout = try await builder.finishWorkout() else {
                return recordedZones(builder: builder, workout: nil)
            }

            if let routeBuilder, insertedLocationCount > 0 {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: [HKMetadataKeyWorkoutBrandName: title])
            }
            status = .ready
            return recordedZones(builder: builder, workout: workout)
        } catch {
            status = .unavailable(error.localizedDescription)
            return recordedZones(builder: builder, workout: nil)
        }
    }

    /// Time in zones so far, for the summary shown before the workout is saved.
    func zonesSoFar() -> [WorkoutZones] {
        guard let builder else { return [] }
        return recordedZones(builder: builder, workout: nil)
    }

    /// Ends the session without saving anything to Health (the user discarded the activity).
    func discardWorkout() async {
        guard let session, let builder else { return }
        defer { reset() }

        session.end()
        try? await builder.endCollection(at: Date())
        builder.discardWorkout()
        routeBuilder?.discard()
        status = .ready
    }

    /// The live data source already records distance for outdoor workouts; adding our own
    /// sample on top doubled it in Health. Only fill in when nothing was collected.
    private func addDistanceIfMissing(_ meters: Double, to builder: HKLiveWorkoutBuilder, endDate: Date) async throws {
        let identifier: HKQuantityTypeIdentifier = activityKind.speedCategory == .cycling ? .distanceCycling : .distanceWalkingRunning
        guard meters > 0, let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }

        let collected = builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
        guard collected <= 0 else { return }

        let start = workoutStartDate ?? endDate.addingTimeInterval(-60)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .meter(), doubleValue: meters),
            start: start,
            end: endDate
        )
        try await builder.addSamples([sample])
    }

    private func adopt(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder, activityKind: ActivityKind, startDate: Date) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        self.workoutStartDate = startDate
        self.activityKind = activityKind
        self.insertedLocationCount = 0
        self.zones = [:]
        self.reportedZoneIndices = [:]
    }

    private func reset() {
        session = nil
        builder = nil
        routeBuilder = nil
        workoutStartDate = nil
        insertedLocationCount = 0
        heartRateBPM = nil
        zones = [:]
        reportedZoneIndices = [:]
    }

    // MARK: - Workout zones

    /// Picks up the zones HealthKit applies to this workout: the person's zones from Health
    /// settings, which Health computes itself unless they set their own. Runs on its own so a
    /// slow answer never holds up the start.
    private func loadZones(for builder: HKLiveWorkoutBuilder) async {
        #if compiler(>=6.4)
        guard #available(watchOS 27.0, *) else { return }
        for metric in WorkoutZoneMetric.metrics(for: activityKind) {
            let type = metric.quantityType
            guard let configuration = try? await builder.zoneConfiguration(for: type),
                  let loaded = WorkoutZones(
                      configuration,
                      metric: metric,
                      durations: builder.zoneGroup(for: type)?.zoneDurations ?? []
                  ) else { continue }
            // A live update may have arrived while this was loading, or the workout ended.
            guard self.builder === builder else { return }
            if zones[metric] == nil {
                zones[metric] = loaded
            }
        }
        #endif
    }

    /// Final time in zones: what HealthKit holds for the workout, else the last live update.
    /// Zones without any time (no power meter, no heart rate) are left out.
    private func recordedZones(builder: HKLiveWorkoutBuilder, workout: HKWorkout?) -> [WorkoutZones] {
        let recorded = zones.merging(healthKitZones(builder: builder, workout: workout)) { _, saved in saved }
        return WorkoutZoneMetric.allCases.compactMap { recorded[$0] }.filter { $0.totalSeconds > 0 }
    }

    /// Zones from the saved workout if there is one, else from the builder.
    private func healthKitZones(builder: HKLiveWorkoutBuilder, workout: HKWorkout?) -> [WorkoutZoneMetric: WorkoutZones] {
        #if compiler(>=6.4)
        guard #available(watchOS 27.0, *) else { return [:] }
        var result: [WorkoutZoneMetric: WorkoutZones] = [:]
        for metric in WorkoutZoneMetric.allCases {
            let type = metric.quantityType
            if let group = workout?.zoneGroup(for: type) ?? builder.zoneGroup(for: type) {
                result[metric] = WorkoutZones(group, metric: metric)
            }
        }
        return result
        #else
        return [:]
        #endif
    }

    private static func hkActivityType(for kind: ActivityKind) -> HKWorkoutActivityType {
        switch kind {
        case .running, .trailRunning:
            return .running
        case .roadCycling, .gravelCycling:
            return .cycling
        }
    }
}

extension WorkoutService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                status = .running
            case .paused:
                status = .paused
            case .ended:
                status = .ready
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            status = .unavailable(error.localizedDescription)
        }
    }
}

extension WorkoutService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let bpm = workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }

        Task { @MainActor in
            heartRateBPM = bpm
        }
    }

    #if compiler(>=6.4)
    @available(watchOS 27.0, *)
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate
    ) {
        guard let group = zoneUpdate.zoneGroup,
              let metric = WorkoutZoneMetric(group.configuration.quantityType),
              let updated = WorkoutZones(group, metric: metric) else { return }
        let current = zoneUpdate.currentZoneDuration.flatMap { group.configuration.position(of: $0.zone) }

        Task { @MainActor in
            guard builder === workoutBuilder else { return }
            zones[metric] = updated
            reportedZoneIndices[metric] = current
        }
    }
    #endif
}

extension WorkoutZoneMetric {
    var quantityType: HKQuantityType {
        switch self {
        case .heartRate: HKQuantityType(.heartRate)
        case .cyclingPower: HKQuantityType(.cyclingPower)
        }
    }

    var healthKitUnit: HKUnit {
        switch self {
        case .heartRate: .count().unitDivided(by: .minute())
        case .cyclingPower: .watt()
        }
    }

    init?(_ quantityType: HKQuantityType) {
        guard let metric = Self.allCases.first(where: { $0.quantityType == quantityType }) else { return nil }
        self = metric
    }
}

#if compiler(>=6.4)
@available(watchOS 27.0, *)
extension HKWorkoutZoneConfiguration {
    /// Position of a zone counted from the lowest; HealthKit's own zone index isn't documented
    /// as starting at 0 or 1.
    func position(of zone: HKWorkoutZone) -> Int? {
        zones.map(\.index).sorted().firstIndex(of: zone.index)
    }
}

@available(watchOS 27.0, *)
extension WorkoutZones {
    init?(_ configuration: HKWorkoutZoneConfiguration, metric: WorkoutZoneMetric, durations: [HKWorkoutZoneDuration]) {
        let unit = metric.healthKitUnit
        let ordered = configuration.zones.sorted { $0.index < $1.index }
        let boundaries = ordered.dropFirst().compactMap { $0.minimum?.doubleValue(for: unit) }
        guard !ordered.isEmpty, boundaries.count == ordered.count - 1 else { return nil }

        var seconds = Array(repeating: 0.0, count: ordered.count)
        for entry in durations {
            if let position = configuration.position(of: entry.zone) {
                seconds[position] += entry.duration
            }
        }

        let source: Source? = switch configuration.source {
        case .system: .system
        case .user: .user
        case .app: .app
        @unknown default: nil
        }
        self.init(metric: metric, boundaries: boundaries, secondsInZone: seconds, source: source)
    }

    init?(_ group: HKWorkoutZoneGroup, metric: WorkoutZoneMetric) {
        self.init(group.configuration, metric: metric, durations: group.zoneDurations)
    }
}
#endif
