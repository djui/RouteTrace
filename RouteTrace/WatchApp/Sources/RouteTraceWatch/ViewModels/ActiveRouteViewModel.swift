import CoreLocation
import Foundation
import Observation
import RouteTraceShared

@MainActor
@Observable
final class ActiveRouteViewModel {
    enum Phase: Equatable {
        case idle
        case active
        case paused
        case summary
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var routePackage: RoutePackage?
    private(set) var activityKind: ActivityKind = .running
    private(set) var navigationSnapshot: NavigationSnapshot?
    private(set) var recording = ActivityRecording(
        routeId: UUID(),
        routeName: "",
        activityKind: .running
    )
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var gpsAcquisitionState: GPSAcquisitionState = .idle
    private(set) var previewCoordinate: GeoCoordinate?

    private var displayCoordinateSmoother = DisplayCoordinateSmoother()

    var displayCoordinate: GeoCoordinate? {
        navigationSnapshot?.currentCoordinate ?? previewCoordinate
    }

    var showsWeakGPSIndicator: Bool {
        switch gpsAcquisitionState {
        case .warmingUp, .acquiring:
            return true
        case .idle, .ready:
            return false
        }
    }

    var gpsStatusLabel: String? {
        switch gpsAcquisitionState {
        case .idle, .ready:
            return nil
        case .warmingUp, .acquiring:
            return "Acquiring GPS…"
        }
    }

    let locationService = LocationTrackingService()
    let workoutService = WorkoutService()

    private var navigationEngine: RouteNavigationEngine?
    private var timer: Timer?
    private var activeOffRouteEvent: OffRouteEvent?
    private var lastElevationMeters: Double?
    private var heartRateSamples: [Double] = []
    private var lastNotifiedOffRouteLevel: RouteNotificationService.OffRouteLevel = .none
    private var lastNotifiedCueID: UUID?
    private var lastPersistenceAt: Date = .distantPast
    private var isWarmingUpGPS = false
    private var warmupActivityKind: ActivityKind = .running
    private var currentBatteryMode: BatteryMode = .normal
    private var locationQualityFilter = LocationQualityFilter()

    var isActive: Bool { phase == .active || phase == .paused || phase == .summary }
    var isPaused: Bool { phase == .paused }
    var isShowingSummary: Bool { phase == .summary }

    var progressFraction: Double {
        guard let snapshot = navigationSnapshot else { return 0 }
        let total = snapshot.progressDistanceMeters + snapshot.distanceRemainingMeters
        guard total > 0 else { return 0 }
        return min(1, max(0, snapshot.progressDistanceMeters / total))
    }

    var averageSpeedMetersPerSecond: Double? {
        guard elapsedSeconds > 0 else { return nil }
        let distance = recording.totalDistanceMeters
        guard distance > 0 else { return nil }
        return distance / elapsedSeconds
    }

    init() {
        locationService.onLocationUpdate = { [weak self] sample in
            self?.handleLocation(sample)
        }
    }

