//
//  CGMServerViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import ContinuousGlucoseMonitorServiceKit

/// Measurement cadences offered to the tester (HYD-G-001); the same setting the collector changes with
/// Set CGM Communication Interval, so the two pickers mirror each other (Fastest = 5 s). Time Offset only has
/// one-minute resolution, so 5 s readings share an offset. Off stops periodic readings and notifications.
enum MeasurementIntervalOption: TimeInterval, CaseIterable, Hashable, CustomStringConvertible {
    case off = 0
    case fiveSeconds = 5
    case oneMinute = 60
    case fiveMinutes = 300

    var description: String {
        switch self {
        case .off: return "Off"
        case .fiveSeconds: return "5 s"
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        }
    }
}

/// Spans of unattended running a tester can add to the record database in one tap.
enum BackfillDurationOption: TimeInterval, CaseIterable, Hashable, CustomStringConvertible {
    case fifteenMinutes = 900
    case oneHour = 3600
    case threeHours = 10800
    case eightHours = 28800
    case oneDay = 86400

    var description: String {
        switch self {
        case .fifteenMinutes: return "15 min"
        case .oneHour: return "1 h"
        case .threeHours: return "3 h"
        case .eightHours: return "8 h"
        case .oneDay: return "24 h"
        }
    }
}

/// Records packed into one CGM Measurement notification during an RACP report. Eight of the largest
/// record (15 octets) stays under any ATT MTU a collector negotiates; Core Bluetooth truncates oversize notifications.
enum RecordsPerNotificationOption: Int, CaseIterable, Hashable, CustomStringConvertible {
    case one = 1
    case two = 2
    case four = 4
    case eight = 8

    var description: String { String(rawValue) }
}

/// One point of the HUD sparkline: a stored reading by Time Offset. NaN glucose (impaired sensor) is skipped by the chart.
struct CGMReadingPoint: Identifiable, Hashable {
    /// Position in the record store. Time Offset has one-minute resolution, so at the 5 s cadence a dozen
    /// readings share one offset and it cannot serve as the identity.
    let id: Int
    let timeOffset: Int
    let glucose: Double
}

/// Warm-up after Start Session before readings begin (TBD-03: default 1 min, adjustable while in progress).
enum WarmupDurationOption: TimeInterval, CaseIterable, Hashable, CustomStringConvertible {
    case off = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case twoHours = 7200

    var description: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .twoHours: return "2 h"
        }
    }
}

/// How often the sensor asks the collector for a calibration (CGMS §3.7.2.2 Next Calibration Time).
enum CalibrationScheduleOption: CaseIterable, Hashable, CustomStringConvertible {
    case never
    case oncePerSession
    case tenMinutes
    case daily
    case immediately

    var schedule: CGMCalibrationSchedule {
        switch self {
        case .never: return .never
        case .oncePerSession: return .oncePerSession
        case .tenMinutes: return .every(minutes: 10)
        case .daily: return .every(minutes: 1440)
        case .immediately: return .immediately
        }
    }

    init?(schedule: CGMCalibrationSchedule) {
        guard let option = Self.allCases.first(where: { $0.schedule == schedule }) else { return nil }
        self = option
    }

    var description: String {
        switch self {
        case .never: return "Never"
        case .oncePerSession: return "Once"
        case .tenMinutes: return "10 min"
        case .daily: return "24 h"
        case .immediately: return "Now"
        }
    }
}

/// What drives the simulated glucose values.
enum GlucoseSourceOption: Hashable, CustomStringConvertible {
    case sineWave
    case constant
    case scenario(name: String)

    var description: String {
        switch self {
        case .sineWave: return "Sine Wave"
        case .constant: return "Constant"
        case .scenario(let name): return name
        }
    }
}

/// One-shot corruption of the next CGMS payload (HYD-C-009); `none` once the sensor has used it.
enum IntegrityFaultOption: CaseIterable, Hashable, CustomStringConvertible {
    case none, omitCRC, corruptCRC, truncate

    init(fault: CGMIntegrityFault?) {
        switch fault {
        case nil: self = .none
        case .omitCRC: self = .omitCRC
        case .corruptCRC: self = .corruptCRC
        case .truncate: self = .truncate
        }
    }

    var fault: CGMIntegrityFault? {
        switch self {
        case .none: return nil
        case .omitCRC: return .omitCRC
        case .corruptCRC: return .corruptCRC
        case .truncate: return .truncate
        }
    }

    var description: String { fault?.description ?? "None" }
}

@Observable
class CGMServerViewModel {

    @ObservationIgnored private var server: GATTServer?
    @ObservationIgnored private var sensor: MockCGMSensor?

