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

    private static let controlPointUUIDs: Set<CBUUID> = [
        CGMCharacteristicUUID.recordAccessControlPoint.cbUUID,
        CGMCharacteristicUUID.specificOpsControlPoint.cbUUID
    ]

    init() {
        super.init(
            scanServiceUUIDs: [CGMCharacteristicUUID.service.cbUUID],
            discoveredServiceUUIDs: [
                CGMCharacteristicUUID.service.cbUUID,
                DeviceInfoCharacteristicUUID.service.cbUUID,
                BatteryCharacteristicUUID.service.cbUUID
            ]
        )
    }

    // MARK: - PeripheralController hooks

    override func peripheralDidDiscoverCharacteristics(_ characteristics: [CBCharacteristic], for service: CBService, on peripheral: CBPeripheral) {
        // CGMS §3.1: Feature must be read before anything else can be interpreted (E2E-CRC presence).
        guard service.uuid == CGMCharacteristicUUID.service.cbUUID,
              let featureCharacteristic = characteristics.first(where: { $0.uuid == CGMCharacteristicUUID.feature.cbUUID })
        else { return }
        peripheral.readValue(for: featureCharacteristic)
    }

    override func peripheralDidDisconnect() {
        feature = nil
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
            deliver("error reading \(characteristic.uuid): \(String(describing: error))", for: characteristic.uuid)
            return
        }

        let message = decode(data, for: characteristic.uuid)
        deliver(message + " Raw Data (Hex): \(data.hexadecimalString)", for: characteristic.uuid)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        configureCompletions.removeValue(forKey: characteristic.uuid)?("configured: \(characteristic.isNotifying), error: \(String(describing: error))")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        if let error {
            let code = (error as NSError).code
            completions.removeValue(forKey: uuid)?("ATT error \(code) (0x\(String(code, radix: 16))) writing \(uuid): \(error.localizedDescription)")
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
                return String(describing: try CGMSessionStartTime(data: data, e2eCRC: isE2EProtectionSupported))
            case CGMCharacteristicUUID.sessionRunTime.cbUUID:
                return String(describing: try CGMSessionRunTime(data: data, e2eCRC: isE2EProtectionSupported))
            case CGMCharacteristicUUID.measurement.cbUUID:
                let records = try CGMMeasurementRecord.decodeRecords(data, e2eCRC: isE2EProtectionSupported)
                onMeasurement?(records)
                return records.map { String(describing: $0) }.joined(separator: "; ")
            case CGMCharacteristicUUID.recordAccessControlPoint.cbUUID:
                return "RACP \(try CGMRACPResponse(data: data))"
            case CGMCharacteristicUUID.specificOpsControlPoint.cbUUID:
                return "CGMCP \(try CGMSpecificOpsResponse(data: data, e2eCRC: isE2EProtectionSupported))"
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
        guard let characteristic, let connectedPeripheral else {
            completion("Service and characteristic not available")
            return
        }
        completions[key] = completion
        connectedPeripheral.readValue(for: characteristic)
    }

    private func write(_ request: Data, to uuid: CGMCharacteristicUUID, completion: @escaping MessageCompletion) {
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