    func restoreIfNeeded(from routeStore: WatchRouteStore, preferences: WatchPreferences) async -> Bool {
        guard phase == .idle,
              let persisted = ActiveActivityPersistence.load(),
              persisted.phase == "active" || persisted.phase == "paused",
              let route = routeStore.route(with: persisted.routeId) else {
            return false
        }

        routePackage = route
        activityKind = persisted.activityKind
        recording = persisted.recording
        elapsedSeconds = persisted.elapsedSeconds

        let engine = RouteNavigationEngine(routePackage: route)
        engine.restoreState(persisted.engineState)
        navigationEngine = engine
        displayCoordinateSmoother.reset()

        if let lastPoint = recording.trackPoints.last {
            let coordinate = GeoCoordinate(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
            if let update = engine.update(
                latitude: lastPoint.latitude,
                longitude: lastPoint.longitude,
                horizontalAccuracyMeters: lastPoint.horizontalAccuracyMeters,
                speedMetersPerSecond: lastPoint.speedMetersPerSecond
            ) {
                navigationSnapshot = engine.makeSnapshot(
                    routeId: route.id,
                    coordinate: coordinate,
                    speed: lastPoint.speedMetersPerSecond,
                    update: update
                )
            }
        }

        locationService.applyBatteryMode(preferences.batteryMode)
        locationService.requestAuthorization()
        currentBatteryMode = preferences.batteryMode

        if let lastPoint = recording.trackPoints.last {
            locationQualityFilter.reset(
                startingStabilized: true,
                seed: qualityInput(from: lastPoint)
            )
            previewCoordinate = lastPoint.coordinate
            gpsAcquisitionState = .ready
        } else {
            locationQualityFilter.reset()
            previewCoordinate = nil
            gpsAcquisitionState = .acquiring
        }

        phase = persisted.phase == "paused" ? .paused : .active
        if phase == .active {
            locationService.startTracking(distanceFilterMeters: distanceFilter(for: preferences.batteryMode))
            startTimer()
        }

        if preferences.useHealthKitWorkouts {
            await workoutService.requestAuthorization(for: activityKind)
            await workoutService.startWorkout(activityKind: activityKind, startDate: recording.startedAt)
        }

        publishWidgetState()
        return true
    }

    func beginGPSWarmup(preferences: WatchPreferences, activityKind: ActivityKind) {
        guard phase == .idle else { return }

        warmupActivityKind = activityKind
        currentBatteryMode = preferences.batteryMode
        locationQualityFilter.reset()
        previewCoordinate = nil
        gpsAcquisitionState = .warmingUp
        isWarmingUpGPS = true

        locationService.applyBatteryMode(preferences.batteryMode)
        locationService.requestAuthorization()
        if !locationService.isTracking {
            locationService.startTracking(distanceFilterMeters: distanceFilter(for: preferences.batteryMode))
        }
    }

    func setWarmupActivityKind(_ activityKind: ActivityKind) {
        warmupActivityKind = activityKind
    }

    func endGPSWarmup() {
        guard phase == .idle, isWarmingUpGPS else { return }
        isWarmingUpGPS = false
        gpsAcquisitionState = .idle
        previewCoordinate = nil
        locationService.stopTracking()
    }

    func start(route: RoutePackage, activityKind: ActivityKind, preferences: WatchPreferences) async {
        guard phase == .idle || phase == .finished else { return }

        self.routePackage = route
        self.activityKind = activityKind
        self.navigationEngine = RouteNavigationEngine(routePackage: route)
        displayCoordinateSmoother.reset()
        self.elapsedSeconds = 0
        self.lastElevationMeters = nil
        self.heartRateSamples = []
        self.activeOffRouteEvent = nil
        self.lastError = nil
        self.lastNotifiedOffRouteLevel = .none
        self.lastNotifiedCueID = nil

        recording = ActivityRecording(
            routeId: route.id,
            routeName: route.name,
            activityKind: activityKind
        )

        isWarmingUpGPS = false
        currentBatteryMode = preferences.batteryMode

        if gpsAcquisitionState == .ready, let lastSample = locationService.lastSample {
            locationQualityFilter.reset(
                startingStabilized: true,
                seed: qualityInput(from: lastSample)
            )
            previewCoordinate = GeoCoordinate(
                latitude: lastSample.coordinate.latitude,
                longitude: lastSample.coordinate.longitude
            )
            gpsAcquisitionState = .ready
        } else {
            locationQualityFilter.reset()
            previewCoordinate = nil
            gpsAcquisitionState = .acquiring
        }

        locationService.applyBatteryMode(preferences.batteryMode)
        locationService.requestAuthorization()
        if !locationService.isTracking {
            locationService.startTracking(distanceFilterMeters: distanceFilter(for: preferences.batteryMode))
        }

        if preferences.useHealthKitWorkouts {
            await workoutService.requestAuthorization(for: activityKind)
            await workoutService.startWorkout(activityKind: activityKind, startDate: recording.startedAt)
        }

        if preferences.navigationNotificationsEnabled {
            _ = await RouteNotificationService.requestAuthorizationIfNeeded()
        }

        startTimer()
        phase = .active
        publishWidgetState()
        persistActivity()
    }

    func pause() {
        guard phase == .active else { return }
        phase = .paused
        locationService.stopTracking()
        workoutService.pauseWorkout()
        stopTimer()
        publishWidgetState()
        persistActivity()
    }

    func resume(preferences: WatchPreferences) {
        guard phase == .paused else { return }
        phase = .active
        currentBatteryMode = preferences.batteryMode
        locationService.applyBatteryMode(preferences.batteryMode)
        locationService.startTracking(distanceFilterMeters: distanceFilter(for: preferences.batteryMode))
        gpsAcquisitionState = locationQualityFilter.hasStabilized ? .ready : .acquiring
        workoutService.resumeWorkout()
        startTimer()
        publishWidgetState()
        persistActivity()
    }

    func togglePauseResume(preferences: WatchPreferences) {
        if phase == .active {
            pause()
        } else if phase == .paused {
            resume(preferences: preferences)
        }
    }

    func prepareSummary(preferences: WatchPreferences) {
        guard phase == .active || phase == .paused else { return }

        stopTimer()
        locationService.stopTracking()
        workoutService.pauseWorkout()

        recording.elapsedSeconds = elapsedSeconds
        recording.averageHeartRateBPM = averageHeartRate
        phase = .summary
        persistActivity()
    }

    func cancelSummary() {
        guard phase == .summary else { return }
        phase = .paused
        persistActivity()
        publishWidgetState()
    }

    func commitFinish(
        preferences: WatchPreferences,
        connectivity: WatchConnectivityManager,
        activityStore: WatchActivityStore
    ) async {
        guard phase == .summary else { return }

        let endDate = Date()
        var finishedRecording = recording
        finishedRecording.endedAt = endDate
        finishedRecording.elapsedSeconds = elapsedSeconds
        finishedRecording.averageHeartRateBPM = averageHeartRate
        finishedRecording.title = ActivityNaming.title(
            startedAt: finishedRecording.startedAt,
            activityKind: activityKind,
            routeName: finishedRecording.routeName
        )

        if preferences.useHealthKitWorkouts {
            _ = await workoutService.finishWorkout(
                endDate: endDate,
                routeName: finishedRecording.displayTitle,
                activityId: finishedRecording.id,
                totalDistanceMeters: finishedRecording.totalDistanceMeters,
                activityKind: activityKind
            )
        }

        recording = finishedRecording
        phase = .finished
        navigationSnapshot = nil
        navigationEngine = nil
        displayCoordinateSmoother.reset()
        routePackage = nil
        ActiveActivityPersistence.clear()
        WatchWidgetStateWriter.clear()

        try? await activityStore.save(finishedRecording)

        await RouteNotificationService.notifyActivityComplete(
            activityTitle: finishedRecording.displayTitle,
            distanceMeters: finishedRecording.totalDistanceMeters,
            elapsedSeconds: elapsedSeconds
        )

        await connectivity.sendActivityRecording(finishedRecording)
    }

    func discardActivity() {
        stopTimer()
        locationService.stopTracking()
        Task {
            switch workoutService.status {
            case .running, .paused:
                _ = await workoutService.finishWorkout(endDate: Date())
            default:
                break
            }
        }
        phase = .idle
        routePackage = nil
        navigationEngine = nil
        navigationSnapshot = nil
        displayCoordinateSmoother.reset()
        previewCoordinate = nil
        gpsAcquisitionState = .idle
        isWarmingUpGPS = false
        locationQualityFilter.reset()
        lastNotifiedOffRouteLevel = .none
        lastNotifiedCueID = nil
        ActiveActivityPersistence.clear()
        WatchWidgetStateWriter.clear()
    }

    func cancel() {
        discardActivity()
    }

    private func handleLocation(_ sample: LocationSample) {
        let input = qualityInput(from: sample)

        if phase == .idle {
            guard isWarmingUpGPS else { return }

            let outcome = locationQualityFilter.evaluate(
                input: input,
                activityKind: warmupActivityKind,
                batteryMode: currentBatteryMode,
                mode: .warmup
            )

            guard case .rejected = outcome else {
                updatePreviewCoordinate(from: sample)
                gpsAcquisitionState = locationQualityFilter.isWarmupReady(
                    input: input,
                    activityKind: warmupActivityKind
                ) ? .ready : .warmingUp
                return
            }

            gpsAcquisitionState = .warmingUp
            return
        }

        guard phase == .active, let route = routePackage, let engine = navigationEngine else { return }

        let outcome = locationQualityFilter.evaluate(
            input: input,
            activityKind: activityKind,
            batteryMode: currentBatteryMode,
            mode: .recording
        )

        switch outcome {
        case .rejected:
            gpsAcquisitionState = locationQualityFilter.hasStabilized ? .ready : .acquiring
            return
        case .previewOnly:
            updatePreviewCoordinate(from: sample)
            gpsAcquisitionState = .acquiring
            return
        case .accepted:
            updatePreviewCoordinate(from: sample)
            gpsAcquisitionState = .ready
        }

        guard let update = engine.update(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond
        ) else { return }

        let coordinate = GeoCoordinate(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude
        )

        let displayCoordinate = displayCoordinateSmoother.coordinate(
            raw: coordinate,
            projected: update.projectedCoordinate,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            isOffRoute: update.isOffRoute,
            recordingAccuracyThresholdMeters: currentBatteryMode.gpsRecordingAccuracyMeters
        )

        let snapshot = engine.makeSnapshot(
            routeId: route.id,
            coordinate: displayCoordinate,
            speed: sample.speedMetersPerSecond,
            update: update
        )
        navigationSnapshot = snapshot

        updateOffRouteEvents(update: update, coordinate: coordinate)
        appendTrackPoint(sample: sample, update: update)

        if workoutService.status == .running {
            let location = CLLocation(
                coordinate: sample.coordinate,
                altitude: sample.altitudeMeters ?? 0,
                horizontalAccuracy: sample.horizontalAccuracyMeters,
                verticalAccuracy: sample.altitudeMeters == nil ? -1 : 5,
                course: sample.courseDegrees ?? -1,
                speed: sample.speedMetersPerSecond ?? -1,
                timestamp: sample.timestamp
            )
            Task {
                await workoutService.insertRouteLocation(location)
            }
        }

        if let heartRate = workoutService.heartRateBPM {
            heartRateSamples.append(heartRate)
        }

        publishWidgetState()
        evaluateNavigationNotifications(snapshot: snapshot)
        persistActivityIfNeeded()
    }

    private func appendTrackPoint(sample: LocationSample, update: RouteNavigationUpdate) {
        var elevationGain = recording.elevationGainMeters ?? 0
        if let altitude = sample.altitudeMeters, let last = lastElevationMeters {
            let delta = altitude - last
            if delta > 0 { elevationGain += delta }
        }
        if let altitude = sample.altitudeMeters {
            lastElevationMeters = altitude
        }

        let point = TrackPoint(
            timestamp: sample.timestamp,
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude,
            altitudeMeters: sample.altitudeMeters,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            heartRateBPM: workoutService.heartRateBPM,
            snappedDistanceFromStartMeters: update.progressDistanceMeters,
            offRouteDistanceMeters: update.offRouteDistanceMeters
        )

        recording.trackPoints.append(point)
        recording.totalDistanceMeters = update.progressDistanceMeters
        recording.elapsedSeconds = elapsedSeconds
        recording.elevationGainMeters = elevationGain
        recording.averageHeartRateBPM = averageHeartRate
    }

    private func updateOffRouteEvents(update: RouteNavigationUpdate, coordinate: GeoCoordinate) {
        if update.isOffRoute {
            if activeOffRouteEvent == nil {
                activeOffRouteEvent = OffRouteEvent(
                    id: UUID(),
                    startedAt: Date(),
                    endedAt: nil,
                    maxDistanceMeters: update.offRouteDistanceMeters,
                    coordinate: coordinate
                )
                recording.offRouteEvents.append(activeOffRouteEvent!)
            } else if let event = activeOffRouteEvent {
                let updated = OffRouteEvent(
                    id: event.id,
                    startedAt: event.startedAt,
                    endedAt: nil,
                    maxDistanceMeters: max(event.maxDistanceMeters, update.offRouteDistanceMeters),
                    coordinate: coordinate
                )
                activeOffRouteEvent = updated
                if let index = recording.offRouteEvents.firstIndex(where: { $0.id == event.id }) {
                    recording.offRouteEvents[index] = updated
                }
            }
        } else if let event = activeOffRouteEvent {
            let closed = OffRouteEvent(
                id: event.id,
                startedAt: event.startedAt,
                endedAt: Date(),
                maxDistanceMeters: event.maxDistanceMeters,
                coordinate: event.coordinate
            )
            if let index = recording.offRouteEvents.firstIndex(where: { $0.id == event.id }) {
                recording.offRouteEvents[index] = closed
            }
            activeOffRouteEvent = nil
        }
    }

    private var averageHeartRate: Double? {
        guard !heartRateSamples.isEmpty else { return nil }
        return heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .active else { return }
                self.elapsedSeconds += 1
                self.recording.elapsedSeconds = self.elapsedSeconds
                self.publishWidgetState()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func publishWidgetState() {
        guard let route = routePackage, let snapshot = navigationSnapshot else { return }
        WatchWidgetStateWriter.writeSnapshot(
            snapshot,
            routeName: route.name,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused
        )
    }

    private func persistActivityIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPersistenceAt) >= 2 else { return }
        persistActivity()
    }