    var numberOfSubscribedDevices: Int = 0
    var procedureAlreadyInProgress = false {
        didSet { if oldValue != procedureAlreadyInProgress { stimulus("Procedure Already In Progress → \(procedureAlreadyInProgress ? "on" : "off")") } }
    }
    var outOfRangeSchedule = false {
        didSet { if oldValue != outOfRangeSchedule { stimulus("Out of Range Schedule → \(outOfRangeSchedule ? "on" : "off")") } }
    }
    /// Armed here, consumed by the sensor's next CGMS payload; the mirror drops back to `none` with it.
    var integrityFault: IntegrityFaultOption = .none {
        didSet {
            guard oldValue != integrityFault else { return }
            if integrityFault != .none { stimulus("Next Payload Fault armed: \(integrityFault)") }
            if let sensor {
                sensor.pendingIntegrityFault = integrityFault.fault
            } else {
                preservedIntegrityFault = integrityFault.fault   // armed while powered off: the next start carries it
            }
        }
    }
    var lastInjectedFaultString: String = "none"

    var isSensorPoweredOn = true {
        didSet {
            guard oldValue != isSensorPoweredOn else { return }
            stimulus("Power On Sensor → \(isSensorPoweredOn ? "on" : "off")")
            if isSensorPoweredOn {
                startServer()
            } else {
                stopServer()
            }
        }
    }

    /// Characteristic permissions are fixed at creation, so flipping this recreates the server. Off by default:
    /// a bond is not needed for testing, and ACS will provide the application-layer channel.
    var requiresEncryption = false {
        didSet {
            guard oldValue != requiresEncryption else { return }
            stimulus("Require Encrypted Link → \(requiresEncryption ? "on" : "off")")
            if server != nil { restart() }
        }
    }

    /// ACS gate: when on, the CGM characteristics are protected resources and the collector must complete
    /// the key exchange and use AC Data In / Out. Flips live on the sensor; survives a restart.
    var isAuthorizationControlEnabled = false {
        didSet {
            guard oldValue != isAuthorizationControlEnabled else { return }
            stimulus("Authorization Control → \(isAuthorizationControlEnabled ? "on" : "off")")
            sensor?.isAuthorizationControlEnabled = isAuthorizationControlEnabled
        }
    }
    var isSecurityEstablished = false
    var oobRandomNumberString: String = ""

    var measurementInterval: MeasurementIntervalOption = .fiveMinutes {
        didSet {
            guard oldValue != measurementInterval else { return }
            stimulus("Communication Interval → \(measurementInterval)")
            applyMeasurementInterval(to: sensor)
        }
    }

    /// True while the sensor's state is being mirrored into these properties (delegate updates, stop), so the
    /// didSet handlers do not log a collector's write or a teardown reset as something the tester did.
    @ObservationIgnored private var isMirroring = false

    private func stimulus(_ detail: String) {
        guard !isMirroring else { return }
        SessionLog.shared.stimulus(detail)
    }

    // Record database (CGMS §3.6): what the collector can backfill through RACP.
    var storedRecordCount: Int = 0
    var recordCapacityEntry: String = String(CGMRecordStore.defaultCapacity)
    /// Applies at once; while powered off the next start picks it up.
    var recordsPerNotification: RecordsPerNotificationOption = .eight {
        didSet {
            guard oldValue != recordsPerNotification else { return }
            sensor?.recordsPerNotification = recordsPerNotification.rawValue
        }
    }
    var recordSettingsMessage: String? = nil
    var backfillDuration: BackfillDurationOption = .oneHour

    // CGM Specific Ops state (CGMS §3.7): set by the collector, mirrored here so a tester can confirm it landed.
    /// The sensor's cadence when a collector wrote an interval the picker cannot show (e.g. 10 min).
    var measurementIntervalNote: String? = nil
    var alertLevels = CGMAlertLevels()
    var alertStatusString: String = "none"
    var calibrationCount: Int = 0
    var lastCalibrationString: String = "none"
    /// Applies at once; while powered off the next start picks it up.
    var calibrationSchedule: CalibrationScheduleOption = .oncePerSession {
        didSet {
            guard oldValue != calibrationSchedule else { return }
            sensor?.calibrationSchedule = calibrationSchedule.schedule
        }
    }
    var calibrationStatusString: String = "none"
    var specificOpsMessage: String? = nil

    // Lifecycle (CGM-DESIGN §Lifecycle)
    /// Applies at once, including mid warm-up; while powered off the next start picks it up.
    var warmupDuration: WarmupDurationOption = .oneMinute {
        didSet {
            guard oldValue != warmupDuration else { return }
            sensor?.warmupDuration = warmupDuration.rawValue
        }
    }
    var warmupEndDate: Date?
    /// The sensor's physical condition; nil while powered off. The strings and flags below derive from it.
    var condition: CGMSensorCondition? = nil
    var conditionString: String { condition.map { String(describing: $0) } ?? "" }
    var isImpaired: Bool { condition == .impaired }
    var isFailed: Bool { condition == .failed }
    var sensorRangeLowEntry: String = "40"
    var sensorRangeHighEntry: String = "400"
    var lifecycleMessage: String? = nil
    /// Newest first, for the Lifecycle card.
    var lifecycleEventStrings: [String] = []

