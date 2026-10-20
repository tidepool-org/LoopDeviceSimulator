//
//  CGMClientViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Test collector UI over the kit's `ContinuousGlucoseMonitorService`, the same client a Loop CGM plugin
//  builds on. The service calls back on BluetoothCommonKit's queues, so everything here hops to the main
//  thread before touching published state.

import SwiftUI
import CoreBluetooth
import BluetoothCommonKit
import ContinuousGlucoseMonitorServiceKit

class CGMClientViewModel: ObservableObject {

    private var sensor: ContinuousGlucoseMonitorService?

    @Published var deviceList: [Device] = []
    @Published var connectedDevice: Device? = nil {
        didSet {
            connectedMessage = "Disconnect from \(connectedDevice?.name ?? "Unknown device")"
        }
    }
    @Published var connectedMessage: String = "Currently Disconnected"
    @Published var isPeripheralConnected: Bool = false

    // MARK: - Configure notifications / indications

    /// Set while the toggles are being synced from the sensor or cleared after a disconnect, so no CCCD
    /// writes are attempted. The kit subscribes to everything during configuration, so they start ON.
    private var isResettingSubscriptions = false

    @Published var measurementNotificationsEnabled: Bool = false {
        didSet { configureIfChanged(.measurement, oldValue, measurementNotificationsEnabled) }
    }
    @Published var featureIndicationsEnabled: Bool = false {
        didSet { configureIfChanged(.feature, oldValue, featureIndicationsEnabled) }
    }
    @Published var racpIndicationsEnabled: Bool = false {
        didSet { configureIfChanged(.recordAccessControlPoint, oldValue, racpIndicationsEnabled) }
    }
    @Published var cgmcpIndicationsEnabled: Bool = false {
        didSet { configureIfChanged(.specificOpsControlPoint, oldValue, cgmcpIndicationsEnabled) }
    }
    @Published var configureMessage: String? = nil

    // MARK: - Authorization Control (secure channel)

    @Published var isSecurityEstablished: Bool = false
    /// Mirrors the service's routing flag; the tester can drop back to plain characteristics to see the
    /// sensor refuse them with Insufficient Authorization.
    @Published var usesSecureChannel: Bool = false {
        didSet {
            guard !isSyncingSecurity, oldValue != usesSecureChannel else { return }
            sensor?.usesSecureChannel = usesSecureChannel
        }
    }
    @Published var authorizationMessage: String? = nil
    /// Sensor key (OOB number) sent during the key exchange; defaults to the mock sensor's. Editable so QA
    /// can run a mismatched key and see the confirmation fail.
    @Published var sensorKeyEntry: String = CGMConstants.oobRandomNumber
    private var isSyncingSecurity = false

