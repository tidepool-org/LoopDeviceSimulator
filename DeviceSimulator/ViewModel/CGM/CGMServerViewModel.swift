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

/// Measurement cadences offered to the tester (HYD-G-001). Seconds-level options exist for quick checks;
/// Time Offset only has one-minute resolution, so 5 s readings share an offset.
enum MeasurementIntervalOption: TimeInterval, CaseIterable, Hashable, CustomStringConvertible {
    case fiveSeconds = 5
    case oneMinute = 60
    case fiveMinutes = 300

    var description: String {
        switch self {
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

@Observable
class CGMServerViewModel {

    @ObservationIgnored private var server: GATTServer?
    @ObservationIgnored private var sensor: MockCGMSensor?

    var numberOfSubscribedDevices: Int = 0
    var procedureAlreadyInProgress = false
    var outOfRangeSchedule = false

    var isSensorPoweredOn = true {
        didSet {
            guard oldValue != isSensorPoweredOn else { return }
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
            guard oldValue != requiresEncryption, server != nil else { return }
            restartServer()
        }
    }

    /// ACS gate: when on, the CGM characteristics are protected resources and the collector must complete
    /// the key exchange and use AC Data In / Out. Flips live on the sensor; survives a restart.
    var isAuthorizationControlEnabled = false {
        didSet {
            guard oldValue != isAuthorizationControlEnabled else { return }
            sensor?.isAuthorizationControlEnabled = isAuthorizationControlEnabled
        }
    }
    var isSecurityEstablished = false
    var oobRandomNumberString: String = ""

    var measurementInterval: MeasurementIntervalOption = .fiveMinutes {
        didSet {
            guard oldValue != measurementInterval else { return }
            sensor?.measurementInterval = measurementInterval.rawValue
        }
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
    var glucoseSource: GlucoseSourceOption = .sineWave {
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
    @ObservationIgnored private var preservedTrace: CGMGlucoseTrace = .simulatorDefault
    @ObservationIgnored private var preservedRecordCapacity = CGMRecordStore.defaultCapacity

    @ObservationIgnored private var serverName: String?
    @ObservationIgnored private var refreshTimer: Timer?

    func startServer(serverName: String? = nil) {
        if server != nil {
            stopServer()
        }
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
        sensor.measurementInterval = measurementInterval.rawValue
        sensor.trace = preservedTrace
        sensor.isAuthorizationControlEnabled = isAuthorizationControlEnabled
        sensor.recordStore.capacity = preservedRecordCapacity
        sensor.recordsPerNotification = recordsPerNotification.rawValue
        sensor.delegate = self
        self.sensor = sensor
        mockSensorDidUpdate(sensor)
        sessionRunTimeHoursEntry = String(sensor.sessionRunTime.hours)
        syncGlucoseSourceEntries(from: sensor.trace)

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
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let sensor {
            preservedFeature = sensor.feature
            preservedManualStatus = sensor.manualSensorStatus
            preservedRunTime = sensor.sessionRunTime
            preservedTrace = sensor.trace
            preservedRecordCapacity = sensor.recordStore.capacity
        }
        server?.disconnect()
        server = nil
        sensor = nil
        numberOfSubscribedDevices = 0
        procedureAlreadyInProgress = false
        outOfRangeSchedule = false
        sessionStateString = ""
        sessionStartTimeString = ""
        timeOffsetString = ""
        sessionRunTimeString = ""
        sensorStatusString = ""
        lastGlucoseString = ""
        measurementCount = 0
        nextMeasurementDate = nil
        isSecurityEstablished = false
        storedRecordCount = 0
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
        mockSensorDidUpdate(sensor)
    }

    /// Empties the database without touching the session, so a tester can re-run a backfill from scratch.
    func clearRecords() {
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
        recordSettingsMessage = added > 0
            ? "Added \(added) records covering the last \(backfillDuration); time offset is now \(sensor.timeOffset) min"
            : "Nothing added: the measurement interval is longer than \(backfillDuration)"
        mockSensorDidUpdate(sensor)
    }

    /// Recreates the server only when the sensor is meant to be on; otherwise the radio stays silent.
    func restartServer() {
        stopServer()
        if isSensorPoweredOn {
            startServer()
        }
    }

    // MARK: - Session and measurements

    func startSession() {
        sensor?.startSession()
    }

    func stopSession() {
        sensor?.stopSession()
    }

    func takeMeasurement() {
        sensor?.takeMeasurement()
    }

    func applySessionRunTime() {
        guard let sensor else { return }
        guard let hours = UInt16(sessionRunTimeHoursEntry) else {
            sessionRunTimeHoursEntry = String(sensor.sessionRunTime.hours)
            return
        }
        sensor.sessionRunTime = CGMSessionRunTime(hours: hours)
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
    }

    func centralDidUnsubscribe(characteristicUUID: CBUUID) {
        numberOfSubscribedDevices = server?.subscribedCentrals.count ?? 0
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
        sessionStateString = String(describing: sensor.sessionState)
        if let startTime = sensor.sessionStartTime {
            sessionStartTimeString = "\(startTime)\(sensor.sessionStartTimeSetByCollector ? " (written by collector)" : "")"
        } else {
            sessionStartTimeString = "session not started"
        }
        timeOffsetString = "\(sensor.timeOffset) min"
        sessionRunTimeString = String(describing: sensor.sessionRunTime)
        sensorStatusString = String(describing: sensor.sensorStatus)
        lastGlucoseString = sensor.lastMeasurement.map { String(describing: $0) } ?? "no measurement yet"
        measurementCount = sensor.measurementCount
        nextMeasurementDate = sensor.nextMeasurementDate
        featureFlags = sensor.feature.flags
        manualSensorStatus = sensor.manualSensorStatus
        if let option = MeasurementIntervalOption(rawValue: sensor.measurementInterval) {
            measurementInterval = option
        }
        storedRecordCount = sensor.recordStore.count
        isAuthorizationControlEnabled = sensor.isAuthorizationControlEnabled
        isSecurityEstablished = sensor.isSecurityEstablished
        oobRandomNumberString = String(data: sensor.securityManager.configuration.oobRandomNumber, encoding: .utf8) ?? ""
    }
}
