//
//  CGMCollectorController.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Test collector (GATT client) for the CGM sensor: one action per server capability so each server phase
//  can be exercised from a second device. Connection lifecycle lives in PeripheralController.

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import ContinuousGlucoseMonitorServiceKit

class CGMCollectorController: PeripheralController {

    /// One pending completion per characteristic, so an unanswered control point write cannot swallow
    /// the next unrelated notification.
    private var completions: [CBUUID: MessageCompletion] = [:]

    /// CCCD writes are answered by `didUpdateNotificationStateFor`, never by a value, so they are tracked
    /// apart from reads: a read result or notification must not consume a pending configure completion.
    private var configureCompletions: [CBUUID: MessageCompletion] = [:]

    /// Last CGM Feature seen (read after discovery, re-read on tap, or indicated); decides whether reads
    /// and writes carry an E2E-CRC.
    private(set) var feature: CGMFeature?

    /// Known once the Feature read after discovery completes; request builders need it for the E2E-CRC.
    var isE2EProtectionSupported: Bool { feature?.isE2ECRCSupported ?? false }

    /// Decoded CGM Measurement records, called for every notification (one notification may carry several).
    var onMeasurement: (([CGMMeasurementRecord]) -> Void)?

    /// Every decoded CGMCP indication, so the UI can mirror values the sensor reports (e.g. a Get response).
    var onSpecificOpsResponse: ((CGMSpecificOpsResponse) -> Void)?

    /// Last Session Start Time read from the sensor (after discovery, on demand, or after Start Session);
    /// the base for stamping a calibration's Calibration Time (Table 3.7, minutes since session start).
    private(set) var sessionStartTime: CGMSessionStartTime?

    private static let controlPointUUIDs: Set<CBUUID> = [
        CGMCharacteristicUUID.recordAccessControlPoint.cbUUID,
        CGMCharacteristicUUID.specificOpsControlPoint.cbUUID
    ]

    // MARK: - Authorization Control (secure channel)