    func establishSecureSession() {
        let key = sensorKeyEntry.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            authorizationMessage = "Sensor key cannot be empty"
            return
        }
        // Bytes, not characters: the key goes over the air as UTF-8.
        guard key.utf8.count <= CGMConstants.maxSensorKeyBytes else {
            authorizationMessage = "Sensor key must be at most \(CGMConstants.maxSensorKeyBytes) bytes; \(key.utf8.count) entered"
            return
        }
        sensor?.setOOBString(key)
        authorizationMessage = "key exchange in progress with sensor key \(key)…"
        sensor?.establishSecureSession { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    authorizationMessage = sensor?.isSecurityEstablished == true
                        ? "secure session established; CGM traffic now uses the secure channel"
                        : "done; no secure session (key invalidated or exchange incomplete)"
                case .failure(let error):
                    authorizationMessage = "key exchange failed: \(error.localizedDescription)"
                }
                syncSecurityState()
            }
        }
    }

    func invalidateKey() {
        sensor?.invalidateKey { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                switch result {
                case .success: authorizationMessage = "key invalidated; CGM traffic is back on the plain characteristics"
                case .failure(let error): authorizationMessage = "invalidate key failed: \(error.localizedDescription)"
                }
                syncSecurityState()
            }
        }
    }

    private func syncSecurityState() {
        isSyncingSecurity = true
        isSecurityEstablished = sensor?.isSecurityEstablished ?? false
        usesSecureChannel = sensor?.usesSecureChannel ?? false
        isSyncingSecurity = false
    }

    // MARK: - Last measurement

    @Published var lastMeasurement: CGMMeasurementRecord? = nil
    @Published var lastMeasurementReceivedAt: Date? = nil
    /// Records received since connecting; one notification may carry several.
    @Published var measurementCount: Int = 0
    /// Distinct records since connecting, and repeats dropped. Keyed on the whole encoded record rather
    /// than Time Offset, because sub-minute intervals put several real readings on one offset.
    @Published private(set) var uniqueRecordCount: Int = 0
    @Published private(set) var duplicateCount: Int = 0
    private var seenRecords: Set<Data> = []

    /// Stores the new records, drops repeats, and returns the new ones in arrival order.
    private func acceptRecords(_ records: [CGMMeasurementRecord]) -> [CGMMeasurementRecord] {
        var fresh: [CGMMeasurementRecord] = []
        for record in records {
            if seenRecords.insert(record.encoded(e2eCRC: false)).inserted {
                fresh.append(record)
            } else {
                duplicateCount += 1
            }
        }
        measurementCount += records.count
        uniqueRecordCount = seenRecords.count
        return fresh
    }

    var lastGlucoseString: String {
        guard let record = lastMeasurement else { return "—" }
        return record.glucoseConcentration.isNaN ? "NaN" : "\(Self.format(record.glucoseConcentration)) mg/dL"
    }

    var lastTrendString: String {
        guard let record = lastMeasurement else { return "—" }
        guard let trend = record.trend else { return "not included" }
        return trend.isNaN ? "NaN" : "\(trend >= 0 ? "+" : "")\(Self.format(trend)) mg/dL/min"
    }

    var lastQualityString: String {
        guard let record = lastMeasurement else { return "—" }
        guard let quality = record.quality else { return "not included" }
        return quality.isNaN ? "NaN" : "\(Self.format(quality))%"
    }

    var lastTimeOffsetString: String {
        lastMeasurement.map { "\($0.timeOffset) min" } ?? "—"
    }

    var lastSensorStatusString: String {
        lastMeasurement.map { String(describing: $0.sensorStatus) } ?? "—"
    }

    var lastReceivedString: String {
        lastMeasurementReceivedAt?.formatted(date: .omitted, time: .standard) ?? "—"
    }

    /// SFLOAT special values decode to NaN or ±infinity; only finite values can be shown as integers.
    private static func format(_ value: Double) -> String {
        guard value.isFinite else {
            return value.isNaN ? "NaN" : (value > 0 ? "+INFINITY" : "-INFINITY")
        }
        return value.compactDescription
    }

    // MARK: - Messages

    @Published var featureMessage: String? = nil
    @Published var statusMessage: String? = nil
    @Published var readSessionStartTimeMessage: String? = nil
    @Published var writeSessionStartTimeMessage: String? = nil
    @Published var sessionRunTimeMessage: String? = nil
    @Published var deviceInformationMessage: String? = nil
    @Published var batteryMessage: String? = nil
    @Published var measurementMessage: String? = nil
    @Published var cgmcpMessage: String? = nil
    @Published var racpMessage: String? = nil
    @Published var consoleMessages: String = ""

    /// One line for a procedure result: the value, or the error.
    private static func describe<T>(_ result: DeviceCommResult<T>, success: ((T) -> String)? = nil) -> String {
        switch result {
        case .success(let value): return success?(value) ?? String(describing: value)
        case .failure(let error): return "error: \(error.localizedDescription)"
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Peripheral connection

    func startClient() {
        SessionLog.shared.context = SessionLog.Context(mode: .cgm, role: .client)
        SessionLog.shared.log(.lifecycle, "CGM collector client started")
        // No background mode in the simulator, so no state restoration.
        let sensor = ContinuousGlucoseMonitorService(restoreOptions: nil)
        sensor.delegate = self
        sensor.loggingDelegate = self
        sensor.setOOBString(CGMConstants.oobRandomNumber)
        self.sensor = sensor
        sensor.scanForSensors()
    }

    /// Tears the service down so no callback can restart scanning after the view is gone; `startClient`
    /// builds a fresh one on the next appearance.
    func stopClient() {
        SessionLog.shared.log(.lifecycle, "CGM collector client stopped")
        defer { SessionLog.shared.context = SessionLog.Context() }   // after the disconnect lines are out
        sensor?.delegate = nil
        sensor?.prepareForDeactivation()
        sensor = nil
        reset()
        deviceList.removeAll()
        consoleMessages.removeAll()
        isPeripheralConnected = false
    }

    func connectToDevice(_ device: Device) {
        guard let uuid = UUID(uuidString: device.uuid) else { return }
        connectedDevice = device
        sensor?.connectToSensor(withIdentifier: uuid)
    }

    func refreshList() {
        deviceList.removeAll()
        if sensor == nil {
            startClient()
        } else {
            sensor?.scanForSensors()
        }
    }

    /// Forget rather than disconnect: BluetoothCommonKit reconnects to a remembered sensor on its own, which
    /// is right for Loop and wrong for a tester who just tapped Disconnect. Scanning resumes for the list.
    func disconnect() {
        sensor?.forgetSensor()
        sensor?.scanForSensors()
    }

    func switchToPeripheralList() {
        isPeripheralConnected = false
    }

    func clearConsole() {
        consoleMessages.removeAll()
    }

    private func reset() {
        resetSubscriptions()
        syncSecurityState()
        authorizationMessage = nil
        lastMeasurement = nil
        lastMeasurementReceivedAt = nil
        measurementCount = 0
        uniqueRecordCount = 0
        duplicateCount = 0
        seenRecords.removeAll()
        featureMessage = nil
        statusMessage = nil
        readSessionStartTimeMessage = nil
        writeSessionStartTimeMessage = nil
        sessionRunTimeMessage = nil
        deviceInformationMessage = nil
        batteryMessage = nil
        measurementMessage = nil
        cgmcpMessage = nil
        racpMessage = nil
        reportedRecords.removeAll()
        reportedDuplicateCount = 0
        isReportInProgress = false
    }

    /// A new link has no CCCD subscriptions, so the toggles must show OFF without writing anything.
    private func resetSubscriptions() {
        isResettingSubscriptions = true
        measurementNotificationsEnabled = false
        featureIndicationsEnabled = false
        racpIndicationsEnabled = false
        cgmcpIndicationsEnabled = false
        isResettingSubscriptions = false
        configureMessage = nil
    }

    /// After configuration the kit has subscribed; show what the sensor actually has on.
    private func syncSubscriptions() {
        guard let sensor else { return }
        isResettingSubscriptions = true
        measurementNotificationsEnabled = sensor.isNotifying(.measurement)
        featureIndicationsEnabled = sensor.isNotifying(.feature)
        racpIndicationsEnabled = sensor.isNotifying(.recordAccessControlPoint)
        cgmcpIndicationsEnabled = sensor.isNotifying(.specificOpsControlPoint)
        isResettingSubscriptions = false
    }

    private func configureIfChanged(_ uuid: CGMCharacteristicUUID, _ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !isResettingSubscriptions else { return }
        sensor?.setNotifications(uuid, enabled: newValue) { [weak self] result in
            self?.onMain { self?.configureMessage = "\(uuid.name): \(Self.describe(result) { _ in "configured: \(newValue)" })" }
        }
    }

    // MARK: - Reads

    func readFeature() {
        sensor?.getFeature { [weak self] result in self?.onMain { self?.featureMessage = Self.describe(result) } }
    }

    func readStatus() {
        sensor?.getStatus { [weak self] result in self?.onMain { self?.statusMessage = Self.describe(result) } }
    }

    func readSessionStartTime() {
        sensor?.getSessionStartTime { [weak self] result in self?.onMain { self?.readSessionStartTimeMessage = Self.describe(result) } }
    }

    func readSessionRunTime() {
        sensor?.getSessionRunTime { [weak self] result in self?.onMain { self?.sessionRunTimeMessage = Self.describe(result) } }
    }

    func readBatteryLevel() {
        sensor?.getBatteryLevel { [weak self] result in self?.onMain { self?.batteryMessage = Self.describe(result) { "battery \($0)%" } } }
    }

    /// Reads the mandatory DIS characteristics one after another, appending each result.
    func readDeviceInformation() {
        deviceInformationMessage = nil
        let characteristics: [DeviceInfoCharacteristicUUID] = [.manufacturerNameString, .modelNumberString, .serialNumberString, .systemID]
        readDeviceInformation(characteristics[...])
    }

    private func readDeviceInformation(_ remaining: ArraySlice<DeviceInfoCharacteristicUUID>) {
        guard let uuid = remaining.first else { return }
        sensor?.getDeviceInformation(uuid) { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                deviceInformationMessage = (deviceInformationMessage ?? "") + "\(uuid.name): \(Self.describe(result))\n"
                readDeviceInformation(remaining.dropFirst())
            }
        }
    }

    // MARK: - Writes

    func writeSessionStartTime() {
        sensor?.setSessionStartTime { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                writeSessionStartTimeMessage = Self.describe(result) { "written" }
                // The sensor re-derives its start time from the write (§3.4.1); refresh the copy used to stamp
                // calibrations. A refused write leaves the old value, which is still the sensor's.
                if case .success = result { readSessionStartTime() }
            }
        }
    }

    // MARK: - CGM Specific Ops Control Point

    /// Every request op code is offered (CGMS Table 3.6); the operand entries below apply to the selected one.
    @Published var selectedSpecificOp: CGMSpecificOpsOpcode = .getCommunicationInterval
    @Published var communicationInterval: CommunicationIntervalOption = .fiveMinutes
    @Published var calibrationRecordNumberEntry = String(CGMCalibrationRecord.lastRecordNumber)
    @Published var calibrationGlucoseEntry = "120"
    @Published var alertLevelEntry = "180"

    var specificOpsOperand: CGMSpecificOpsOperand {
        selectedSpecificOp.requestOperand ?? CGMSpecificOpsOperand.none
    }

    /// Minutes since the sensor's Session Start Time as last read; nil until it has been read.
    private var currentTimeOffset: UInt16? {
        guard let start = sensor?.sessionStartTime?.date else { return nil }
        return UInt16(clamping: max(0, Int(Date().timeIntervalSince(start) / 60)))
    }

    func startSession() {
        cgmcpMessage = nil
        sensor?.startSession(completion: cgmcpCompletion)
    }

    func stopSession() {
        cgmcpMessage = nil
        sensor?.stopSession(completion: cgmcpCompletion)
    }

    /// Sends the selected request from the operand entries; a bad entry is reported instead of sent.
    func sendSelectedSpecificOp() {
        guard let sensor else { return }
        let opcode = selectedSpecificOp
        cgmcpMessage = nil
        switch specificOpsOperand {
        case .none:
            sensor.sendSpecificOpsRequest(opcode, operand: Data(), completion: cgmcpCompletion)
        case .communicationIntervalMinutes:
            sensor.setCommunicationInterval(minutes: communicationInterval.rawValue, completion: cgmcpCompletion)
        case .calibrationRecordNumber:
            guard let number = UInt16(calibrationRecordNumberEntry) else {
                cgmcpMessage = "Record number must be 0–65535 (65535 = last)"
                return
            }
            sensor.getGlucoseCalibrationValue(recordNumber: number, completion: cgmcpCompletion)
        case .calibrationRecord:
            guard let glucose = calibrationGlucoseEntry.parsedDouble else {
                cgmcpMessage = "Calibration glucose must be numeric"
                return
            }
            // The fingerstick is taken as the tap happens: Calibration Time is now, in minutes since the
            // sensor's Session Start Time (Table 3.7). Next Calibration Time, Record Number and Status are the
            // sensor's to fill in and are sent as zero.
            guard let calibrationTime = currentTimeOffset else {
                cgmcpMessage = "Read Session Start Time first so the calibration can be stamped"
                return
            }
            sensor.setGlucoseCalibrationValue(CGMCalibrationRecord(glucoseConcentration: glucose, calibrationTime: calibrationTime), completion: cgmcpCompletion)
        case .glucoseLevel, .rateLevel:
            guard let level = alertLevelEntry.parsedDouble else {
                cgmcpMessage = "Alert level must be numeric"
                return
            }
            sensor.setAlertLevel(opcode, value: level, completion: cgmcpCompletion)
        }
    }

    private var cgmcpCompletion: CGMSpecificOpsCompletion {
        { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                cgmcpMessage = (cgmcpMessage ?? "") + "\nCGMCP " + Self.describe(result)
            }
        }
    }

    /// A Get answer moves the matching entry to what the sensor holds, so the picker shows the sensor's value
    /// rather than the tester's last choice. A communication interval outside the offered options is left to
    /// the message text.
    private func mirrorSpecificOpsResponse(_ response: CGMSpecificOpsResponse) {
        switch response {
        case .communicationInterval(let minutes):
            if let option = CommunicationIntervalOption(rawValue: minutes) {
                communicationInterval = option
            }
        case let .level(opcode, value):
            // Only the level the tester is working on; a Get for another family must not clobber the entry.
            guard let family = opcode.alertLevelKeyPath, family == selectedSpecificOp.alertLevelKeyPath, value.isFinite else { return }
            alertLevelEntry = value.compactDescription
        case let .responseCode(request, code):
            // A new session has a new start time; refresh it so calibrations are stamped against the right one.
            if request == CGMSpecificOpsOpcode.startSession.rawValue, code == CGMSpecificOpsResponseCode.success.rawValue {
                readSessionStartTime()
            }
        case .calibrationValue:
            break
        }
    }

    // MARK: - Record Access Control Point

    @Published var racpOpcode: CGMRACPOpcode = .reportNumberOfStoredRecords
    @Published var racpOperator: CGMRACPOperator = .allRecords
    @Published var racpMinimumEntry = "0"
    @Published var racpMaximumEntry = "0"

    var racpNeedsMinimum: Bool { racpOperator == .greaterThanOrEqualTo || racpOperator == .withinRangeOf }
    var racpNeedsMaximum: Bool { racpOperator == .lessThanOrEqualTo || racpOperator == .withinRangeOf }

    /// Records delivered by the most recent Report Stored Records, so a backfill is visible at a glance.
    @Published var reportedRecords: [CGMMeasurementRecord] = []
    @Published var reportedDuplicateCount = 0
    @Published var isReportInProgress = false

    var reportedRecordsSummary: String {
        let receiving = isReportInProgress ? " (receiving…)" : ""
        let duplicates = reportedDuplicateCount > 0 ? ", \(reportedDuplicateCount) duplicates skipped" : ""
        guard let first = reportedRecords.first, let last = reportedRecords.last else {
            return reportedDuplicateCount > 0 ? "0 new records\(duplicates)\(receiving)" : (isReportInProgress ? "receiving…" : "none")
        }
        return "\(reportedRecords.count) new records, offsets \(first.timeOffset)–\(last.timeOffset) min\(duplicates)\(receiving)"
    }

    /// HYD-G-015: ask for everything after the last measurement seen, or all records if none was seen.
    func backfillSinceLastMeasurement() {
        let request: CGMRACPRequest
        if let last = lastMeasurement, last.timeOffset < UInt16.max {
            request = CGMRACPRequest(opcode: .reportStoredRecords, racpOperator: .greaterThanOrEqualTo, minimum: last.timeOffset + 1)
        } else {
            request = CGMRACPRequest(opcode: .reportStoredRecords, racpOperator: .allRecords)
        }
        send(request)
    }

    func sendRACPRequest() {
        let request: CGMRACPRequest
        if racpOpcode == .abortOperation {
            request = .abort
        } else {
            // Only the filter fields the operator actually sends are validated; hidden ones cannot block.
            var minimum: UInt16 = 0
            var maximum: UInt16 = 0
            if racpNeedsMinimum {
                guard let value = UInt16(racpMinimumEntry) else {
                    racpMessage = "Minimum Time Offset must be 0–65535 minutes"
                    return
                }
                minimum = value
            }
            if racpNeedsMaximum {
                guard let value = UInt16(racpMaximumEntry) else {
                    racpMessage = "Maximum Time Offset must be 0–65535 minutes"
                    return
                }
                maximum = value
            }
            if racpOperator == .withinRangeOf, minimum > maximum {
                racpMessage = "Within Range Of needs minimum ≤ maximum"
                return
            }
            request = CGMRACPRequest(opcode: racpOpcode, racpOperator: racpOperator, minimum: minimum, maximum: maximum)
        }
        send(request)
    }

    private func send(_ request: CGMRACPRequest) {
        guard let sensor else { return }
        racpMessage = nil
        // Clear only when opening a fresh report. A report requested mid-transfer is refused by the sensor
        // (Procedure Already In Progress) and must not wipe the one still arriving.
        let opensReport = request.opcode == .reportStoredRecords && !isReportInProgress
        if opensReport {
            reportedRecords.removeAll()
            reportedDuplicateCount = 0
            isReportInProgress = true
        }
        sensor.sendRACPRequest(request) { [weak self] result in
            self?.onMain { [weak self] in
                guard let self else { return }
                racpMessage = (racpMessage ?? "") + "\nRACP " + Self.describe(result)
                // The completion is the closing Response Code (or the refusal); the records came before it.
                if opensReport { isReportInProgress = false }
            }
        }
    }
}

