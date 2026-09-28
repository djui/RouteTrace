import CoreLocation
import Foundation
import Observation
import RouteTraceShared

/// Where the route is when the runner has left it.
struct RejoinGuidance: Equatable {
    let distanceMeters: Double
    /// Compass bearing from the runner to the closest point on the route.
    let bearingDegrees: Double
    /// Direction of travel, when moving; lets the arrow point relative to the runner.
    let courseDegrees: Double?

    var relativeBearingDegrees: Double? {
        courseDegrees.map { MapMath.normalizeBearing(bearingDegrees - $0) }
    }

    var compassDirection: String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((MapMath.normalizeBearing(bearingDegrees) + 22.5) / 45) % 8]
    }
}

/// Elevation along the route, prepared once per route for the altitude page.
struct RouteElevationProfile: Equatable {
    struct Sample: Equatable {
        let distanceMeters: Double
        let elevationMeters: Double
    }

    let samples: [Sample]
    let totalDistanceMeters: Double
    let minElevation: Double
    let maxElevation: Double

    init?(route: RoutePackage, maxSamples: Int = 160) {
        let all = route.route.compactMap { point in
            point.elevationMeters.map { Sample(distanceMeters: point.distanceFromStartMeters, elevationMeters: $0) }
        }
        guard all.count >= 2 else { return nil }
        samples = ProfileDownsampler.downsample(all, maxCount: maxSamples)
        totalDistanceMeters = route.navigationDistanceMeters
        minElevation = samples.map(\.elevationMeters).min() ?? 0
        maxElevation = samples.map(\.elevationMeters).max() ?? 1
    }

