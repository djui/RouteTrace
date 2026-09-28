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

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var workoutStartDate: Date?
    private var activityKind: ActivityKind = .running
    private var insertedLocationCount = 0

    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

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
        for identifier: HKQuantityTypeIdentifier in [.activeEnergyBurned, .distanceWalkingRunning, .distanceCycling] {
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

    /// Ends the session and saves the workout (with its route) to Health.
    @discardableResult
    func finishWorkout(
        endDate: Date,
        title: String,
        activityId: UUID,
        gpsDistanceMeters: Double
    ) async -> HKWorkout? {
        guard let session, let builder else { return nil }
        defer { reset() }

        session.end()

        do {
            try await builder.endCollection(at: endDate)
            try await addDistanceIfMissing(gpsDistanceMeters, to: builder, endDate: endDate)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: activityId.uuidString,
                HKMetadataKeyWorkoutBrandName: title
            ])

            guard let workout = try await builder.finishWorkout() else { return nil }

            if let routeBuilder, insertedLocationCount > 0 {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: [HKMetadataKeyWorkoutBrandName: title])
            }
            status = .ready
            return workout
        } catch {
            status = .unavailable(error.localizedDescription)
            return nil
        }
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
    }

    private func reset() {
        session = nil
        builder = nil
        routeBuilder = nil
        workoutStartDate = nil
        insertedLocationCount = 0
        heartRateBPM = nil
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
}
