//
//  CGMClientViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI
import CoreBluetooth
import BluetoothCommonKit
import ContinuousGlucoseMonitorServiceKit

class CGMClientViewModel: ObservableObject {

    private var collector: CGMCollectorController?

    @Published var deviceList: [Device] = []
    @Published var connectedDevice: Device? = nil {
        didSet {
            connectedMessage = "Disconnect from \(connectedDevice?.name ?? "Unknown device")"
        }
    }
    @Published var connectedMessage: String = "Currently Disconnected"
    @Published var isPeripheralConnected: Bool = false

    // MARK: - Configure notifications / indications

    /// Set while the toggles are being cleared after a disconnect, so no CCCD writes are attempted.
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
    /// Mirrors the collector's routing flag; the tester can drop back to plain characteristics to see the
    /// sensor refuse them with Insufficient Authorization.
    @Published var usesSecureChannel: Bool = false {
        didSet {
            guard !isSyncingSecurity, oldValue != usesSecureChannel else { return }
            collector?.usesSecureChannel = usesSecureChannel
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
        collector?.sensorKey = key
        authorizationMessage = "key exchange in progress with sensor key \(key)…"
        collector?.establishSecureSession { [weak self] message in
            self?.authorizationMessage = message
            self?.syncSecurityState()
        }
    }

    func invalidateKey() {
        collector?.invalidateKey { [weak self] message in
            self?.authorizationMessage = message
            self?.syncSecurityState()
        }
    }

    private func syncSecurityState() {
        isSyncingSecurity = true
        isSecurityEstablished = collector?.isSecurityEstablished ?? false
        usesSecureChannel = collector?.usesSecureChannel ?? false
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

    // MARK: - Peripheral connection

    func startClient() {
        collector = CGMCollectorController()
        collector?.delegate = self
        collector?.onMeasurement = { [weak self] records in
            guard let self else { return }
            let fresh = self.acceptRecords(records)
            if self.isReportInProgress {
                self.reportedRecords.append(contentsOf: fresh)
                self.reportedDuplicateCount += records.count - fresh.count
            }
            // A report can replay history, so only a record at or past the newest offset becomes "last".
            guard let latest = fresh.max(by: { $0.timeOffset < $1.timeOffset }) else { return }
            if let last = self.lastMeasurement, latest.timeOffset < last.timeOffset { return }
            self.lastMeasurement = latest
            self.lastMeasurementReceivedAt = Date()
        }
        collector?.onSecurityStateChange = { [weak self] in
            self?.syncSecurityState()
        }
    }

    /// Tears the controller down so no callback can restart scanning after the view is gone; `startClient`
    /// builds a fresh one on the next appearance.
    func stopClient() {
        collector?.stop()
        collector = nil
        reset()
        deviceList.removeAll()
        consoleMessages.removeAll()
        isPeripheralConnected = false
    }

    func connectToDevice(_ device: Device) {
        guard let uuid = UUID(uuidString: device.uuid) else { return }
        connectedDevice = device
        collector?.connectToPeripheralWithUUID(uuid: uuid)
    }

    func refreshList() {
        deviceList.removeAll()
        // The disconnect button tears the controller down; a refresh brings it back so scanning resumes.
        if collector == nil {
            startClient()
        }
        collector?.scanForPeripherals()
    }

    func disconnect() {
        collector?.disconnectFromPeripheral()
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

    private func configureIfChanged(_ uuid: CGMCharacteristicUUID, _ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !isResettingSubscriptions else { return }
        collector?.configureNotifications(uuid, enabled: newValue) { message in
            self.configureMessage = "\(uuid.name): \(message)"
        }
    }

    // MARK: - Reads

    func readFeature() {
        collector?.readFeature { self.featureMessage = $0 }
    }

    func readStatus() {
        collector?.readStatus { self.statusMessage = $0 }
    }

    func readSessionStartTime() {
        collector?.readSessionStartTime { self.readSessionStartTimeMessage = $0 }
    }

    func readSessionRunTime() {
        collector?.readSessionRunTime { self.sessionRunTimeMessage = $0 }
    }

    func readBatteryLevel() {
        collector?.readBatteryLevel { self.batteryMessage = $0 }
    }

    /// Reads the mandatory DIS characteristics one after another, appending each result.
    func readDeviceInformation() {
        deviceInformationMessage = nil
        let characteristics: [DeviceInfoCharacteristicUUID] = [.manufacturerNameString, .modelNumberString, .serialNumberString, .systemID]
        readDeviceInformation(characteristics[...])
    }

    private func readDeviceInformation(_ remaining: ArraySlice<DeviceInfoCharacteristicUUID>) {
        guard let uuid = remaining.first else { return }
        collector?.readDeviceInformation(uuid) { message in
            self.deviceInformationMessage = (self.deviceInformationMessage ?? "") + "\(uuid.name): \(message)\n"
            self.readDeviceInformation(remaining.dropFirst())
        }
    }

    // MARK: - Writes

    func writeSessionStartTime() {
        collector?.writeSessionStartTime { self.writeSessionStartTimeMessage = $0 }
    }

    // MARK: - CGM Specific Ops Control Point

    /// Every request op code is offered (CGMS Table 3.6); the operand entries below apply to the selected one.
    @Published var selectedSpecificOp: CGMSpecificOpsOpcode = .getCommunicationInterval
    @Published var communicationIntervalEntry = "5"
    @Published var calibrationRecordNumberEntry = String(CGMCalibrationRecord.lastRecordNumber)
    @Published var calibrationGlucoseEntry = "120"
    @Published var calibrationTimeEntry = "0"
    @Published var nextCalibrationTimeEntry = "0"
    @Published var alertLevelEntry = "180"

    var specificOpsOperand: CGMSpecificOpsOperand {
        selectedSpecificOp.requestOperand ?? CGMSpecificOpsOperand.none
    }

    func startSession() {
        sendSpecificOps(.startSession)
    }

    func stopSession() {
        sendSpecificOps(.stopSession)
    }

    private func sendSpecificOps(_ opcode: CGMSpecificOpsOpcode) {
        guard let collector else { return }
        sendSpecificOps(CGMSpecificOpsRequest.encode(opcode, e2eCRC: collector.isE2EProtectionSupported))
    }

    /// Builds the selected request from the operand entries; a bad entry is reported instead of sent.
    func sendSelectedSpecificOp() {
        guard let collector else { return }
        let e2eCRC = collector.isE2EProtectionSupported
        let opcode = selectedSpecificOp
        let request: Data
        switch specificOpsOperand {
        case .none:
            request = CGMSpecificOpsRequest.encode(opcode, e2eCRC: e2eCRC)
        case .communicationIntervalMinutes:
            guard let minutes = UInt8(communicationIntervalEntry) else {
                cgmcpMessage = "Communication interval must be 0–255 minutes"
                return
            }
            request = CGMSpecificOpsRequest.setCommunicationInterval(minutes: minutes, e2eCRC: e2eCRC)
        case .calibrationRecordNumber:
            guard let number = UInt16(calibrationRecordNumberEntry) else {
                cgmcpMessage = "Record number must be 0–65535 (65535 = last)"
                return
            }
            request = CGMSpecificOpsRequest.getGlucoseCalibrationValue(recordNumber: number, e2eCRC: e2eCRC)
        case .calibrationRecord:
            guard let glucose = calibrationGlucoseEntry.parsedDouble, let time = UInt16(calibrationTimeEntry),
                  let next = UInt16(nextCalibrationTimeEntry)
            else {
                cgmcpMessage = "Calibration needs a numeric glucose and 0–65535 minute offsets"
                return
            }
            let record = CGMCalibrationRecord(glucoseConcentration: glucose, calibrationTime: time, nextCalibrationTime: next)
            request = CGMSpecificOpsRequest.setGlucoseCalibrationValue(record, e2eCRC: e2eCRC)
        case .glucoseLevel, .rateLevel:
            guard let level = alertLevelEntry.parsedDouble else {
                cgmcpMessage = "Alert level must be numeric"
                return
            }
            request = CGMSpecificOpsRequest.setLevel(opcode, value: level, e2eCRC: e2eCRC)
        }
        sendSpecificOps(request)
    }

    private func sendSpecificOps(_ request: Data) {
        cgmcpMessage = nil
        collector?.sendSpecificOpsRequest(request) { message in
            self.cgmcpMessage = (self.cgmcpMessage ?? "") + "\n" + message
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
        guard let collector else { return }
        racpMessage = nil
        if request.opcode == .reportStoredRecords {
            reportedRecords.removeAll()
            reportedDuplicateCount = 0
            isReportInProgress = true
        }
        collector.sendRACPRequest(request) { [weak self] message in
            guard let self else { return }
            self.racpMessage = (self.racpMessage ?? "") + "\n" + message
            // The Response Code indication closes the report; records arrived before it.
            if message.contains("RACP") || message.contains("error") || message.contains("disconnected") {
                self.isReportInProgress = false
            }
        }
    }
}

extension CGMClientViewModel: PeripheralControllerDelegate {
    func peripheralDiscovered(sender: PeripheralController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber) {
        let device = Device(name: peripheralName, uuid: peripheralID.uuidString, advertisedName: advertisingName, rssi: rssi, serviceData: serviceData)
        // The controller rescans after a disconnect, so the same sensor can be reported again.
        deviceList.removeAll { $0.uuid == device.uuid }
        deviceList.append(device)
        deviceList.sort(by: { $0.rssi.compare($1.rssi) == .orderedDescending })
    }

    func connectedToPeripheral(sender: PeripheralController) {
        isPeripheralConnected = true
    }

    func didDisconnectFromPeripheral(sender: PeripheralController) {
        connectedMessage = "Currently disconnected"
        deviceList.removeAll()
        resetSubscriptions()
        consoleMessages = "\(#function) wait for the user to switch back to peripheral view\n" + consoleMessages
    }

    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String) {
        ConsoleOut.shared.logMessage(message: "\(cbUUID) notification/indication: \(message)")
        switch cbUUID {
        case CGMCharacteristicUUID.measurement.cbUUID:
            measurementMessage = message
        case CGMCharacteristicUUID.feature.cbUUID:
            // Arrives after discovery (automatic read) and whenever the sensor indicates a change.
            featureMessage = message
        case CGMCharacteristicUUID.recordAccessControlPoint.cbUUID:
            racpMessage = (racpMessage ?? "") + "\n" + message
        case CGMCharacteristicUUID.specificOpsControlPoint.cbUUID:
            cgmcpMessage = (cgmcpMessage ?? "") + "\n" + message
        default:
            consoleMessages = "\(cbUUID): \(message)\n" + consoleMessages
        }
    }
}
