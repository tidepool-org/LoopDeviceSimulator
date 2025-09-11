//
//  InsulinDeliveryController.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

typealias MessageCompletion = (String) -> Void

public protocol InsulinDeliveryControllerDelegate: AnyObject {
    func peripheralDiscovered(sender: InsulinDeliveryController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber)
    func connectedToPeripheral(sender: InsulinDeliveryController)
    func didDisconnectFromPeripheral(sender: InsulinDeliveryController)
    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String)
}

public class InsulinDeliveryController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    public weak var delegate: InsulinDeliveryControllerDelegate?
    var peripheralArray: [CBPeripheral] = [CBPeripheral]()
    var centralManager: CBCentralManager?
    var connectedPeripheral: CBPeripheral?
    let statusReaderControlPoint: IDStatusReaderControlPointDataHandler
    let commandControlPoint: IDCommandControlPointDataHandler
    let racp: IDRecordAccessControlPointDataHandler
    let deviceTime: DeviceTimeDataHandler
    let deviceTimeControlPoint: DTControlPointDataHandler
    let basalManager: BasalManager
    let bolusManager: BolusManager
    var requestArray = Array<Data>()
    var willAbort = false
    var completion: MessageCompletion?
    var features: IDFeatureFlag = []
    var basalProfile: [BasalSegment] = [
        BasalSegment(index: 1, rate: 1.1, duration: .minutes(240)),
        BasalSegment(index: 2, rate: 1.2, duration: .minutes(240)),
        BasalSegment(index: 3, rate: 1.3, duration: .minutes(240)),
        BasalSegment(index: 4, rate: 1.4, duration: .minutes(240)),
        BasalSegment(index: 5, rate: 1.5, duration: .minutes(240)),
        BasalSegment(index: 6, rate: 1.6, duration: .minutes(240))
    ]
    
    override init() {
        basalManager = BasalManager()
        bolusManager = BolusManager()
        statusReaderControlPoint = IDStatusReaderControlPointDataHandler(bolusManager: bolusManager, basalManager: basalManager)
        commandControlPoint = IDCommandControlPointDataHandler(bolusManager: bolusManager, basalManager: basalManager)
        racp = IDRecordAccessControlPointDataHandler()
        deviceTime = DeviceTimeDataHandler()
        deviceTimeControlPoint = DTControlPointDataHandler()
        
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        basalManager.delegate = self
        bolusManager.delegate = self
        statusReaderControlPoint.e2eDelegate = self
        commandControlPoint.e2eDelegate = self
        racp.e2eDelegate = self
        deviceTime.e2eDelegate = self
        deviceTimeControlPoint.e2eDelegate = self
    }
    
    func scanForPeripherals() {
        self.centralManager?.stopScan()
        self.peripheralArray.removeAll()
        self.centralManager?.scanForPeripherals(withServices: [InsulinDeliveryCharacteristicUUID.service.cbUUID])
    }
    
    func disconnectFromPeripheral() {
        guard let connectedPeripheral = connectedPeripheral else { return }
        self.centralManager?.cancelPeripheralConnection(connectedPeripheral)
    }
    
    func isScanning() -> Bool {
        self.centralManager?.isScanning ?? false
    }
    
    func connectToPeripheralAtIndex(index: Int) {
        let peripheral = self.peripheralArray[index]
        self.connectedPeripheral = peripheral
        self.connectedPeripheral?.delegate = self
        centralManager?.stopScan()
        centralManager?.connect(self.connectedPeripheral!)
    }

    func connectToPeripheralWithUUID(uuid: UUID) {
        let peripheral = self.peripheralArray.first(where: { $0.identifier == uuid })
        self.connectedPeripheral = peripheral
        self.connectedPeripheral?.delegate = self
        centralManager?.stopScan()
        centralManager?.connect(self.connectedPeripheral!)
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("central.state is .unknown")
        case .resetting:
            print("central.state is .resetting")
        case .unsupported:
            print("central.state is .unsupported")
        case .unauthorized:
            print("central.state is .unauthorized")
        case .poweredOff:
            print("central.state is .poweredOff")
        case .poweredOn:
            print("central.state is .poweredOn")
            centralManager?.scanForPeripherals(withServices: [InsulinDeliveryCharacteristicUUID.service.cbUUID])
        @unknown default:
            fatalError("unknown central state")
        }

        guard connectedPeripheral?.state != .connected else { return }
        delegate?.didDisconnectFromPeripheral(sender: self)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(peripheral, " AD data: ", advertisementData, " services: ", peripheral.services as Any)
        guard let peripheralName = peripheral.name else { return }
        self.delegate?.peripheralDiscovered(sender: self, peripheralID: peripheral.identifier, peripheralName: peripheralName, advertisingName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "unknown", serviceData: advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? nil, rssi: RSSI)
        self.peripheralArray.append(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected!")
        self.connectedPeripheral?.discoverServices([InsulinDeliveryCharacteristicUUID.service.cbUUID, DeviceTimeCharacteristicUUID.service.cbUUID, ImmediateAlertCharacteristicUUID.service.cbUUID])
        self.delegate?.connectedToPeripheral(sender: self)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.connectedPeripheral = nil
        self.peripheralArray.removeAll()
        self.centralManager?.scanForPeripherals(withServices: [InsulinDeliveryCharacteristicUUID.service.cbUUID])
        self.delegate?.didDisconnectFromPeripheral(sender: self)
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("\(#function) services: \(String(describing: peripheral.services))")
        guard let services = peripheral.services else { return }

        for service in services {
            print(service)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("modified services: ", invalidatedServices)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print(characteristic)
            if characteristic.properties.contains(.read) {
                print("\(characteristic.uuid): properties contains .read")
            }
            if characteristic.properties.contains(.notify) {
                print("\(characteristic.uuid): properties contains .notify")
            }
            if characteristic.properties.contains(.indicate) {
                print("\(characteristic.uuid): properties contains .indicate")
            }
            if characteristic.properties.contains(.write) {
                print("\(characteristic.uuid): properties contains .write")
            }
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        ConsoleOut.shared.logMessage(message: "\(#function) characteristic value \(String(describing: characteristic.value)), error \(String(describing: error))")
        guard let characteristicData = characteristic.value
        else {
            completion?("Characteristic value error: \(String(describing: error))")
            completion = nil
            return
        }

        print("Characteristic \(characteristic.uuid) value: \(characteristicData.hexadecimalString)")

        guard error == nil
        else {
            completion?("error \(String(describing: error))")
            completion = nil
            return
        }

        // handle response
        var message: String = ""
        switch characteristic.uuid {
        case InsulinDeliveryCharacteristicUUID.features.cbUUID:
            print("Data from feature characteristic")
            let result = IDFeatureDataHandlerEnhancement.handleData(characteristicData)
            switch result {
            case .success((_ , let features)):
                self.features = features
            default:
                break
            }
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case InsulinDeliveryCharacteristicUUID.status.cbUUID:
            print("Data from status characteristic")
            let result = IDStatusDataHandler.handleData(characteristicData, e2eProtectionSupported: isE2EProtectionSupported)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
            delegate?.characteristicIndicationMessage(characteristic.uuid, message: message)
            return
        case InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID:
            print("Data from status changed characteristic")
            let result = IDStatusChangedDataHandlerEnhancement.handleData(characteristicData, e2eProtectionSupported: isE2EProtectionSupported)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
            delegate?.characteristicIndicationMessage(characteristic.uuid, message: message)
            return
        case InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID:
            print("Data from annunciation status characteristic")
            let result = IDAnnunciationStatusDataHandler.handleData(characteristicData, e2eProtectionSupported: isE2EProtectionSupported)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
            delegate?.characteristicIndicationMessage(characteristic.uuid, message: message)
            return
        case InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID:
            print("Data from status reader control point")
            let result = statusReaderControlPoint.handleResponse(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID:
            print("Data from command control point")
            let result = commandControlPoint.handleResponse(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case InsulinDeliveryCharacteristicUUID.commandData.cbUUID:
            print("Data from command data")
            let result = commandControlPoint.handleCommandDataResponse(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID:
            print("Data from record access control point")
            let result = racp.handleResponse(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case InsulinDeliveryCharacteristicUUID.historyData.cbUUID:
            print("Data from history data")
            let result = IDHistoryDataHandler.handleData(characteristicData, e2eProtectionSupported: isE2EProtectionSupported)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case DeviceTimeCharacteristicUUID.deviceTime.cbUUID:
            print("Data from device time")
            let result = deviceTime.handleData(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case DeviceTimeCharacteristicUUID.controlPoint.cbUUID:
            print("Data from device time control point")
            let result = deviceTimeControlPoint.handleResponse(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        default:
            print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }

        if let completion = completion {
            completion(message)
        } else {
            delegate?.characteristicIndicationMessage(characteristic.uuid, message: message)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("notification/indication configured for \(characteristic.uuid): \(characteristic.isNotifying)")
        completion?("configured: \(characteristic.isNotifying), error: \(String(describing: error))")
        completion = nil
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        var message: String?
        if error != nil {
            if let nsError = error as NSError? {
                let cbError = CBATTError(_nsError: nsError)
                if characteristic.uuid == InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID && cbError.code.rawValue == CBATTError.Code.commandNotSupported.rawValue {
                    message = "ATT Error: Command not supported (\(cbError.code.rawValue))"
                } else {
                    if cbError.code.rawValue == CBATTError.Code.imporperlyConfigured.rawValue {
                        message = "ATT Error: Client Characteristic Configuration Descriptor Imporperly Configured (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.procedureAlreadyInProgress.rawValue {
                        message = "ATT Error: Procedure Already In Progress (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.outOfRange.rawValue {
                        message = "ATT Error: Out Of Range (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.commandNotSupported.rawValue {
                        message = "ATT Error: Command not supported Time Format (\(cbError.code.rawValue))"
                    }
                }
            }
        }
        completion?("\(#function) " + (message ?? "error: " + error.debugDescription))
    }
    
    // MARK: - Characteristic
    
    func readCharacteristic(uuid: CBUUID, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        connectedPeripheral?.readValue(for: characteristic)
        self.completion = completion
    }
    
    func writeCharacteristic(uuid: CBUUID, request: Data, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }
}
    
// MARK: - Configure Characteristic
extension InsulinDeliveryController {
    func configureIDDStatusIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.status.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDStatusChangedIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDAnnunciationStatusIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDStatusReaderControlPointIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDCommandControlPointIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDCommandDataIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.commandData.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDRecordAccessControlPointIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIDDHistoryDataIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: InsulinDeliveryCharacteristicUUID.historyData.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIndications(uuid: CBUUID, enabled: Bool = true, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        
        connectedPeripheral?.setNotifyValue(enabled, for: characteristic)
        self.completion = completion
    }
    
    func configureDeviceTimeControlPointIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureDeviceTimeIndications(uuid: DeviceTimeCharacteristicUUID.controlPoint.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureDeviceTimeIndications(uuid: CBUUID, enabled: Bool = true, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == DeviceTimeCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        
        connectedPeripheral?.setNotifyValue(enabled, for: characteristic)
        self.completion = completion
    }
}

// MARK: - Read Characteistics
extension InsulinDeliveryController {
    func readIDDFeatureCharacteristic(completion: @escaping MessageCompletion) {
        readCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.features.cbUUID, completion: completion)
    }
    
    func readIDDStatusCharacteristic(completion: @escaping MessageCompletion) {
        readCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.status.cbUUID, completion: completion)
    }
    
    func readIDDStatusChangedCharacteristic(completion: @escaping MessageCompletion) {
        readCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID, completion: completion)
    }
    
    func readIDDAnnunciationStatusCharacteristic(completion: @escaping MessageCompletion) {
        readCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID, completion: completion)
    }
}

// MARK: - Device Time
extension InsulinDeliveryController {
    func readDeviceTimeCharacteristic(completion: @escaping MessageCompletion) {
        readDTCharacteristic(uuid: DeviceTimeCharacteristicUUID.deviceTime.cbUUID, completion: completion)
    }
    
    func readDTCharacteristic(uuid: CBUUID, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == DeviceTimeCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        connectedPeripheral?.readValue(for: characteristic)
        self.completion = completion
    }
    
    func setDeviceTime(completion: @escaping MessageCompletion) {
        let request = deviceTimeControlPoint.createProposeTimeUpdateRequest(using: TimeZone.current)
        sendDeviceTimeControlPointRequest(request: request, completion: completion)
    }
    
    func sendDeviceTimeControlPointRequest(request: Data, completion: @escaping MessageCompletion) {
        writeDeviceTimeCharacteristic(uuid: DeviceTimeCharacteristicUUID.controlPoint.cbUUID, request: request, completion: completion)
    }
    
    func writeDeviceTimeCharacteristic(uuid: CBUUID, request: Data, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == DeviceTimeCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }
}

// MARK: - Immediate Alert
extension InsulinDeliveryController {
    func playBeepSound(completion: @escaping MessageCompletion) {
        let request = ImmediateAlertService.createBeepRequest()
        writeImmediateAlertCharacteristic(uuid: ImmediateAlertCharacteristicUUID.alertLevel.cbUUID, request: request, completion: completion)
    }
    
    func writeImmediateAlertCharacteristic(uuid: CBUUID, request: Data, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == ImmediateAlertCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withoutResponse)
        self.completion = completion
    }
}

// MARK: - Status Reader Control Point
extension InsulinDeliveryController {
    func resetStatus(_ flags: IDStatusChangedFlag, completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createResetStatusChangedRequest(for: flags)
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getActiveBolusIDs(_ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetActiveBolusIDsRequest()
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getActiveBolusDelivery(_ bolusID: BolusID, valueSelection: BolusValueSelection, completion: @escaping MessageCompletion) {
        let request = bolusManager.createGetActiveBolusDeliveryRequest(for: bolusID, bolusValueSelection: valueSelection)
        bolusManager.sendingActiveBolusRequest(valueSelection)
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getActiveBasalRateDelivery(_ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetActiveBasalRateDeliveryRequest()
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getTotalDailyInsulinStatus(_ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetTotalDailyInsulinStatusRequest()
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getCounter(for counterType: CounterType, valueSelection: CounterValueSelection, _ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetCounterRequest(for: counterType, counterValueSelection: valueSelection)
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }
    
    func getDeliveredInsulin(_ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetDeliveredInsulinRequest()
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }

    func getInsulinOnBoard(_ completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetInsulinOnBoardRequest()
        sendStatusReaderControlPointRequest(request: request, completion: completion)
    }

    func getSelectedStatus(_ selectedStatusFlags: IDSelectedStatusFlag, completion: @escaping MessageCompletion) {
        let request = statusReaderControlPoint.createGetSelectedStatusInformationRequest(selectedStatusFlags)
        writeCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID, request: request, completion: completion)
    }
    
    func sendStatusReaderControlPointRequest(request: Data, completion: @escaping MessageCompletion) {
        var request = request
        if isE2EProtectionSupported {
            request = request.appendingCRC()
        }
        writeCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID, request: request, completion: completion)
    }
}

extension IDStatusReaderControlPointDataHandler {
    func createGetSelectedStatusInformationRequest(_ selectedStatusFlags: IDSelectedStatusFlag) -> Data {
        buildRequest(.getSelectedStatusInformation, operand: Data(selectedStatusFlags.rawValue))
    }
}

// MARK: - Command Control Point
extension InsulinDeliveryController {
    func setTherapyControlState(_ therapyControlState: InsulinTherapyControlState, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetTherapyControlStateRequest(therapyControlState)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func setFlightMode(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetFlightModeRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func snoozeAnnunciation(_ annunciationID: AnnunciationIdentifier, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSnoozeAnnunciationRequest(for: annunciationID)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func confirmAnnunciation(_ annunciationID: AnnunciationIdentifier, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createConfirmAnnunciationRequest(for: annunciationID)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func readBasalProfile(_ profileNumber: UInt8, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createReadBasalRateProfileRequest(for: profileNumber)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func writeBasalProfile(_ profileNumber: UInt8, completion: @escaping MessageCompletion) {
        commandControlPoint.queueWriteBasalProfileRequests(for: basalProfile)
        completion("basalProfile \(basalProfile)")
        let groupsOfBasalSegments: [[BasalSegment]] = basalProfile.chunked(into: 3)
        groupsOfBasalSegments.enumerated().forEach { (index, basalSegments) in
            let isLast = index == groupsOfBasalSegments.count-1
            let request = commandControlPoint.createWriteBasalRateSegmentsRequest(for: basalSegments,
                                                                                  templateNumber: profileNumber,
                                                                                  isLast: isLast)
            sendCommandControlPointRequest(request: request, completion: completion)
        }
    }
    
    func setTempBasal(_ amount: Double, replaceExisting: Bool, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetTempBasalRequest(unitsPerHour: amount, durationInMinutes: 30, deliveryContext: .deviceBased, replaceExisting: replaceExisting)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func cancelTempBasal(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createCancelTempBasalRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func setBolus(_ amount: Double, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetBolusRequest(for: amount, activationType: .manualBolus)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func cancelBolus(with bolusID: BolusID, completion: @escaping MessageCompletion) {
        let request = bolusManager.createCancelBolusRequest(for: bolusID)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func getAvailableBoluses(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createGetAvailableBolusesRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func getTemplateStatusDetails(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createGetTemplateStatusDetailsRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func resetTemplateStatus(_ templateNumbers: [TemplateNumber], completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createDeactivateProfileTemplatesRequest(for: templateNumbers)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func activateProfileTemplates(_ templateNumbers: [TemplateNumber], completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createActivateProfileTemplatesRequest(for: templateNumbers)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func getActivatedProfiles(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createGetActivatedProfileTemplates()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func startPriming(amount: Double, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createStartPrimingRequest(amount)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func stopPriming(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createStopPrimingRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func setInitialReservoirFillLevel(_ fillLevel: Int, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetInitialReservoirFillLevelRequest(fillLevel)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func getMaxBolusAmount(completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createGetMaxBolusAmountRequest()
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func setMaxBolusAmount(_ amount: Double, completion: @escaping MessageCompletion) {
        let request = commandControlPoint.createSetMaxBolusAmountRequest(amount)
        sendCommandControlPointRequest(request: request, completion: completion)
    }
    
    func sendCommandControlPointRequest(request: Data, completion: @escaping MessageCompletion) {
        var request = request
        if isE2EProtectionSupported {
            request = request.appendingCRC()
        }
        writeCharacteristic(uuid: InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID, request: request, completion: completion)
    }
}

// MARK: - RACP
extension InsulinDeliveryController {
    func requestStoredRecords(racpOperator: IDRACPOperator, minRecordNumber: RecordNumber?, maxRecordNumber: RecordNumber?, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID})
        else {
            completion("Service and characteristic not available")
            return
        }

        let request: Data
        switch racpOperator {
        case .nullOperator:
            completion("Cannot use the Null Operator for requesting number of stored records")
            return
        case .allRecords:
            request = racp.createGetAllStoredRecordsRequest()
        case .lessThanOrEqualTo:
            guard let maxRecordNumber = maxRecordNumber else {
                completion("Request stored records less than or equal to requires a max record number")
                return
            }

            request = racp.createGetAllStoredRecordsRequest(beforeIncludingRecordNumber: maxRecordNumber)
        case .greaterThanOrEqualTo:
            guard let minRecordNumber = minRecordNumber else {
                completion("Request stored records less than or equal to requires a min record number")
                return
            }
            request = racp.createGetAllStoredRecordsRequest(afterIncludingRecordNumber: minRecordNumber)
        case .inclusiveRange:
            guard let maxRecordNumber = maxRecordNumber,
                  let minRecordNumber = minRecordNumber
            else {
                completion("Request stored records less than or equal to requires both a min and max record number")
                return
            }
            request = racp.createGetAllStoredRecordsInclusiveRangeRequest(minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber)
        case .lastRecord:
            request = racp.createGetMostCurrentStoredRecordRequest()
        case .firstRecord:
            request = racp.createOldestStoredRecordRequest()
        }

        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }

    func deleteStoredRecords(racpOperator: IDRACPOperator, minRecordNumber: RecordNumber?, maxRecordNumber: RecordNumber?, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID})
        else {
            completion("Service and characteristic not available")
            return
        }


        switch racpOperator {
        case .nullOperator:
            completion("Cannot use the Null Operator for deleting stored records")
            return
        case .lessThanOrEqualTo:
            guard maxRecordNumber != nil else {
                completion("Request delete stored records less than or equal to requires a max record number")
                return
            }
        case .greaterThanOrEqualTo:
            guard minRecordNumber != nil else {
                completion("Request delete stored records less than or equal to requires a min record number")
                return
            }
        case .inclusiveRange:
            guard maxRecordNumber != nil,
                  minRecordNumber != nil
            else {
                completion("Request delete stored records less than or equal to requires both a min and max record number")
                return
            }
        default:
            break
        }

        let request = racp.createDeleteStoredRecordsRequest(racpOperator: racpOperator, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber)
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }

    func requestNumberOfStoredRecords(racpOperator: IDRACPOperator, minRecordNumber: RecordNumber?, maxRecordNumber: RecordNumber?, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID})
        else {
            completion("Service and characteristic not available")
            return
        }


        switch racpOperator {
        case .nullOperator:
            completion("Cannot use the Null Operator for requesting stored records")
            return
        case .lessThanOrEqualTo:
            guard maxRecordNumber != nil else {
                completion("Request number of stored records less than or equal to requires a max record number")
                return
            }
        case .greaterThanOrEqualTo:
            guard minRecordNumber != nil else {
                completion("Request number of stored records less than or equal to requires a min record number")
                return
            }
        case .inclusiveRange:
            guard maxRecordNumber != nil,
                  minRecordNumber != nil
            else {
                completion("Request number of stored records less than or equal to requires both a min and max record number")
                return
            }
        default:
            break
        }

        let request = racp.createReportNumberOfStoredRecordsRequest(racpOperator: racpOperator, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber)
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }

    func racpAbortOperation(completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID})
        else {
            completion("Service and characteristic not available")
            return
        }

        let request = racp.createAbortProcedureRequest()
        self.connectedPeripheral?.writeValue(request, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        self.completion = completion
    }
}

extension InsulinDeliveryController: BasalManagerDelegate {
    public func basalManagerDidUpdateStatus(_ basalManager: InsulinDeliveryServiceKit.BasalManager) {
        //noop
    }
    
    public func isActiveBasalRate(_ activeBasalRate: Double) -> Bool {
        true
    }
}

extension InsulinDeliveryController: BolusManagerDelegate {
    public func estimatedBolusDelivery(for elapsedTime: TimeInterval) -> Double? {
        2.5 / TimeInterval.minutes(1)
    }
    
    public func bolusManagerDidUpdateActiveBolusDeliveryStatus(_ bolusManager: InsulinDeliveryServiceKit.BolusManager) {
        //noop
    }
}

extension InsulinDeliveryController: E2EProtectionDelegate {
    public var isE2EProtectionSupported: Bool {
        features.contains(.supportedE2EProtection)
    }
}
