//
//  AuthorizationControlController.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit

protocol AuthorizationControlControllerDelegate: AnyObject {
    func peripheralDiscovered(sender: AuthorizationControlController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber)
    func connectedToPeripheral(sender: AuthorizationControlController)
    func didDisconnectFromPeripheral(sender: AuthorizationControlController)
    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String)
}

public class AuthorizationControlController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var delegate: AuthorizationControlControllerDelegate?
    var completion: MessageCompletion?
    
    var peripheralArray: [CBPeripheral] = [CBPeripheral]()
    var centralManager: CBCentralManager?
    var connectedPeripheral: CBPeripheral?
    
    let controlPoint: ACControlPointDataHandler
    let data: ACDataDataHandler
    let maxRequestSize = 19
    let securityManager: SecurityManager
    public var sharedKeyData: Data?
    var uuidToHandleMap: [CBUUID: ResourceHandle] = [:]
    
    override init() {
        securityManager = SecurityManager()
        controlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: maxRequestSize)
        data = ACDataDataHandler(securityManager: securityManager, maxRequestSize: maxRequestSize)
        
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        securityManager.delegate = self
    }
    
    func scanForPeripherals() {
        self.centralManager?.stopScan()
        self.peripheralArray.removeAll()
        self.centralManager?.scanForPeripherals(withServices: [ACCharacteristicUUID.service.cbUUID])
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
            centralManager?.scanForPeripherals(withServices: [ACCharacteristicUUID.service.cbUUID])
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
        self.connectedPeripheral?.discoverServices([ACCharacteristicUUID.service.cbUUID])
        self.delegate?.connectedToPeripheral(sender: self)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.connectedPeripheral = nil
        self.peripheralArray.removeAll()
        self.centralManager?.scanForPeripherals(withServices: [ACCharacteristicUUID.service.cbUUID])
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
        case ACCharacteristicUUID.status.cbUUID:
            print("Data from status characteristic")
            let result = ACStatusDataHandler.handleData(characteristicData)
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case ACCharacteristicUUID.controlPoint.cbUUID:
            print("Data from control point characteristic")
            let (result,_) = controlPoint.handleSegmentedResponse(characteristicData)
            switch result {
            case .success(let responseData):
                if let uuidToHandleMap = responseData as? [CBUUID: UInt16] {
                    self.uuidToHandleMap = uuidToHandleMap
                }
            default:
                break
            }
            message = String(describing: result)
            message.append(" Raw Data (Hex): \(characteristicData.hexadecimalString)")
        case ACCharacteristicUUID.dataOutNotify.cbUUID, ACCharacteristicUUID.dataOutIndicate.cbUUID:
            print("Data from data characteristic")
            let result = data.handleSecureResponse(characteristicData)
            message = String(describing: result)
            switch result {
            case .success(let resourceResponse):
                message.append(" plainText: \(String(describing: String(data: resourceResponse.response, encoding: .utf8)))")
            default:
                break
            }
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
                if characteristic.uuid == ACCharacteristicUUID.controlPoint.cbUUID && cbError.code.rawValue == CBATTError.Code.commandNotSupported.rawValue {
                    message = "ATT Error: Command not supported (\(cbError.code.rawValue))"
                } else {
                    if cbError.code.rawValue == CBATTError.Code.imporperlyConfigured.rawValue {
                        message = "ATT Error: Client Characteristic Configuration Descriptor Imporperly Configured (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.procedureAlreadyInProgress.rawValue {
                        message = "ATT Error: Procedure Already In Progress (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.outOfRange.rawValue {
                        message = "ATT Error: Out Of Range (\(cbError.code.rawValue))"
                    } else if cbError.code.rawValue == CBATTError.Code.incorrectTimeFormat.rawValue {
                        message = "ATT Error: Incorrect Time Format (\(cbError.code.rawValue))"
                    }
                }
            }
        }
        completion?("\(#function) " + (message ?? "error: " + error.debugDescription))
    }
    
    // MARK: - Characteristic
    
    func readCharacteristic(uuid: CBUUID, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == ACCharacteristicUUID.service.cbUUID}),
              let characteristic = service.characteristics?.first(where: {$0.uuid == uuid })
        else {
            completion("Service and characteristic not available")
            return
        }
        connectedPeripheral?.readValue(for: characteristic)
        self.completion = completion
    }
    
    func writeCharacteristic(uuid: CBUUID, request: Data, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == ACCharacteristicUUID.service.cbUUID}),
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
extension AuthorizationControlController {
    func configureACStatusIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: ACCharacteristicUUID.status.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureACControlPointIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: ACCharacteristicUUID.controlPoint.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureACDataOutNotification(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: ACCharacteristicUUID.dataOutNotify.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureACDataOutIndications(enabled: Bool = true, completion: @escaping MessageCompletion) {
        configureIndications(uuid: ACCharacteristicUUID.dataOutIndicate.cbUUID, enabled: enabled, completion: completion)
    }
    
    func configureIndications(uuid: CBUUID, enabled: Bool = true, completion: @escaping MessageCompletion) {
        guard let service = self.connectedPeripheral?.services?.first(where: {$0.uuid == ACCharacteristicUUID.service.cbUUID}),
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
extension AuthorizationControlController {
    func readACStatusCharacteristic(completion: @escaping MessageCompletion) {
        readCharacteristic(uuid: ACCharacteristicUUID.status.cbUUID, completion: completion)
    }
}

// MARK: - Command Control Point
extension AuthorizationControlController {
    func getACSFeatures(completion: @escaping MessageCompletion) {
        let request = controlPoint.createGetACSFeatureRequest()
        sendControlPointRequest(request: request, completion: completion)
    }

    func getResourceHandleToUUIDMap(completion: @escaping MessageCompletion) {
        let request = controlPoint.createGetResourceHandleToUUIDMapRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func getRestrictionMapIDList(completion: @escaping MessageCompletion) {
        let request = controlPoint.createGetRestrictionMapIDListRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func getAllActiveDescriptors(completion: @escaping MessageCompletion) {
        let request = controlPoint.createGetAllActiveDescriptorsRequest()
        sendControlPointRequest(request: request, completion: completion)
    }

    func ecdhConfirmationCode(completion: @escaping MessageCompletion) {
        guard let request = controlPoint.createECDHConfirmationCodeRequest() else {
            completion("cannot make confirmation code request")
            return
        }
        sendControlPointRequest(request: request, completion: completion)
    }
        
    func getATTMTU(completion: @escaping MessageCompletion) {
        let request = controlPoint.createGetATTMTURequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func keyExchangeECDH(completion: @escaping MessageCompletion) {
        guard let request = controlPoint.createECDHPublicKeyRequest() else {
            completion("cannot make ECDH key exchange request")
            return
        }
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func keyExchangeKDF(completion: @escaping MessageCompletion) {
        let request = controlPoint.createKeyExchangeKDFRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func setClientNonceFixed(completion: @escaping MessageCompletion) {
        let request = controlPoint.createSetClientNonceFixedRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
            
    func invalidateKey(completion: @escaping MessageCompletion) {
        let request = controlPoint.createInvalidateKeyRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func startKeyExchange(completion: @escaping MessageCompletion) {
        securityManager.generateKeyPair()
        let request = controlPoint.createStartKeyExchangeRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func ecdhConfirmationRandomNumber(completion: @escaping MessageCompletion) {
        let request = controlPoint.createECDHConfirmationRandomNumberRequest()
        sendControlPointRequest(request: request, completion: completion)
    }
    
    func sendControlPointRequest(request: Data, completion: @escaping MessageCompletion) {
        let segmentedRequests = controlPoint.segmentPayload(request)
        for request in segmentedRequests {
            writeCharacteristic(uuid: ACCharacteristicUUID.controlPoint.cbUUID, request: request, completion: completion)
        }
    }
}

// MARK: - Secure Requeast
extension AuthorizationControlController {
    func sendSecureRequest(completion: @escaping MessageCompletion) {
        let plainText = "This is a test message"
        let requestData = plainText.data(using: .utf8)!
        sendSecureRequestData(request: requestData, completion: completion)
    }
    
    func sendSecureRequestData(request: Data, completion: @escaping MessageCompletion) {
        guard let resourceHandle = uuidToHandleMap.values.first else {
            completion("no resource handle to UUID map available")
            return
        }
        
        let result = data.prepareSecureRequestSegments(request,
                                                       resourceHandle: resourceHandle)
        switch result {
        case .success(let segmentedRequests):
            for request in segmentedRequests {
                writeCharacteristic(uuid: ACCharacteristicUUID.dataIn.cbUUID, request: request, completion: completion)
            }
        case .failure(let error):
            completion("Failed to prepare secure request segments: \(error)")
        }
    }
}

extension AuthorizationControlController: SecurityManagerDelegate {
    public func securityManagerDidEstablishedSecurity(_ securityManager: BluetoothCommonKit.SecurityManager) {
        print("security was established")
    }
    
    public func securityManagerDidUpdateConfiguration(_ securityManager: BluetoothCommonKit.SecurityManager) {
        // nop
    }
}