    // HUD page (CGMSensorHUDView): the latest reading in numbers, the recent trace, and the status bits by name.
    var lastGlucose: Double? = nil
    var lastTrend: Double? = nil
    var isSessionRunning = false
    var timeOffsetMinutes = 0
    /// Stored readings from the last hour of session time, for the HUD chart's fixed 60 min window.
    var recentReadings: [CGMReadingPoint] = []
    static let chartWindowMinutes = 60
    var activeStatusBitNames: [String] = []

    // Mirrors of sensor state for display
    var sessionStateString: String = ""
    var sessionStartTimeString: String = ""
    var timeOffsetString: String = ""
    var sessionRunTimeString: String = ""
    var sensorStatusString: String = ""
    var lastGlucoseString: String = ""
    var measurementCount: Int = 0
    var nextMeasurementDate: Date?
    var featureFlags: CGMFeatureFlags = []
    var manualSensorStatus: CGMSensorStatusAnnunciation = []

    // Glucose source. Picking a source applies it at once (the checkmark is the active source); the numeric
    // entries are text so the tester can type freely and are applied with the Apply Parameters button.
    /// The bundled trace the sensor plays until the tester picks something else (Nate, 2026-10-15).
    static let defaultScenarioName = "Normal Trace"

    var glucoseSource: GlucoseSourceOption = .scenario(name: CGMServerViewModel.defaultScenarioName) {
        didSet {
            guard oldValue != glucoseSource, !isSyncingGlucoseSource else { return }
            applyGlucoseSource()
        }
    }
    @ObservationIgnored private var isSyncingGlucoseSource = false
    var sineStartEntry: String = "120"
    var sineAmplitudeEntry: String = "40"
    var sinePeriodMinutesEntry: String = "360"
    var constantEntry: String = "120"
    var glucoseSourceMessage: String? = nil

    // Trace effects (CGM-DESIGN §Glucose trace, HYD-C-018): entries are text, applied with Apply Effects.
    var traceEffects: CGMTraceEffects = .none
    var noiseEntry: String = "0"
    var outlierChanceEntry: String = "0"
    var outlierSizeEntry: String = "60"
    var failedReadingChanceEntry: String = "0"
    var effectsSeedEntry: String = "1"
    var traceEffectsMessage: String? = nil

    // Sensor clock skew (HYD-C-015/016): Session Start Time is written as host clock plus this, in minutes on screen.
    var clockOffset: TimeInterval = 0
    var clockOffsetMinutesEntry: String = "0"
    var clockOffsetMessage: String? = nil
    let scenarios: [CGMGlucoseScenario] = CGMScenarioLibrary.bundled

    var glucoseSourceOptions: [GlucoseSourceOption] {
        [.sineWave, .constant] + scenarios.map { .scenario(name: $0.name) }
    }

    /// Text field contents; only reset when the server starts or the value is applied, never by refreshes.
    var sessionRunTimeHoursEntry: String = "240"

    // Tester settings survive a restart (power cycle, encryption toggle).
    @ObservationIgnored private var preservedFeature: CGMFeature = .simulatorDefault
    @ObservationIgnored private var preservedManualStatus: CGMSensorStatusAnnunciation = []
    @ObservationIgnored private var preservedRunTime = CGMSessionRunTime(hours: 240)
    @ObservationIgnored private var preservedTrace: CGMGlucoseTrace = CGMScenarioLibrary.bundled
        .first { $0.name == CGMServerViewModel.defaultScenarioName }
        .map(CGMGlucoseTrace.scenario) ?? .simulatorDefault
    @ObservationIgnored private var preservedRecordCapacity = CGMRecordStore.defaultCapacity
    @ObservationIgnored private var preservedAlertLevels = CGMAlertLevels()
    @ObservationIgnored private var preservedSensorRange: ClosedRange<Double> = 40...400
    @ObservationIgnored private var preservedTraceEffects: CGMTraceEffects = .none
    @ObservationIgnored private var preservedClockOffset: TimeInterval = 0
    @ObservationIgnored private var preservedIntegrityFault: CGMIntegrityFault? = nil

    @ObservationIgnored private var serverName: String?
    @ObservationIgnored private var refreshTimer: Timer?