    /// Client half of ACS: ECDH key exchange over the AC Control Point, then protected reads and writes
    /// through AC Data In / Out addressed by resource handle. Same OOB number as the mock sensor.
    let securityManager = SecurityManager()
    private(set) lazy var authorizationControlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: 19)
    private(set) lazy var authorizationData = ACDataDataHandler(securityManager: securityManager, maxRequestSize: 19)

    /// Derived session key (SecurityManagerDelegate storage); nil until the handshake completes.
    var sharedKeyData: Data?

    /// Out-of-band number used for the confirmation step. Must match the sensor's key for the exchange to
    /// succeed; QA sets a different value to exercise the failure path.
    var sensorKey: String {
        get { String(data: securityManager.configuration.oobRandomNumber, encoding: .utf8) ?? "" }
        set { securityManager.configuration.oobRandomNumber = Data(newValue.utf8) }
    }

    var isSecurityEstablished: Bool { securityManager.applicationSecurityEstablished }

    /// Route CGMS reads, writes and control point requests through AC Data In instead of the plain
    /// characteristics. Turned on automatically when a handshake succeeds.
    var usesSecureChannel = false

    /// Fired when the secure session is established, invalidated or lost.
    var onSecurityStateChange: (() -> Void)?

    private var handshakeCompletion: MessageCompletion?

    init() {
        super.init(
            scanServiceUUIDs: [CGMCharacteristicUUID.service.cbUUID],
            discoveredServiceUUIDs: [
                CGMCharacteristicUUID.service.cbUUID,
                DeviceInfoCharacteristicUUID.service.cbUUID,
                BatteryCharacteristicUUID.service.cbUUID,
                ACCharacteristicUUID.service.cbUUID
            ]
        )
        securityManager.configuration.oobRandomNumber = Data(CGMConstants.oobRandomNumber.utf8)
        securityManager.delegate = self
    }

    // MARK: - PeripheralController hooks

    override func peripheralDidDiscoverCharacteristics(_ characteristics: [CBCharacteristic], for service: CBService, on peripheral: CBPeripheral) {
        // CGMS §3.1: Feature must be read before anything else can be interpreted (E2E-CRC presence).
        guard service.uuid == CGMCharacteristicUUID.service.cbUUID,
              let featureCharacteristic = characteristics.first(where: { $0.uuid == CGMCharacteristicUUID.feature.cbUUID })
        else { return }
        peripheral.readValue(for: featureCharacteristic)
        // Session Start Time follows (reads are answered in order, so Feature is known when it decodes); it
        // is needed to stamp calibrations without a manual read.
        if let startTime = characteristics.first(where: { $0.uuid == CGMCharacteristicUUID.sessionStartTime.cbUUID }) {
            peripheral.readValue(for: startTime)
        }
    }

    override func peripheralDidDisconnect() {
        feature = nil
        sessionStartTime = nil
        // The session key and nonce sequence cannot be trusted across a link loss; start over next time.
        let hadSession = isSecurityEstablished || usesSecureChannel
        sharedKeyData = nil
        usesSecureChannel = false
        _ = authorizationControlPoint.getPendingProceduresAndReset()
        handshakeCompletion?("disconnected during key exchange")
        handshakeCompletion = nil
        if hadSession { onSecurityStateChange?() }
        // In-flight requests fail loudly instead of vanishing.
        let pending = completions
        let pendingConfigures = configureCompletions
        completions.removeAll()
        configureCompletions.removeAll()
        for (uuid, completion) in pending {
            completion("disconnected before \(uuid) answered")
        }
        for (uuid, completion) in pendingConfigures {
            completion("disconnected before \(uuid) notification state changed")
        }
    }

    // MARK: - CBPeripheralDelegate (values)

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            let reason = error?.cgmATTDescription ?? "no value"
            deliver("error reading \(characteristic.uuid): \(reason)", for: characteristic.uuid)
            return
        }

        switch characteristic.uuid {
        case ACCharacteristicUUID.controlPoint.cbUUID:
            handleAuthorizationControlPointResponse(data)
        case ACCharacteristicUUID.dataOutIndicate.cbUUID, ACCharacteristicUUID.dataOutNotify.cbUUID:
            handleSecureResponse(data, from: characteristic.uuid)
        case ACCharacteristicUUID.status.cbUUID:
            deliver("ACS status: \(String(describing: ACStatusDataHandler.handleData(data))) Raw Data (Hex): \(data.hexadecimalString)", for: characteristic.uuid)
        default:
            let message = decode(data, for: characteristic.uuid)
            deliver(message + " Raw Data (Hex): \(data.hexadecimalString)", for: characteristic.uuid)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        configureCompletions.removeValue(forKey: characteristic.uuid)?("configured: \(characteristic.isNotifying), error: \(String(describing: error))")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        if let error {
            let message = "\(error.cgmATTDescription) writing \(uuid)"
            switch uuid {
            case ACCharacteristicUUID.controlPoint.cbUUID:
                failHandshake(message)
            case ACCharacteristicUUID.dataIn.cbUUID:
                // The secure request's own completion is keyed by the CGM characteristic it targeted.
                failPendingSecureRequests(message)
            default:
                completions.removeValue(forKey: uuid)?(message)
            }
            return
        }
        // Secure-channel writes are answered through AC Data Out, not by the write response.
        if uuid == ACCharacteristicUUID.dataIn.cbUUID || uuid == ACCharacteristicUUID.controlPoint.cbUUID {
            return
        }

        guard Self.controlPointUUIDs.contains(uuid) else {
            completions.removeValue(forKey: uuid)?("write to \(uuid) succeeded")
            return
        }

        // A control point write is answered by an indication, which consumes the pending completion. The
        // indication can beat the write response, so report the acceptance through whichever path is left.
        let accepted = "write to \(uuid) accepted"
        if let completion = completions[uuid] {
            completion(accepted + ", awaiting indication")
        } else {
            delegate?.characteristicIndicationMessage(uuid, message: accepted)
        }
    }

    private func deliver(_ message: String, for uuid: CBUUID) {
        if let completion = completions.removeValue(forKey: uuid) {
            completion(message)
        } else {
            delegate?.characteristicIndicationMessage(uuid, message: message)
        }
    }

    // MARK: - Decoding

    private func decode(_ data: Data, for uuid: CBUUID) -> String {
        do {
            switch uuid {
            case CGMCharacteristicUUID.feature.cbUUID:
                // Once E2E is known to be on, a corrupted E2E bit cannot switch the CRC check off.
                let feature = try CGMFeature(data: data, e2eCRC: isE2EProtectionSupported)
                self.feature = feature
                return String(describing: feature)
            case CGMCharacteristicUUID.status.cbUUID:
                return String(describing: try CGMStatus(data: data, e2eCRC: isE2EProtectionSupported))
            case CGMCharacteristicUUID.sessionStartTime.cbUUID:
                let startTime = try CGMSessionStartTime(data: data, e2eCRC: isE2EProtectionSupported)
                sessionStartTime = startTime
                return String(describing: startTime)
            case CGMCharacteristicUUID.sessionRunTime.cbUUID:
                return String(describing: try CGMSessionRunTime(data: data, e2eCRC: isE2EProtectionSupported))
            case CGMCharacteristicUUID.measurement.cbUUID:
                let records = try CGMMeasurementRecord.decodeRecords(data, e2eCRC: isE2EProtectionSupported)
                onMeasurement?(records)
                return records.map { String(describing: $0) }.joined(separator: "; ")
            case CGMCharacteristicUUID.recordAccessControlPoint.cbUUID:
                return "RACP \(try CGMRACPResponse(data: data))"
            case CGMCharacteristicUUID.specificOpsControlPoint.cbUUID:
                let response = try CGMSpecificOpsResponse(data: data, e2eCRC: isE2EProtectionSupported)
                onSpecificOpsResponse?(response)
                return "CGMCP \(response)"
            case DeviceInfoCharacteristicUUID.systemID.cbUUID:
                return "System ID \(data.hexadecimalString)"
            case DeviceInfoCharacteristicUUID.manufacturerNameString.cbUUID,
                 DeviceInfoCharacteristicUUID.modelNumberString.cbUUID,
                 DeviceInfoCharacteristicUUID.serialNumberString.cbUUID,
                 DeviceInfoCharacteristicUUID.firmwareRevisionString.cbUUID,
                 DeviceInfoCharacteristicUUID.hardwareRevisionString.cbUUID,
                 DeviceInfoCharacteristicUUID.softwareRevisionString.cbUUID:
                return String(data: data, encoding: .utf8) ?? "invalid UTF-8"
            case BatteryCharacteristicUUID.batteryLevel.cbUUID:
                return "battery \(data.first.map(String.init) ?? "?")%"
            default:
                return "unhandled characteristic \(uuid)"
            }
        } catch {
            return "decode error: \(error)"
        }
    }

    // MARK: - Characteristic access

    private func read(_ characteristic: CBCharacteristic?, key: CBUUID, completion: @escaping MessageCompletion) {
        // CGMS characteristics are protected resources once the secure channel is in use; DIS and Battery stay plain.
        if usesSecureChannel, let cgmUUID = CGMCharacteristicUUID(cbUUID: key) {
            sendSecureRequest(nil, to: cgmUUID, completion: completion)
            return
        }
        guard let characteristic, let connectedPeripheral else {
            completion("Service and characteristic not available")
            return
        }
        completions[key] = completion
        connectedPeripheral.readValue(for: characteristic)
    }

    private func write(_ request: Data, to uuid: CGMCharacteristicUUID, completion: @escaping MessageCompletion) {
        if usesSecureChannel {
            sendSecureRequest(request, to: uuid, completion: completion)
            return
        }
        guard let characteristic = connectedPeripheral?.getCGMCharacteristicWithUUID(uuid), let connectedPeripheral else {
            completion("Service and characteristic not available")
            return
        }
        completions[uuid.cbUUID] = completion
        connectedPeripheral.writeValue(request, for: characteristic, type: .withResponse)
    }

    func configureNotifications(_ uuid: CGMCharacteristicUUID, enabled: Bool, completion: @escaping MessageCompletion) {
        guard let characteristic = connectedPeripheral?.getCGMCharacteristicWithUUID(uuid), let connectedPeripheral else {
            completion("Service and characteristic not available")
            return
        }
        configureCompletions[uuid.cbUUID] = completion
        connectedPeripheral.setNotifyValue(enabled, for: characteristic)
    }

    // MARK: - Reads

    func readFeature(completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getCGMCharacteristicWithUUID(.feature), key: CGMCharacteristicUUID.feature.cbUUID, completion: completion)
    }

    func readStatus(completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getCGMCharacteristicWithUUID(.status), key: CGMCharacteristicUUID.status.cbUUID, completion: completion)
    }

    func readSessionStartTime(completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getCGMCharacteristicWithUUID(.sessionStartTime), key: CGMCharacteristicUUID.sessionStartTime.cbUUID, completion: completion)
    }

    func readSessionRunTime(completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getCGMCharacteristicWithUUID(.sessionRunTime), key: CGMCharacteristicUUID.sessionRunTime.cbUUID, completion: completion)
    }

    func readDeviceInformation(_ uuid: DeviceInfoCharacteristicUUID, completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getDISCharacteristicWithUUID(uuid), key: uuid.cbUUID, completion: completion)
    }

    func readBatteryLevel(completion: @escaping MessageCompletion) {
        read(connectedPeripheral?.getBatteryCharacteristicWithUUID(.batteryLevel), key: BatteryCharacteristicUUID.batteryLevel.cbUUID, completion: completion)
    }

    // MARK: - Writes

    /// CGMS §3.4.1: write the collector's current time; the sensor derives the session start from it.
    func writeSessionStartTime(_ date: Date = Date(), timeZone: TimeZone = .current, completion: @escaping MessageCompletion) {
        let startTime = CGMSessionStartTime(date: date, timeZone: timeZone)
        write(startTime.encoded(e2eCRC: isE2EProtectionSupported), to: .sessionStartTime, completion: completion)
    }

    /// Operand-free CGMCP procedure (Start Session, Get …, Reset Device Specific Alert).
    func sendSpecificOpsRequest(_ opcode: CGMSpecificOpsOpcode, completion: @escaping MessageCompletion) {
        sendSpecificOpsRequest(CGMSpecificOpsRequest.encode(opcode, e2eCRC: isE2EProtectionSupported), completion: completion)
    }

    /// A fully encoded CGMCP request, built with `CGMSpecificOpsRequest` using `isE2EProtectionSupported`.
    func sendSpecificOpsRequest(_ request: Data, completion: @escaping MessageCompletion) {
        write(request, to: .specificOpsControlPoint, completion: completion)
    }

    func sendRACPRequest(_ request: CGMRACPRequest, completion: @escaping MessageCompletion) {
        write(request.encoded(), to: .recordAccessControlPoint, completion: completion)
    }
}