// MARK: - CGMSensorDelegate

extension CGMClientViewModel: CGMSensorDelegate {
    func sensor(_ sensor: CGMSensorComms, didDiscoverSensorWithName name: String?, identifier: UUID, advertisementData: [String: Any], signalStrength: NSNumber) {
        // A Mac (or any peripheral) may advertise the service without a name the system has cached yet;
        // dropping it would hide a perfectly connectable sensor. Fall back to the advertised or a placeholder name.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let device = Device(name: name ?? advertisedName ?? "Unnamed \(identifier.uuidString.prefix(8))",
                            uuid: identifier.uuidString,
                            advertisedName: advertisedName ?? "unknown",
                            rssi: signalStrength,
                            serviceData: advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])
        onMain {
            // The service rescans after a disconnect, so the same sensor can be reported again.
            self.deviceList.removeAll { $0.uuid == device.uuid }
            self.deviceList.append(device)
            self.deviceList.sort(by: { $0.rssi.compare($1.rssi) == .orderedDescending })
        }
    }

    func sensorConnectionStatusChanged(_ sensor: CGMSensorComms) {
        let isConnected = sensor.isConnected
        onMain {
            if isConnected {
                SessionLog.shared.log(.connection, "connected to sensor")
                self.isPeripheralConnected = true
            } else {
                SessionLog.shared.log(.connection, "disconnected from sensor")
                self.connectedMessage = "Currently disconnected"
                self.deviceList.removeAll()
                self.resetSubscriptions()
                // Whatever was still being reported is not coming; keep what arrived.
                self.isReportInProgress = false
                self.syncSecurityState()
                self.consoleMessages = "disconnected; wait for the user to switch back to peripheral view\n" + self.consoleMessages
            }
        }
    }

    func sensorIsReady(_ sensor: CGMSensorComms) {
        let feature = sensor.feature
        let startTime = sensor.sessionStartTime
        onMain {
            self.syncSubscriptions()
            self.syncSecurityState()
            self.featureMessage = feature.map { String(describing: $0) }
            self.readSessionStartTimeMessage = startTime.map { String(describing: $0) }
        }
    }

    func sensorDidCompleteAuthentication(_ sensor: CGMSensorComms, error: DeviceCommError?) {
        onMain {
            if let error {
                self.authorizationMessage = "secure session ended: \(error.localizedDescription)"
            }
            self.syncSecurityState()
        }
    }

    /// The sensor flipped protection (AC Status) or a key came or went; the Use Secure Channel toggle follows.
    func sensorDidUpdateSecurity(_ sensor: CGMSensorComms) {
        onMain {
            self.authorizationMessage = sensor.usesSecureChannel
                ? "sensor protects its resources; CGM traffic is on the secure channel"
                : "sensor serves CGM plainly\(sensor.isSecurityEstablished ? " (key kept for when protection turns on)" : ""); CGM traffic is on the plain characteristics"
            self.syncSecurityState()
        }
    }

    func sensor(_ sensor: CGMSensorComms, didReceiveMeasurements records: [CGMMeasurementRecord]) {
        onMain {
            // Every notification is contact with the sensor, even a status-only record identical to the last.
            self.lastMeasurementReceivedAt = Date()
            self.measurementMessage = records.map { String(describing: $0) }.joined(separator: "; ")
            let fresh = self.acceptRecords(records)
            if self.isReportInProgress {
                self.reportedRecords.append(contentsOf: fresh)
                self.reportedDuplicateCount += records.count - fresh.count
            }
            // A report can replay history, so only a record at or past the newest offset becomes "last".
            guard let latest = fresh.max(by: { $0.timeOffset < $1.timeOffset }) else { return }
            if let last = self.lastMeasurement, latest.timeOffset < last.timeOffset { return }
            self.lastMeasurement = latest
        }
    }

    func sensor(_ sensor: CGMSensorComms, didUpdateFeature feature: CGMFeature) {
        // Arrives after discovery (automatic read) and whenever the sensor indicates a change.
        onMain { self.featureMessage = String(describing: feature) }
    }

    func sensor(_ sensor: CGMSensorComms, didReceiveSpecificOpsResponse response: CGMSpecificOpsResponse) {
        onMain { self.mirrorSpecificOpsResponse(response) }
    }

    func sensor(_ sensor: CGMSensorComms, didReceiveRACPResponse response: CGMRACPResponse) {
        // Normally the request's completion closes the report; this covers a Response Code that arrives
        // after the sensor refused a later request and the completion is already gone.
        guard case let .responseCode(request, _) = response,
              request == CGMRACPOpcode.reportStoredRecords.rawValue || request == CGMRACPOpcode.abortOperation.rawValue
        else { return }
        onMain { self.isReportInProgress = false }
    }

    func sensor(_ sensor: CGMSensorComms, didEncounterError error: DeviceCommError, forCharacteristic uuid: CBUUID?) {
        onMain { self.consoleMessages = "\(uuid?.uuidString ?? "sensor"): \(error.localizedDescription)\n" + self.consoleMessages }
    }

    func sensorDidUpdateState(_ sensor: CGMSensorComms) { }
}

// MARK: - DeviceCommLoggingDelegate

/// The kit's client logs through this; the shared console forwards to the session log.
extension CGMClientViewModel: DeviceCommLoggingDelegate {
    func logConnectionEvent(function: StaticString, _ message: String) {
        ConsoleOut.shared.logMessage(message: "collector connection \(function) \(message)")
    }

    func logSendEvent(function: StaticString, _ message: String) {
        ConsoleOut.shared.logMessage(message: "collector \(function) \(message)")
    }

    func logReceiveEvent(function: StaticString, _ message: String) {
        ConsoleOut.shared.logMessage(message: "collector received \(message)")
        onMain { self.consoleMessages = "\(message)\n" + self.consoleMessages }
    }

    func logErrorEvent(function: StaticString, _ message: String) {
        ConsoleOut.shared.logMessage(message: "collector error \(function) \(message)")
        onMain { self.consoleMessages = "error: \(message)\n" + self.consoleMessages }
    }
}