    func startServer(serverName: String? = nil) {
        if server != nil {
            stopServer()
        }
        // Before the GATT server exists, so its first console lines already carry the mode; the glucose
        // source is filled in once the sensor is built.
        SessionLog.shared.context = SessionLog.Context(mode: .cgm, role: .server)
        // nil keeps the current name (restart); an empty string falls back to the CGM default.
        if let serverName {
            self.serverName = serverName.isEmpty ? nil : serverName
        }
        
        let server = GATTServer(
            advertisedName: self.serverName ?? CGMConstants.serverName,
            advertisedServices: [CGMCharacteristicUUID.service.cbUUID, ACCharacteristicUUID.service.cbUUID]
        )
        self.server = server
        server.delegate = self

        let messageQueue = MessageQueue(gattService: server)
        let sensor = MockCGMSensor(
            gattServer: server,
            messageQueue: messageQueue,
            requiresEncryption: requiresEncryption,
            feature: preservedFeature
        )
        sensor.manualSensorStatus = preservedManualStatus
        sensor.sessionRunTime = preservedRunTime
        applyMeasurementInterval(to: sensor)
        sensor.trace = preservedTrace
        sensor.isAuthorizationControlEnabled = isAuthorizationControlEnabled
        sensor.recordStore.capacity = preservedRecordCapacity
        sensor.recordsPerNotification = recordsPerNotification.rawValue
        sensor.alertLevels = preservedAlertLevels
        sensor.calibrationSchedule = calibrationSchedule.schedule
        sensor.warmupDuration = warmupDuration.rawValue
        sensor.sensorRange = preservedSensorRange
        sensor.traceEffects = preservedTraceEffects
        sensor.clockOffset = preservedClockOffset
        sensor.pendingIntegrityFault = preservedIntegrityFault   // a fault armed while powered off or across a restart
        preservedIntegrityFault = nil
        sensor.delegate = self
        self.sensor = sensor
        mockSensorDidUpdate(sensor)
        sessionRunTimeHoursEntry = String(sensor.sessionRunTime.hours)
        syncGlucoseSourceEntries(from: sensor.trace)
        syncSensorRangeEntries(from: sensor)
        syncTraceEffectsEntries(from: sensor.traceEffects)
        syncClockOffsetEntry(from: sensor.clockOffset)
        SessionLog.shared.context = logContext(for: sensor)
        SessionLog.shared.log(.lifecycle, "CGM server started, advertising \(self.serverName ?? CGMConstants.serverName)")

        // Time Offset is clock-derived, so refresh the display once a minute. Common modes keep it ticking
        // while the tester scrolls.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let sensor = self.sensor else { return }
            self.mockSensorDidUpdate(sensor)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stopServer() {
        // Resets below are teardown, not tester actions; the context stays until the last kit line is out.
        isMirroring = true
        defer {
            isMirroring = false
            SessionLog.shared.context = SessionLog.Context()
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let sensor {
            SessionLog.shared.log(.lifecycle, "CGM server stopped")
            preservedIntegrityFault = sensor.pendingIntegrityFault
            preservedFeature = sensor.feature
            preservedManualStatus = sensor.manualSensorStatus
            preservedRunTime = sensor.sessionRunTime
            preservedTrace = sensor.trace
            preservedRecordCapacity = sensor.recordStore.capacity
            preservedAlertLevels = sensor.alertLevels
            preservedSensorRange = sensor.sensorRange
            preservedTraceEffects = sensor.traceEffects
            preservedClockOffset = sensor.clockOffset
        }
        server?.disconnect()
        server = nil
        sensor = nil
        numberOfSubscribedDevices = 0
        procedureAlreadyInProgress = false
        outOfRangeSchedule = false
        sessionStateString = ""
        warmupEndDate = nil
        condition = nil
        lifecycleEventStrings = []
        sessionStartTimeString = ""
        timeOffsetString = ""
        sessionRunTimeString = ""
        sensorStatusString = ""
        lastGlucoseString = ""
        lastGlucose = nil
        lastTrend = nil
        isSessionRunning = false
        timeOffsetMinutes = 0
        recentReadings = []
        activeStatusBitNames = []
        measurementCount = 0
        nextMeasurementDate = nil
        isSecurityEstablished = false
        storedRecordCount = 0
        measurementIntervalNote = nil
        alertStatusString = "none"
        calibrationCount = 0
        lastCalibrationString = "none"
        calibrationStatusString = "none"
    }

    /// Mode, role and the glucose source the log stamps on every line while this server runs (HYD-O-003).
    private func logContext(for sensor: MockCGMSensor) -> SessionLog.Context {
        let scenario: String
        switch sensor.trace {
        case .scenario(let traceScenario):
            scenario = traceScenario.name
        case .constant(let mgdl):
            scenario = "Constant \(mgdl.compactDescription) mg/dL"
        case let .sineCurve(base, amplitude, period):
            scenario = "Sine \(base.compactDescription) ± \(amplitude.compactDescription) mg/dL over \((period / 60).compactDescription) min"
        }
        let effects = sensor.traceEffects
        return SessionLog.Context(mode: .cgm, role: .server, scenario: scenario,
                                  scenarioVersion: effects.isActive ? "effects seed \(effects.seed)" : nil)
    }

    // MARK: - CGM Specific Ops

    /// Forgets the stored calibrations so a Get answers the record 0 placeholder again.
    func clearCalibrations() {
        stimulus("Clear Calibrations")
        sensor?.calibrationStore.removeAll()
    }

    /// Puts the alert levels back to the sensor defaults, e.g. after a tester drove them somewhere odd.
    func resetAlertLevels() {
        stimulus("Reset Alert Levels")
        if let sensor {
            sensor.alertLevels = CGMAlertLevels()
        } else {
            preservedAlertLevels = CGMAlertLevels()
            alertLevels = preservedAlertLevels
        }
    }

    /// Off stops the periodic readings; any other option sets the cadence and makes sure they run.
    private func applyMeasurementInterval(to sensor: MockCGMSensor?) {
        guard let sensor else { return }
        if measurementInterval == .off {
            sensor.isPeriodicCommunicationEnabled = false
        } else {
            sensor.measurementInterval = measurementInterval.rawValue
            sensor.isPeriodicCommunicationEnabled = true
        }
    }

    /// Moves the picker to the sensor's cadence when it is one of the options (a collector can set any
    /// whole number of minutes); otherwise the actual value is shown as a note.
    private func syncMeasurementInterval(from sensor: MockCGMSensor) {
        if !sensor.isPeriodicCommunicationEnabled {
            measurementInterval = .off
            measurementIntervalNote = nil
        } else if let option = MeasurementIntervalOption(rawValue: sensor.measurementInterval) {
            measurementInterval = option
            measurementIntervalNote = nil
        } else {
            measurementIntervalNote = "\(sensor.communicationInterval) min (written by collector)"
        }
    }

    // MARK: - Record database

    /// Applies the capacity entry; a bad entry is reported, not applied.
    func applyRecordSettings() {
        guard let sensor else { return }
        guard let capacity = Int(recordCapacityEntry), capacity >= 1 else {
            recordSettingsMessage = "Capacity must be a whole number of at least 1"
            return
        }
        sensor.recordStore.capacity = capacity
        recordSettingsMessage = nil
        stimulus("Record capacity → \(capacity)")
        mockSensorDidUpdate(sensor)
    }

    /// Empties the database without touching the session, so a tester can re-run a backfill from scratch.
    func clearRecords() {
        stimulus("Clear Records")
        sensor?.recordStore.removeAll()
    }

    /// Adds the selected span of history from the active glucose source, as if the collector had been away.
    func backfill() {
        guard let sensor else { return }
        guard sensor.sessionState == .running else {
            recordSettingsMessage = "Start a session before backfilling"
            return
        }
        let added = sensor.backfill(duration: backfillDuration.rawValue)
        stimulus("Backfill \(backfillDuration): \(added) records added")
        recordSettingsMessage = added > 0
            ? "Added \(added) records covering the last \(backfillDuration); time offset is now \(sensor.timeOffset) min"
            : "Nothing added: the measurement interval is longer than \(backfillDuration)"
        mockSensorDidUpdate(sensor)
    }

    /// Recreates the server only when the sensor is meant to be on; otherwise the radio stays silent.
    func restartServer() {
        stimulus("Restart Server")
        restart()
    }

    /// Recreates the server only when the sensor is meant to be on; otherwise the radio stays silent.
    private func restart() {
        stopServer()
        if isSensorPoweredOn {
            startServer()
        }
    }

    // MARK: - Session and measurements

    func startSession() {
        stimulus("Start Session")
        sensor?.startSession()
    }

    func stopSession() {
        stimulus("Stop Session")
        sensor?.stopSession()
    }

    func takeMeasurement() {
        stimulus("Measure Now")
        sensor?.takeMeasurement()
    }

    // MARK: - Lifecycle

    func replaceSensor() {
        stimulus("Replace Sensor")
        sensor?.replaceSensor()
    }

    func failSensor() {
        stimulus("Fail Sensor")
        sensor?.failSensor()
    }

    /// One button: begins a temporary issue, or resolves the one in progress.
    func toggleTemporaryIssue() {
        guard let sensor else { return }
        if sensor.condition == .impaired {
            stimulus("Resolve Issue")
            sensor.resolveTemporaryIssue()
        } else {
            stimulus("Temporary Issue")
            sensor.beginTemporaryIssue()
        }
    }

    /// Applies the sensor range entries (HYD-G-003); a bad entry is reported, not applied.
    func applySensorRange() {
        guard let low = sensorRangeLowEntry.parsedDouble, let high = sensorRangeHighEntry.parsedDouble, low.isFinite, high.isFinite, low < high else {
            lifecycleMessage = "Sensor range needs numeric low < high"
            return
        }
        lifecycleMessage = nil
        stimulus("Sensor range → \(low.compactDescription)…\(high.compactDescription) mg/dL")
        if let sensor {
            sensor.sensorRange = low...high
        } else {
            preservedSensorRange = low...high
        }
    }

    /// The entries show the range the sensor is actually using, so unapplied typing does not survive a restart.
    private func syncSensorRangeEntries(from sensor: MockCGMSensor) {
        sensorRangeLowEntry = sensor.sensorRange.lowerBound.compactDescription
        sensorRangeHighEntry = sensor.sensorRange.upperBound.compactDescription
    }

    // MARK: - Trace effects

    /// Applies the effect entries (percentages on screen, probabilities on the sensor); a bad entry is reported.
    func applyTraceEffects() {
        guard let noise = noiseEntry.parsedDouble, let outlierPercent = outlierChanceEntry.parsedDouble,
              let outlierSize = outlierSizeEntry.parsedDouble, let failedPercent = failedReadingChanceEntry.parsedDouble,
              let seed = UInt64(effectsSeedEntry.trimmingCharacters(in: .whitespaces)),
              noise.isFinite, noise >= 0, outlierSize.isFinite, outlierSize >= 0,
              (0...100).contains(outlierPercent), (0...100).contains(failedPercent)
        else {
            traceEffectsMessage = "Effects need noise ≥ 0, chances 0–100 %, outlier size ≥ 0 and a whole-number seed"
            return
        }
        traceEffectsMessage = nil
        let effects = CGMTraceEffects(noiseStandardDeviation: noise, outlierProbability: outlierPercent / 100, outlierMagnitude: outlierSize, errorProbability: failedPercent / 100, seed: seed)
        stimulus("Apply Effects: noise σ \(Self.format(noise)), outliers \(Self.format(outlierPercent)) % ±\(Self.format(outlierSize)), failed readings \(Self.format(failedPercent)) %, seed \(seed)")
        if let sensor {
            sensor.traceEffects = effects
        } else {
            preservedTraceEffects = effects
            traceEffects = effects   // the summary row shows what the next start will apply
        }
    }

    private func syncTraceEffectsEntries(from effects: CGMTraceEffects) {
        noiseEntry = Self.format(effects.noiseStandardDeviation)
        outlierChanceEntry = Self.percent(effects.outlierProbability)
        outlierSizeEntry = Self.format(effects.outlierMagnitude)
        failedReadingChanceEntry = Self.percent(effects.errorProbability)
        effectsSeedEntry = String(effects.seed)
        traceEffectsMessage = nil
    }

    /// A probability as a percentage with at most one decimal, so 0.07 reads "7" and not "7.000000000000001".
    private static func percent(_ probability: Double) -> String {
        format((probability * 1000).rounded() / 10)
    }

    /// One line for the Glucose Source card: what the sensor is applying right now.
    var traceEffectsSummary: String {
        guard traceEffects.isActive else { return "off" }
        var parts: [String] = []
        if traceEffects.noiseStandardDeviation > 0 { parts.append("noise σ \(Self.format(traceEffects.noiseStandardDeviation))") }
        if traceEffects.outlierProbability > 0 { parts.append("outliers \(Self.percent(traceEffects.outlierProbability)) % ±\(Self.format(traceEffects.outlierMagnitude))") }
        if traceEffects.errorProbability > 0 { parts.append("failed readings \(Self.percent(traceEffects.errorProbability)) %") }
        return parts.joined(separator: ", ") + ", seed \(traceEffects.seed)"
    }

    // MARK: - Device clock

    /// Applies the clock skew entry in minutes (negative allowed); the sensor uses it at the next Start Session.
    func applyClockOffset() {
        guard let minutes = clockOffsetMinutesEntry.parsedDouble, minutes.isFinite, abs(minutes) <= 7 * 24 * 60 else {
            clockOffsetMessage = "Clock offset needs a number of minutes within ±7 days"
            return
        }
        clockOffsetMessage = nil
        stimulus("Clock Skew → \(Self.format(minutes)) min (next session)")
        if let sensor {
            sensor.clockOffset = minutes * 60
        } else {
            preservedClockOffset = minutes * 60
            clockOffset = minutes * 60
        }
    }

    private func syncClockOffsetEntry(from offset: TimeInterval) {
        clockOffsetMinutesEntry = Self.format(offset / 60)
        clockOffsetMessage = nil
    }

    func applySessionRunTime() {
        guard let sensor else { return }
        guard let hours = UInt16(sessionRunTimeHoursEntry) else {
            sessionRunTimeHoursEntry = String(sensor.sessionRunTime.hours)
            return
        }
        sensor.sessionRunTime = CGMSessionRunTime(hours: hours)
        stimulus("Session Run Time → \(hours) h")
    }

    // MARK: - Glucose source

    /// Builds the trace from the selected source and its entries and hands it to the sensor; takes effect at
    /// the next sample. Only validation problems produce a message.
    func applyGlucoseSource() {
        guard let sensor else { return }
        switch glucoseSource {
        case .sineWave:
            guard let start = sineStartEntry.parsedDouble, let amplitude = sineAmplitudeEntry.parsedDouble,
                  let minutes = sinePeriodMinutesEntry.parsedDouble, minutes > 0
            else {
                glucoseSourceMessage = "Sine wave needs numeric start, amplitude and a period above 0 minutes"
                return
            }
            sensor.trace = .sineCurve(base: start, amplitude: amplitude, period: minutes * 60)
        case .constant:
            guard let mgdl = constantEntry.parsedDouble else {
                glucoseSourceMessage = "Constant needs a numeric mg/dL value"
                return
            }
            sensor.trace = .constant(mgdl: mgdl)
        case .scenario(let name):
            guard let scenario = scenarios.first(where: { $0.name == name }) else {
                glucoseSourceMessage = "Scenario \(name) is not bundled"
                return
            }
            sensor.trace = .scenario(scenario)
        }
        glucoseSourceMessage = nil
        stimulus("Glucose Source → \(glucoseSource)")
    }

    /// Scenario details for the selected scenario, shown under the picker.
    var selectedScenarioSummary: String? {
        guard case .scenario(let name) = glucoseSource,
              let scenario = scenarios.first(where: { $0.name == name })
        else { return nil }
        return "\(scenario.values.count) values recorded \(Self.format(scenario.sampleInterval / 60)) min apart, one per measurement, \(scenario.repeats ? "repeats at the end" : "holds the last value")"
    }

    /// Reflects the sensor's trace in the picker and entries without re-applying it.
    private func syncGlucoseSourceEntries(from trace: CGMGlucoseTrace) {
        isSyncingGlucoseSource = true
        defer { isSyncingGlucoseSource = false }
        switch trace {
        case let .sineCurve(base, amplitude, period):
            glucoseSource = .sineWave
            sineStartEntry = Self.format(base)
            sineAmplitudeEntry = Self.format(amplitude)
            sinePeriodMinutesEntry = Self.format(period / 60)
        case .constant(let mgdl):
            glucoseSource = .constant
            constantEntry = Self.format(mgdl)
        case .scenario(let scenario):
            glucoseSource = .scenario(name: scenario.name)
        }
        glucoseSourceMessage = nil
    }

    private static func format(_ value: Double) -> String {
        value.compactDescription
    }

    // MARK: - Feature and status bits

    func isFeatureEnabled(_ flag: CGMFeatureFlags) -> Bool {
        featureFlags.contains(flag)
    }

    /// While the sensor is powered off the toggles edit the preserved value, which the next start applies.
    func setFeature(_ flag: CGMFeatureFlags, enabled: Bool) {
        stimulus("Feature \(CGMFeatureFlags.named.first { $0.flag == flag }?.name ?? "\(flag.rawValue)") → \(enabled ? "on" : "off")")
        if let sensor {
            if enabled {
                sensor.feature.flags.insert(flag)
            } else {
                sensor.feature.flags.remove(flag)
            }
        } else {
            if enabled {
                preservedFeature.flags.insert(flag)
            } else {
                preservedFeature.flags.remove(flag)
            }
            featureFlags = preservedFeature.flags
        }
    }

    func isStatusBitSet(_ bit: CGMSensorStatusAnnunciation) -> Bool {
        manualSensorStatus.contains(bit)
    }

    func setStatusBit(_ bit: CGMSensorStatusAnnunciation, enabled: Bool) {
        stimulus("Status bit \(CGMSensorStatusAnnunciation.named.first { $0.flag == bit }?.name ?? "\(bit.rawValue)") → \(enabled ? "on" : "off")")
        if let sensor {
            if enabled {
                sensor.manualSensorStatus.insert(bit)
            } else {
                sensor.manualSensorStatus.remove(bit)
            }
        } else {
            if enabled {
                preservedManualStatus.insert(bit)
            } else {
                preservedManualStatus.remove(bit)
            }
            manualSensorStatus = preservedManualStatus
        }
    }

    /// Tester-settable annunciation bits; only the session-stopped bit is derived by the sensor.
    static let manualStatusBits: [(flag: CGMSensorStatusAnnunciation, name: String)] = CGMSensorStatusAnnunciation.named.filter {
        $0.flag != .sessionStopped
    }
}

// MARK: - GATT Service Delegate

extension CGMServerViewModel: GATTServiceDelegate {
    func centralDidSubscribe(characteristicUUID: CBUUID) {
        numberOfSubscribedDevices = server?.subscribedCentrals.count ?? 0
        SessionLog.shared.log(.connection, "central subscribed to \(characteristicUUID.uuidString) (\(numberOfSubscribedDevices) subscribed)")
    }

    func centralDidUnsubscribe(characteristicUUID: CBUUID) {
        numberOfSubscribedDevices = server?.subscribedCentrals.count ?? 0
        SessionLog.shared.log(.connection, "central unsubscribed from \(characteristicUUID.uuidString) (\(numberOfSubscribedDevices) subscribed)")
    }

    func isProcedureAlreadyInProgress() -> Bool {
        procedureAlreadyInProgress
    }

    func isOutOfRange() -> Bool {
        outOfRangeSchedule
    }
}

// MARK: - Mock Sensor Delegate

extension CGMServerViewModel: MockCGMSensorDelegate {
    func mockSensorDidUpdate(_ sensor: MockCGMSensor) {
        isMirroring = true
        defer { isMirroring = false }
        let context = logContext(for: sensor)
        if SessionLog.shared.context != context { SessionLog.shared.context = context }
        sessionStateString = sensor.isWarmingUp ? "running (warming up)" : String(describing: sensor.sessionState)
        warmupEndDate = sensor.warmupEndDate
        if let option = WarmupDurationOption(rawValue: sensor.warmupDuration) {
            warmupDuration = option
        }
        condition = sensor.condition
        traceEffects = sensor.traceEffects
        clockOffset = sensor.clockOffset
        integrityFault = IntegrityFaultOption(fault: sensor.pendingIntegrityFault)
        lastInjectedFaultString = sensor.lastInjectedFault.map { injected in
            "\(injected.fault) on \(injected.characteristic.name) at \(injected.date.formatted(date: .omitted, time: .standard))\(injected.applied ? "" : " (no CRC to corrupt, sent intact)")"
        } ?? "none"
        lifecycleEventStrings = sensor.lifecycleEvents.suffix(20).reversed().map { String(describing: $0) }
        if let startTime = sensor.sessionStartTime {
            sessionStartTimeString = "\(startTime)\(sensor.sessionStartTimeSetByCollector ? " (written by collector)" : "")"
        } else {
            sessionStartTimeString = "session not started"
        }
        timeOffsetString = "\(sensor.timeOffset) min"
        sessionRunTimeString = String(describing: sensor.sessionRunTime)
        sensorStatusString = String(describing: sensor.sensorStatus)
        lastGlucoseString = sensor.lastMeasurement.map { String(describing: $0) } ?? "no measurement yet"
        lastGlucose = sensor.lastMeasurement?.glucoseConcentration
        lastTrend = sensor.lastMeasurement?.trend
        isSessionRunning = sensor.sessionState == .running
        timeOffsetMinutes = Int(sensor.timeOffset)
        // Records are chronological, so the window is a suffix: walk back from the newest and stop at the
        // first record older than the window rather than scanning the whole store on every update.
        let windowStart = timeOffsetMinutes - Self.chartWindowMinutes
        let records = sensor.recordStore.records
        let windowIndices = records.indices.reversed().prefix { Int(records[$0].timeOffset) >= windowStart }
        recentReadings = windowIndices.reversed().map { index in
            CGMReadingPoint(id: index, timeOffset: Int(records[index].timeOffset), glucose: records[index].glucoseConcentration)
        }
        activeStatusBitNames = CGMSensorStatusAnnunciation.named.filter { sensor.sensorStatus.contains($0.flag) }.map(\.name)
        measurementCount = sensor.measurementCount
        nextMeasurementDate = sensor.nextMeasurementDate
        featureFlags = sensor.feature.flags
        manualSensorStatus = sensor.manualSensorStatus
        syncMeasurementInterval(from: sensor)
        storedRecordCount = sensor.recordStore.count
        alertLevels = sensor.alertLevels
        alertStatusString = sensor.alertStatus.isEmpty ? "none" : String(describing: sensor.alertStatus)
        calibrationCount = sensor.calibrationStore.count
        lastCalibrationString = sensor.calibrationStore.last.map { String(describing: $0) } ?? "none"
        calibrationStatusString = sensor.calibrationStatus.isEmpty ? "none" : String(describing: sensor.calibrationStatus)
        if let option = CalibrationScheduleOption(schedule: sensor.calibrationSchedule) {
            calibrationSchedule = option
        }
        isAuthorizationControlEnabled = sensor.isAuthorizationControlEnabled
        isSecurityEstablished = sensor.isSecurityEstablished
        oobRandomNumberString = String(data: sensor.securityManager.configuration.oobRandomNumber, encoding: .utf8) ?? ""
    }
}