// MARK: - Authorization Control handshake and secure channel

extension CGMCollectorController: SecurityManagerDelegate {
    /// Subscribes to the ACS characteristics, then runs the configuration reads and the ECDH key exchange.
    /// BluetoothCommonKit queues the follow-up requests itself; this just feeds them one at a time.
    func establishSecureSession(completion: @escaping MessageCompletion) {
        guard let peripheral = connectedPeripheral else {
            completion("not connected")
            return
        }
        guard peripheral.getACSCharacteristicWithUUID(.controlPoint) != nil else {
            completion("sensor does not offer the Authorization Control service")
            return
        }
        guard handshakeCompletion == nil else {
            completion("key exchange already in progress")
            return
        }
        handshakeCompletion = completion
        subscribeAuthorizationControl([.status, .controlPoint, .dataOutIndicate, .dataOutNotify][...]) { [weak self] in
            guard let self else { return }
            self.authorizationControlPoint.queueConfigurationRequests()
            self.sendNextAuthorizationRequest()
        }
    }

    /// Asks the sensor to drop the current key; the client forgets it when the response is Success.
    func invalidateKey(completion: @escaping MessageCompletion) {
        guard isSecurityEstablished else {
            completion("no secure session to invalidate")
            return
        }
        handshakeCompletion = completion
        authorizationControlPoint.queueInvalidateKeyRequest()
        sendNextAuthorizationRequest()
    }