    func elevation(at distance: Double) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if distance <= first.distanceMeters { return first.elevationMeters }
        if distance >= last.distanceMeters { return last.elevationMeters }
        guard let upper = samples.firstIndex(where: { $0.distanceMeters >= distance }), upper > 0 else {
            return last.elevationMeters
        }
        let a = samples[upper - 1]
        let b = samples[upper]
        let span = b.distanceMeters - a.distanceMeters
        guard span > 0 else { return b.elevationMeters }
        return a.elevationMeters + (distance - a.distanceMeters) / span * (b.elevationMeters - a.elevationMeters)
    }

    /// Climbing still ahead of `distance`.
    func remainingAscent(after distance: Double) -> Double {
        let ahead = samples.filter { $0.distanceMeters >= distance }.map(\.elevationMeters)
        return ElevationStatistics.gainAndLoss(of: ahead, thresholdMeters: ElevationStatistics.routeThresholdMeters).gain
    }
}

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
    private(set) var recording = ActivityRecording(routeId: UUID(), routeName: "", activityKind: .running)
    private(set) var elapsedSeconds: TimeInterval = 0
    /// Distance actually covered (GPS), as opposed to progress along the route.
    private(set) var gpsDistanceMeters: Double = 0
    private(set) var elevationGainMeters: Double?
    private(set) var currentSpeedMetersPerSecond: Double?
    private(set) var lastError: String?
    private(set) var gpsAcquisitionState: GPSAcquisitionState = .idle
    private(set) var previewCoordinate: GeoCoordinate?
    /// The recorded track, thinned for drawing (every fix would be thousands of points).
    private(set) var displayTrack: [GeoCoordinate] = []
    private(set) var rejoinGuidance: RejoinGuidance?
    private(set) var elevationProfile: RouteElevationProfile?
    private(set) var preferredStartPage: BatteryPreferredStartPage?

    var displayCoordinate: GeoCoordinate? {
        navigationSnapshot?.currentCoordinate ?? previewCoordinate
    }

    /// Direction of travel while moving; nil when standing still.
    var courseDegrees: Double? {
        guard let sample = locationService.lastSample,
              let course = sample.courseDegrees,
              (sample.speedMetersPerSecond ?? 0) > 0.7 else { return nil }
        return course
    }

    var showsWeakGPSIndicator: Bool {
        switch gpsAcquisitionState {
        case .warmingUp, .acquiring: true
        case .idle, .ready: false
        }
    }

    var gpsStatusLabel: String? {
        showsWeakGPSIndicator ? "Acquiring GPS…" : nil
    }

    static let upcomingCueDisplayDistanceMeters = 500.0

    var upcomingCueDisplay: (cue: RouteCue, distanceMeters: Double, isOffRoute: Bool)? {
        guard let snapshot = navigationSnapshot,
              let cue = snapshot.nextCue,
              cue.kind != .finish,
              let distance = snapshot.distanceToNextCueMeters,
              distance <= Self.upcomingCueDisplayDistanceMeters else {
            return nil
        }
        return (cue, distance, snapshot.isOffRoute)
    }

    let locationService = LocationTrackingService()
    let workoutService = WorkoutService()
    let displayUpdateCoordinator = DisplayUpdateCoordinator()

    private var navigationEngine: RouteNavigationEngine?
    private var timer: Timer?
    private var clock = ActivityClock()
    private var liveStats = LiveTrackStatistics()
    private var speedEstimator = SpeedEstimator()
    private var alertTracker = NavigationAlertTracker()
    private var zoneAlertPolicy = ZoneChangeAlertPolicy()
    private var activeOffRouteEvent: OffRouteEvent?
    private var lastPersistenceAt: Date = .distantPast
    private var isWarmingUpGPS = false
    private var warmupActivityKind: ActivityKind = .running
    private var currentBatteryMode: BatteryMode = .normal
    private var currentBatteryPolicy = BatteryModePolicy(mode: .normal)
    private var locationQualityFilter = LocationQualityFilter()
    private var displayCoordinateSmoother = DisplayCoordinateSmoother()

    /// Spacing of the drawn track; finer detail is invisible on a watch map.
    private static let displayTrackSpacingMeters = 4.0

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
        ActivityTrackStatistics.averageSpeedMetersPerSecond(
            gpsDistanceMeters: gpsDistanceMeters,
            elapsedSeconds: elapsedSeconds
        )
    }

    var averageHeartRateBPM: Double? {
        if let fromHealth = workoutService.averageHeartRateBPM {
            return fromHealth
        }
        let values = recording.trackPoints.compactMap(\.heartRateBPM)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    init() {
        locationService.onLocationUpdate = { [weak self] sample in
            self?.handleLocation(sample)
        }
    }

    // MARK: - Lifecycle

    func restoreIfNeeded(from routeStore: WatchRouteStore, preferences: WatchPreferences) async -> Bool {
        guard phase == .idle,
              let persisted = ActiveActivityPersistence.load(),
              ["active", "paused", "summary"].contains(persisted.phase),
              let route = routeStore.route(with: persisted.routeId) else {
            return false
        }

        prepare(route: route, activityKind: persisted.activityKind)
        var restored = persisted.recording
        if restored.plannedRoutePoints == nil {
            restored.plannedRoutePoints = route.route
        }
        recording = restored
        clock = persisted.resolvedClock
        elapsedSeconds = clock.elapsed()
        liveStats = LiveTrackStatistics(rebuildingFrom: recording.trackPoints)
        gpsDistanceMeters = liveStats.distanceMeters
        elevationGainMeters = liveStats.elevationGainMeters
        displayTrack = Self.thinnedTrack(recording.trackPoints.map(\.coordinate))

        let engine = RouteNavigationEngine(routePackage: route)
        engine.restoreState(persisted.engineState)
        navigationEngine = engine

        if let lastPoint = recording.trackPoints.last,
           let update = engine.previewUpdate(
               latitude: lastPoint.latitude,
               longitude: lastPoint.longitude,
               horizontalAccuracyMeters: lastPoint.horizontalAccuracyMeters,
               speedMetersPerSecond: nil
           ) {
            navigationSnapshot = engine.makeSnapshot(routeId: route.id, coordinate: lastPoint.coordinate, speed: nil, update: update)
            locationQualityFilter.reset(startingStabilized: true, seed: qualityInput(from: lastPoint))
            previewCoordinate = lastPoint.coordinate
            gpsAcquisitionState = .ready
        } else {
            navigationSnapshot = engine.makeInitialSnapshot(routeId: route.id)
            locationQualityFilter.reset()
            gpsAcquisitionState = .acquiring
        }

        applyBatterySettings(from: preferences)
        locationService.requestAuthorization()

        switch persisted.phase {
        case "paused": phase = .paused
        case "summary": phase = .summary
        default: phase = .active
        }

        if phase == .active {
            clock.start()
            locationService.startTracking(distanceFilterMeters: currentBatteryPolicy.distanceFilterMeters)
        }
        startTimer()

        if preferences.useHealthKitWorkouts {
            let recovered = await workoutService.recoverActiveWorkout(activityKind: activityKind, startDate: recording.startedAt)
            if !recovered {
                await workoutService.requestAuthorization(for: activityKind)
                await workoutService.startWorkout(activityKind: activityKind, startDate: recording.startedAt)
            }
            if phase != .active {
                workoutService.pauseWorkout()
            }
        }

        publishWidgetState(forceTimelineReload: true)
        return true
    }

    func start(route: RoutePackage, activityKind: ActivityKind, preferences: WatchPreferences) async {
        guard phase == .idle || phase == .finished else { return }

        // Permission sheets can stay up for minutes on first use; ask before anything is timestamped,
        // or the Health workout would start earlier than the activity timer.
        if preferences.useHealthKitWorkouts {
            await workoutService.requestAuthorization(for: activityKind)
        }
        if preferences.navigationNotificationsEnabled {
            _ = await RouteNotificationService.requestAuthorizationIfNeeded()
        }
        guard phase == .idle || phase == .finished else { return }

        prepare(route: route, activityKind: activityKind)
        navigationEngine = RouteNavigationEngine(routePackage: route)
        navigationSnapshot = navigationEngine?.makeInitialSnapshot(routeId: route.id)
        recording = ActivityRecording(
            routeId: route.id,
            routeName: route.name,
            activityKind: activityKind,
            plannedRoutePoints: route.route
        )

        isWarmingUpGPS = false
        applyBatterySettings(from: preferences)

        if gpsAcquisitionState == .ready, let lastSample = locationService.lastSample {
            locationQualityFilter.reset(startingStabilized: true, seed: qualityInput(from: lastSample))
            previewCoordinate = GeoCoordinate(latitude: lastSample.coordinate.latitude, longitude: lastSample.coordinate.longitude)
        } else {
            locationQualityFilter.reset()
            previewCoordinate = nil
            gpsAcquisitionState = .acquiring
        }

        locationService.applyBatteryPolicy(currentBatteryPolicy)
        locationService.requestAuthorization()
        if !locationService.isTracking {
            locationService.startTracking(distanceFilterMeters: currentBatteryPolicy.distanceFilterMeters)
        }

        if preferences.useHealthKitWorkouts {
            await workoutService.startWorkout(activityKind: activityKind, startDate: recording.startedAt)
        }

        clock.start(at: recording.startedAt)
        startTimer()
        phase = .active
        preferredStartPage = currentBatteryPolicy.preferredStartPage
        publishWidgetState(forceTimelineReload: true)
        persistActivity()
    }

    private func prepare(route: RoutePackage, activityKind: ActivityKind) {
        routePackage = route
        self.activityKind = activityKind
        elevationProfile = RouteElevationProfile(route: route)
        clock = ActivityClock()
        elapsedSeconds = 0
        liveStats = LiveTrackStatistics()
        gpsDistanceMeters = 0
        elevationGainMeters = nil
        currentSpeedMetersPerSecond = nil
        speedEstimator.reset()
        alertTracker.reset()
        zoneAlertPolicy.reset()
        displayTrack = []
        rejoinGuidance = nil
        activeOffRouteEvent = nil
        lastError = nil
        displayCoordinateSmoother.reset()
        displayUpdateCoordinator.reset()
    }

    func pause() {
        guard phase == .active else { return }
        phase = .paused
        clock.pause()
        elapsedSeconds = clock.elapsed()
        currentSpeedMetersPerSecond = nil
        locationService.stopTracking()
        workoutService.pauseWorkout()
        publishWidgetState(forceTimelineReload: true)
        persistActivity()
    }

    func resume(preferences: WatchPreferences) {
        guard phase == .paused else { return }
        phase = .active
        clock.start()
        speedEstimator.reset()
        applyBatterySettings(from: preferences)
        locationService.startTracking(distanceFilterMeters: currentBatteryPolicy.distanceFilterMeters)
        gpsAcquisitionState = locationQualityFilter.hasStabilized ? .ready : .acquiring
        workoutService.resumeWorkout()
        publishWidgetState(forceTimelineReload: true)
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
        clock.pause()
        elapsedSeconds = clock.elapsed()
        locationService.stopTracking()
        workoutService.pauseWorkout()
        recording.elapsedSeconds = elapsedSeconds
        recording.averageHeartRateBPM = averageHeartRateBPM
        let zones = workoutService.zonesSoFar()
        if !zones.isEmpty {
            recording.workoutZones = zones
        }
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
        var finished = recording
        finished.endedAt = endDate
        finished.elapsedSeconds = elapsedSeconds
        finished.averageHeartRateBPM = averageHeartRateBPM
        finished.elevationGainMeters = elevationGainMeters
        finished.title = ActivityNaming.title(
            startedAt: finished.startedAt,
            activityKind: activityKind,
            routeName: finished.routeName
        )

        if workoutService.isSessionActive {
            let zones = await workoutService.finishWorkout(
                endDate: endDate,
                title: finished.displayTitle,
                activityId: finished.id,
                gpsDistanceMeters: gpsDistanceMeters
            )
            if !zones.isEmpty {
                finished.workoutZones = zones
            }
        }

        recording = finished
        let distance = gpsDistanceMeters
        tearDown(phase: .finished)

        try? await activityStore.save(finished)
        await RouteNotificationService.notifyActivityComplete(
            activityTitle: finished.displayTitle,
            distanceMeters: distance,
            elapsedSeconds: finished.elapsedSeconds
        )
        await connectivity.sendActivityRecording(finished)
    }

    func discardActivity() {
        if workoutService.isSessionActive {
            Task { await workoutService.discardWorkout() }
        }
        tearDown(phase: .idle)
    }

    private func tearDown(phase: Phase) {
        stopTimer()
        locationService.stopTracking()
        self.phase = phase
        routePackage = nil
        navigationEngine = nil
        navigationSnapshot = nil
        elevationProfile = nil
        displayTrack = []
        rejoinGuidance = nil
        previewCoordinate = nil
        gpsAcquisitionState = .idle
        isWarmingUpGPS = false
        currentSpeedMetersPerSecond = nil
        locationQualityFilter.reset()
        displayCoordinateSmoother.reset()
        displayUpdateCoordinator.reset()
        ActiveActivityPersistence.clear()
        WatchWidgetStateWriter.clear()
    }

    // MARK: - GPS warm-up

    func beginGPSWarmup(preferences: WatchPreferences, activityKind: ActivityKind, browseWarmup: Bool = true) {
        guard phase == .idle else { return }
        let policy = batteryPolicy(for: preferences)
        guard browseWarmup, policy.enablesBrowseWarmup else { return }

        warmupActivityKind = activityKind
        applyBatterySettings(from: preferences, browseWarmup: true)
        startWarmupTracking()
    }

    func beginImminentStartWarmup(preferences: WatchPreferences, activityKind: ActivityKind) {
        guard phase == .idle else { return }
        warmupActivityKind = activityKind
        applyBatterySettings(from: preferences)
        startWarmupTracking()
    }

    private func startWarmupTracking() {
        locationQualityFilter.reset()
        previewCoordinate = nil
        gpsAcquisitionState = .warmingUp
        isWarmingUpGPS = true
        locationService.applyBatteryPolicy(currentBatteryPolicy)
        locationService.requestAuthorization()
        if !locationService.isTracking {
            locationService.startTracking(distanceFilterMeters: currentBatteryPolicy.distanceFilterMeters)
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

    func applyBatterySettings(from preferences: WatchPreferences, browseWarmup: Bool = false) {
        let policy = batteryPolicy(for: preferences)
        currentBatteryPolicy = policy
        currentBatteryMode = policy.mode

        if browseWarmup, policy.usesReducedBrowseWarmup {
            locationService.applyBatteryPolicy(BatteryModePolicy(mode: .saver))
        } else if phase == .active || phase == .paused || isWarmingUpGPS {
            locationService.applyBatteryPolicy(policy)
            if locationService.isTracking {
                locationService.startTracking(distanceFilterMeters: policy.distanceFilterMeters)
            }
        }
    }

    func clearPreferredStartPage() {
        preferredStartPage = nil
    }

    // MARK: - Location updates

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
                gpsAcquisitionState = locationQualityFilter.isWarmupReady(input: input, activityKind: warmupActivityKind)
                    ? .ready
                    : .warmingUp
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
            applyPreviewNavigation(from: sample, route: route, engine: engine)
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

        let coordinate = GeoCoordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude)
        let smoothed = displayCoordinateSmoother.coordinate(
            raw: coordinate,
            projected: update.projectedCoordinate,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            isOffRoute: update.isOffRoute,
            recordingAccuracyThresholdMeters: currentBatteryMode.gpsRecordingAccuracyMeters
        )

        let point = TrackPoint(
            timestamp: sample.timestamp,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeMeters: sample.altitudeMeters,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            heartRateBPM: workoutService.heartRateBPM,
            snappedDistanceFromStartMeters: update.progressDistanceMeters,
            offRouteDistanceMeters: update.offRouteDistanceMeters
        )
        record(point, update: update)

        let previousTrackPoint = recording.trackPoints.dropLast().last
        if let speed = sample.speedMetersPerSecond {
            speedEstimator.add(speedMetersPerSecond: speed, at: sample.timestamp)
        } else if let previousTrackPoint {
            let dt = sample.timestamp.timeIntervalSince(previousTrackPoint.timestamp)
            if dt > 0 {
                speedEstimator.add(
                    speedMetersPerSecond: MapMath.haversineMeters(from: previousTrackPoint.coordinate, to: coordinate) / dt,
                    at: sample.timestamp
                )
            }
        }
        currentSpeedMetersPerSecond = speedEstimator.current(at: sample.timestamp)

        let snapshot = engine.makeSnapshot(
            routeId: route.id,
            coordinate: smoothed,
            speed: currentSpeedMetersPerSecond,
            update: update
        )
        navigationSnapshot = snapshot

        rejoinGuidance = update.isOffRoute
            ? RejoinGuidance(
                distanceMeters: update.offRouteDistanceMeters,
                bearingDegrees: MapMath.bearingDegrees(from: coordinate, to: update.projectedCoordinate),
                courseDegrees: courseDegrees
            )
            : nil

        updateOffRouteEvents(update: update, coordinate: coordinate)

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
            Task { await workoutService.insertRouteLocation(location) }
        }

        for alert in alertTracker.alerts(for: snapshot, activity: activityKind, speedMetersPerSecond: currentSpeedMetersPerSecond) {
            RouteNotificationService.deliver(alert)
        }

        publishWidgetState()
        persistActivityIfNeeded()
    }

    private func record(_ point: TrackPoint, update: RouteNavigationUpdate) {
        recording.trackPoints.append(point)
        liveStats.add(point)
        gpsDistanceMeters = liveStats.distanceMeters
        elevationGainMeters = liveStats.elevationGainMeters

        recording.totalDistanceMeters = update.progressDistanceMeters
        recording.elevationGainMeters = elevationGainMeters
        recording.elapsedSeconds = clock.elapsed()

        if let last = displayTrack.last,
           MapMath.haversineMeters(from: last, to: point.coordinate) < Self.displayTrackSpacingMeters {
            return
        }
        displayTrack.append(point.coordinate)
    }

    private func updateOffRouteEvents(update: RouteNavigationUpdate, coordinate: GeoCoordinate) {
        if update.isOffRoute {
            if let event = activeOffRouteEvent {
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
            } else {
                let event = OffRouteEvent(
                    startedAt: Date(),
                    maxDistanceMeters: update.offRouteDistanceMeters,
                    coordinate: coordinate
                )
                activeOffRouteEvent = event
                recording.offRouteEvents.append(event)
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

    // MARK: - Timer

    /// Drives the UI once per second; time itself comes from the wall-clock `ActivityClock`.
    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        elapsedSeconds = clock.elapsed(at: now)
        if phase == .active {
            recording.elapsedSeconds = elapsedSeconds
            currentSpeedMetersPerSecond = speedEstimator.current(at: now)
            publishWidgetState()
            checkZoneChange(at: now)
        }
    }

    private func checkZoneChange(at now: Date) {
        let change = zoneAlertPolicy.update(
            zoneIndex: workoutService.heartRateZoneIndex,
            at: now,
            canAlert: RouteNotificationService.isQuietForZoneAlert(at: now)
        )
        if let change {
            RouteNotificationService.deliverZoneChange(change)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Persistence & widget

    private func publishWidgetState(forceTimelineReload: Bool = false) {
        guard let route = routePackage, let snapshot = navigationSnapshot else { return }
        WatchWidgetStateWriter.write(
            WatchActivityWidgetPayload(
                routeName: route.name,
                progressFraction: progressFraction,
                distanceRemainingMeters: snapshot.distanceRemainingMeters,
                elapsedSeconds: elapsedSeconds,
                isPaused: phase != .active,
                isOffRoute: snapshot.isOffRoute,
                updatedAt: Date(),
                timerStartDate: phase == .active ? Date().addingTimeInterval(-elapsedSeconds) : nil
            ),
            minReloadInterval: currentBatteryPolicy.widgetReloadMinInterval,
            forceTimelineReload: forceTimelineReload
        )
    }

    private func persistActivityIfNeeded() {
        guard Date().timeIntervalSince(lastPersistenceAt) >= currentBatteryPolicy.persistenceMinInterval else { return }
        persistActivity()
    }

    /// Saves just enough to resume after the app is terminated. The planned route and the
    /// engine's copies of the track are rebuilt on restore instead of being re-encoded here.
    private func persistActivity() {
        guard let route = routePackage, let engine = navigationEngine else { return }
        let phaseKey: String
        switch phase {
        case .active: phaseKey = "active"
        case .paused: phaseKey = "paused"
        case .summary: phaseKey = "summary"
        default: return
        }

        var slim = recording
        slim.plannedRoutePoints = nil
        ActiveActivityPersistence.save(PersistedActiveActivity(
            phase: phaseKey,
            routeId: route.id,
            activityKind: activityKind,
            recording: slim,
            elapsedSeconds: clock.elapsed(),
            engineState: engine.exportState(includeTracks: false),
            clock: clock
        ))
        lastPersistenceAt = Date()
    }

    // MARK: - Helpers

    private func batteryPolicy(for preferences: WatchPreferences) -> BatteryModePolicy {
        BatteryModePolicy.policy(userMode: preferences.batteryMode)
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
        guard MapMath.isValidCoordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude) else { return }
        previewCoordinate = GeoCoordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude)
    }

    private func applyPreviewNavigation(from sample: LocationSample, route: RoutePackage, engine: RouteNavigationEngine) {
        guard let update = engine.previewUpdate(
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond
        ) else { return }

        let coordinate = GeoCoordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude)
        let smoothed = displayCoordinateSmoother.coordinate(
            raw: coordinate,
            projected: update.projectedCoordinate,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            isOffRoute: update.isOffRoute,
            recordingAccuracyThresholdMeters: currentBatteryMode.gpsRecordingAccuracyMeters
        )
        navigationSnapshot = engine.makeSnapshot(routeId: route.id, coordinate: smoothed, speed: nil, update: update)
    }

    private static func thinnedTrack(_ coordinates: [GeoCoordinate]) -> [GeoCoordinate] {
        var result: [GeoCoordinate] = []
        result.reserveCapacity(coordinates.count / 2)
        for coordinate in coordinates {
            if let last = result.last, MapMath.haversineMeters(from: last, to: coordinate) < displayTrackSpacingMeters {
                continue
            }
            result.append(coordinate)
        }
        return result
    }
}