    private func persistActivity() {
        guard let route = routePackage, let engine = navigationEngine else { return }
        guard phase == .active || phase == .paused || phase == .summary else { return }

        let phaseKey: String = switch phase {
        case .active: "active"
        case .paused: "paused"
        case .summary: "summary"
        default: "idle"
        }

        let snapshot = PersistedActiveActivity(
            phase: phaseKey,
            routeId: route.id,
            activityKind: activityKind,
            recording: recording,
            elapsedSeconds: elapsedSeconds,
            engineState: engine.exportState()
        )
        ActiveActivityPersistence.save(snapshot)
        lastPersistenceAt = Date()
    }

    private func evaluateNavigationNotifications(snapshot: NavigationSnapshot) {
        guard WatchPreferences.shared.navigationNotificationsEnabled else { return }

        if snapshot.isCriticallyOffRoute && lastNotifiedOffRouteLevel != .critical {
            lastNotifiedOffRouteLevel = .critical
            Task {
                await RouteNotificationService.notifyCriticalOffRoute(distanceMeters: snapshot.offRouteDistanceMeters)
            }
        } else if snapshot.isOffRoute && lastNotifiedOffRouteLevel == .none {
            lastNotifiedOffRouteLevel = .warning
            Task {
                await RouteNotificationService.notifyOffRouteWarning(distanceMeters: snapshot.offRouteDistanceMeters)
            }
        } else if !snapshot.isOffRoute {
            lastNotifiedOffRouteLevel = .none
        }

        if let cue = snapshot.nextCue,
           RouteNotificationService.cueNotificationThresholdMet(distanceMeters: snapshot.distanceToNextCueMeters),
           lastNotifiedCueID != cue.id,
           let distance = snapshot.distanceToNextCueMeters {
            lastNotifiedCueID = cue.id
            Task {
                await RouteNotificationService.notifyUpcomingCue(cue, distanceMeters: distance)
            }
        }
    }

    private func distanceFilter(for mode: BatteryMode) -> CLLocationDistance {
        switch mode {
        case .normal: 5
        case .saver: 12
        case .ultraSaver: 25
        }
    }

    private func qualityInput(from sample: LocationSample) -> LocationQualityInput {
        LocationQualityInput(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            timestamp: sample.timestamp
        )
    }

    private func qualityInput(from point: TrackPoint) -> LocationQualityInput {
        LocationQualityInput(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracyMeters: point.horizontalAccuracyMeters,
            speedMetersPerSecond: point.speedMetersPerSecond,
            timestamp: point.timestamp
        )
    }

    private func updatePreviewCoordinate(from sample: LocationSample) {
        guard MapMath.isValidCoordinate(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude
        ) else { return }

        previewCoordinate = GeoCoordinate(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude
        )
    }
}