    private func subscribeAuthorizationControl(_ uuids: ArraySlice<ACCharacteristicUUID>, then: @escaping () -> Void) {
        guard let uuid = uuids.first else {
            then()
            return
        }
        guard let characteristic = connectedPeripheral?.getACSCharacteristicWithUUID(uuid), let peripheral = connectedPeripheral else {
            failHandshake("Authorization Control characteristic \(uuid.name) not available")
            return
        }
        if characteristic.isNotifying {
            subscribeAuthorizationControl(uuids.dropFirst(), then: then)
            return
        }
        configureCompletions[uuid.cbUUID] = { [weak self] _ in
            self?.subscribeAuthorizationControl(uuids.dropFirst(), then: then)
        }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    private func sendNextAuthorizationRequest() {
        guard !authorizationControlPoint.procedureRunning else { return }
        guard let (request, _) = authorizationControlPoint.nextRequestToSend() else {
            finishHandshake()
            return
        }
        guard let characteristic = connectedPeripheral?.getACSCharacteristicWithUUID(.controlPoint), let peripheral = connectedPeripheral else {
            failHandshake("Authorization Control Point not available")
            return
        }
        authorizationControlPoint.procedureRunning = true
        for segment in authorizationControlPoint.segmentPayload(request) {
            peripheral.writeValue(segment, for: characteristic, type: .withResponse)
        }
    }

    private func handleAuthorizationControlPointResponse(_ data: Data) {
        let (result, _) = authorizationControlPoint.handleSegmentedResponse(data)
        switch result {
        case .success:
            ConsoleOut.shared.logMessage(message: "ACCP response: \(result)")
            sendNextAuthorizationRequest()
        case .failure(let error):
            if case .partialResponse = error { return }
            failHandshake("key exchange failed: \(error)")
        }
    }

    private func finishHandshake() {
        guard let completion = handshakeCompletion else { return }
        handshakeCompletion = nil
        if isSecurityEstablished {
            usesSecureChannel = true
            completion("secure session established; CGM traffic now uses the secure channel")
        } else {
            usesSecureChannel = false
            completion("done; no secure session (key invalidated or exchange incomplete)")
        }
        onSecurityStateChange?()
    }

    private func failHandshake(_ message: String) {
        _ = authorizationControlPoint.getPendingProceduresAndReset()
        let completion = handshakeCompletion
        handshakeCompletion = nil
        completion?(message)
        onSecurityStateChange?()
    }

    /// Encrypts `request` (nil = read) for the protected characteristic and writes it to AC Data In. The
    /// answer arrives on AC Data Out and is delivered under the characteristic's own UUID.
    private func sendSecureRequest(_ request: Data?, to uuid: CGMCharacteristicUUID, completion: @escaping MessageCompletion) {
        guard let handle = authorizationControlPoint.uuidToHandleMap[uuid.cbUUID] else {
            completion("no resource handle for \(uuid.name); establish the secure session first")
            return
        }
        guard let dataIn = connectedPeripheral?.getACSCharacteristicWithUUID(.dataIn), let peripheral = connectedPeripheral else {
            completion("AC Data In not available")
            return
        }
        switch authorizationData.prepareSecureRequestSegments(request, resourceHandle: handle) {
        case .success(let segments):
            completions[uuid.cbUUID] = completion
            for segment in segments {
                peripheral.writeValue(segment, for: dataIn, type: .withResponse)
            }
        case .failure(let error):
            completion("could not protect request for \(uuid.name): \(error)")
        }
    }

    private func handleSecureResponse(_ data: Data, from source: CBUUID) {
        switch authorizationData.handleSecureResponse(data) {
        case .success(let resource):
            guard let uuid = authorizationControlPoint.uuidToHandleMap.first(where: { $0.value == resource.resourceHandle })?.key else {
                deliver("secure response for unknown resource handle \(resource.resourceHandle)", for: source)
                return
            }
            // Refusals arrive as ATT errors on the AC Data In write (see didWriteValueFor), so anything
            // decrypted here is a real value.
            let message = decode(resource.response, for: uuid)
            deliver("(secure) " + message + " Raw Data (Hex): \(resource.response.hexadecimalString)", for: uuid)
        case .failure(let error):
            if case .partialResponse = error { return }
            deliver("secure response error: \(error)", for: source)
        }
    }

    private func failPendingSecureRequests(_ message: String) {
        let pending = completions.filter { CGMCharacteristicUUID(cbUUID: $0.key) != nil }
        for (uuid, completion) in pending {
            completions.removeValue(forKey: uuid)
            completion(message)
        }
    }

    // MARK: SecurityManagerDelegate

    func securityManagerDidEstablishedSecurity(_ securityManager: SecurityManager) {
        ConsoleOut.shared.logMessage(message: "\(#function)")
    }

    func securityManagerDidUpdateConfiguration(_ securityManager: SecurityManager) { }
}

private extension CGMCharacteristicUUID {
    init?(cbUUID: CBUUID) {
        self.init(rawValue: cbUUID.uuidString.lowercased())
    }
}
