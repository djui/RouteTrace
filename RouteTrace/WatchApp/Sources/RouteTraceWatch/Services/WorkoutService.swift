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
    private var insertedLocationCount = 0

    func requestAuthorization(for activityKind: ActivityKind) async {
        guard isHealthKitAvailable else {
            status = .unavailable("HealthKit is not available on this device.")
            return
        }

        var typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            typesToShare.insert(energy)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            typesToShare.insert(distance)
        }

        var typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned, .distanceWalkingRunning] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                typesToRead.insert(type)
            }
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            status = .ready
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
            configuration.activityType = hkActivityType(for: activityKind)
            configuration.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder
            self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            self.workoutStartDate = startDate
            self.insertedLocationCount = 0

            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            status = .running
        } catch {
            session = nil
            builder = nil
            routeBuilder = nil
            workoutStartDate = nil
            status = .unavailable(error.localizedDescription)
        }
    }

    func pauseWorkout() {
        session?.pause()
        status = .paused
    }

    func resumeWorkout() {
        session?.resume()
        status = .running
    }

    func insertRouteLocation(_ location: CLLocation) async {
        guard let routeBuilder else { return }
        await withCheckedContinuation { continuation in
            routeBuilder.insertRouteData([location]) { success, error in
                if success {
                    Task { @MainActor in
                        self.insertedLocationCount += 1
                    }
                } else if let error {
                    Task { @MainActor in
                        if case .running = self.status {
                            self.status = .unavailable(error.localizedDescription)
                        }
                    }
                }
                continuation.resume()
            }
        }
    }

    func finishWorkout(
        endDate: Date,
        routeName: String? = nil,
        activityId: UUID? = nil,
        totalDistanceMeters: Double? = nil,
        activityKind: ActivityKind? = nil
    ) async -> HKWorkout? {
        guard let session, let builder else { return nil }

        session.end()

        do {
            try await builder.endCollection(at: endDate)

            if let totalDistanceMeters, totalDistanceMeters > 0,
               let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let start = workoutStartDate ?? endDate.addingTimeInterval(-60)
                let quantity = HKQuantity(unit: .meter(), doubleValue: totalDistanceMeters)
                let sample = HKQuantitySample(type: distanceType, quantity: quantity, start: start, end: endDate)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add([sample]) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }

            let workout = try await builder.finishWorkout()

            if let routeBuilder, let workout, insertedLocationCount > 0 {
                var metadata: [String: Any] = [
                    HKMetadataKeyExternalUUID: activityId?.uuidString ?? workout.uuid.uuidString
                ]
                if let routeName {
                    metadata[HKMetadataKeyWorkoutBrandName] = routeName
                }

                await withCheckedContinuation { continuation in
                    routeBuilder.finishRoute(with: workout, metadata: metadata) { _, error in
                        if let error {
                            Task { @MainActor in
                                self.status = .unavailable(error.localizedDescription)
                            }
                        }
                        continuation.resume()
                    }
                }
            }

            self.session = nil
            self.builder = nil
            self.routeBuilder = nil
            self.workoutStartDate = nil
            self.insertedLocationCount = 0
            status = .ready
            return workout
        } catch {
            self.session = nil
            self.builder = nil
            self.routeBuilder = nil
            self.workoutStartDate = nil
            self.insertedLocationCount = 0
            status = .unavailable(error.localizedDescription)
            return nil
        }
    }

    private func hkActivityType(for kind: ActivityKind) -> HKWorkoutActivityType {
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
              collectedTypes.contains(heartRateType) else { return }

        Task { @MainActor in
            let statistics = workoutBuilder.statistics(for: heartRateType)
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let quantity = statistics?.mostRecentQuantity() {
                heartRateBPM = quantity.doubleValue(for: unit)
            }
        }
    }
}
