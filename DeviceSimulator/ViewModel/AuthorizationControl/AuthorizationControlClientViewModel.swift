//
//  AuthorizationControlClientViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import CoreBluetooth
import BluetoothCommonKit

class AuthorizationControlClientViewModel: ObservableObject {

    private var authorizationControlController: AuthorizationControlController?

    @Published var deviceList: [Device] = []
    
    @Published var connectedDevice: Device? = nil {
        didSet {
            connectedMessage = "Disconnect from \(connectedDevice?.name ?? "Unknown device")"
        }
    }

    @Published var connectedMessage: String = "Currently Disconnected"
    
    @Published var isPeripheralConnected: Bool = false
    
    @Published var ecdhKeyIDString: String = "1" {
        didSet {
            authorizationControlController?.securityManager.configuration.ecdhKeyID = ecdhKeyID
        }
    }
    var ecdhKeyID: KeyID { KeyID(ecdhKeyIDString) ?? 1 }

    @Published var algorithmKeyIDString: String = "2" {
        didSet {
            authorizationControlController?.securityManager.configuration.algorithmKeyID = algorithmKeyID
        }
    }
    var algorithmKeyID: KeyID { KeyID(algorithmKeyIDString) ?? 2 }
    
    @Published var oobRandomNumberString: String = "42" {
        didSet {
            authorizationControlController?.securityManager.configuration.oobRandomNumber = oobRandomNumber
        }
    }
    var oobRandomNumber: Data { oobRandomNumberString.data(using: .utf8)! }

    // MARK: - Configure Characterist
    
    @Published var indicationsEnabledStatus: Bool = false {
        didSet {
            authorizationControlController?.configureACStatusIndications(enabled: indicationsEnabledStatus) { message in
                self.indicationsEnabledMessageStatus = message
            }
        }
    }
    @Published var indicationsMessageStatus: String? = nil
    @Published var indicationsEnabledMessageStatus: String? = nil
    
    @Published var indicationsEnabledControlPoint: Bool = false {
        didSet {
            authorizationControlController?.configureACControlPointIndications(enabled: indicationsEnabledControlPoint) { message in
                self.indicationsEnabledMessageControlPoint = message
            }
        }
    }
    @Published var indicationsEnabledMessageControlPoint: String? = nil
    
    @Published var indicationsEnabledDataOutNotify: Bool = false {
        didSet {
            authorizationControlController?.configureACDataOutNotification(enabled: indicationsEnabledDataOutNotify) { message in
                self.indicationsEnabledMessageDataOutNotify = message
            }
        }
    }
    @Published var indicationsEnabledMessageDataOutNotify: String? = nil
    
    @Published var indicationsEnabledDataOutIndicate: Bool = false {
        didSet {
            authorizationControlController?.configureACDataOutIndications(enabled: indicationsEnabledDataOutIndicate) { message in
                self.indicationsEnabledMessageDataOutIndicate = message
            }
        }
    }
    @Published var indicationsEnabledMessageDataOutIndicate: String? = nil

    // MARK: - Read Characterist
    
    @Published var readMessageACStatusCharacteristic: String? = nil
    
    // MARK: - Command Control Point
    @Published var getAllActiveDescriptorsMessage: String? = nil
    @Published var getResourceHandleToUUIDMapMessage: String? = nil
    @Published var getRestrictionMapIDListMessage: String? = nil
    @Published var getACSFeaturesMessage: String? = nil
    @Published var getATTMTUMessage: String? = nil
    @Published var ecdhConfirmationCodeMessage: String? = nil
    @Published var keyExchangeECDHMessage: String? = nil
    @Published var keyExchangeKDFMessage: String? = nil
    @Published var setClientNonceFixedMessage: String? = nil
    @Published var invalidateKeyMessage: String? = nil
    @Published var startKeyExchangeMessage: String? = nil
    @Published var ecdhConfirmationRandomNumberMessage: String? = nil
    @Published var sendSecureRequestMessage: String? = nil
    
    // Primarily used for testing
    private let dateGenerator: () -> Date
    private var now: Date { dateGenerator() }

    @Published var consoleMessages: String = ""

    init(dateGenerator: @escaping () -> Date = { Date() }) {
        self.dateGenerator = dateGenerator
    }
    
    // MARK: - Peripheral Connection

    func startClient() {
        authorizationControlController = AuthorizationControlController()
        authorizationControlController?.delegate = self
        if let ecdhKeyID = authorizationControlController?.securityManager.configuration.ecdhKeyID {
            self.ecdhKeyIDString = "\(ecdhKeyID)"
        }
        if let algorithmKeyID = authorizationControlController?.securityManager.configuration.algorithmKeyID {
            self.algorithmKeyIDString = "\(algorithmKeyID)"
        }
        authorizationControlController?.securityManager.configuration.oobRandomNumber = oobRandomNumber
    }

    func stopClient() {
        disconnect()
        reset()
        authorizationControlController?.centralManager?.stopScan()
        consoleMessages.removeAll()
        isPeripheralConnected = false
    }

    func connectToDevice(_ device: Device) {
        guard let uuid = UUID(uuidString: device.uuid) else { return }
        connectedDevice = device
        authorizationControlController?.connectToPeripheralWithUUID(uuid: uuid)
    }

    func refreshList() {
        deviceList.removeAll()
        authorizationControlController?.scanForPeripherals()
    }

    func disconnect() {
        authorizationControlController?.disconnectFromPeripheral()
    }
    
    func switchToPeripheralList() {
        isPeripheralConnected = false
    }

    func clearConsole() {
        consoleMessages.removeAll()
    }

    private func reset() {
        indicationsEnabledStatus = false
        indicationsEnabledControlPoint = false
        indicationsEnabledDataOutNotify = false
        indicationsEnabledDataOutIndicate = false
                
        indicationsMessageStatus = nil
        indicationsEnabledMessageStatus = nil
        indicationsEnabledMessageControlPoint = nil
        indicationsEnabledMessageDataOutNotify = nil
        indicationsEnabledMessageDataOutIndicate = nil
        
        readMessageACStatusCharacteristic = nil
        
        getAllActiveDescriptorsMessage = nil
        getResourceHandleToUUIDMapMessage = nil
        getRestrictionMapIDListMessage = nil
        getACSFeaturesMessage = nil
        ecdhConfirmationCodeMessage = nil
        getATTMTUMessage = nil
        keyExchangeECDHMessage = nil
        keyExchangeKDFMessage = nil
        setClientNonceFixedMessage = nil
        invalidateKeyMessage = nil
        startKeyExchangeMessage = nil
        ecdhConfirmationRandomNumberMessage = nil

        sendSecureRequestMessage = nil
        
        refreshList()
    }
}


extension AuthorizationControlClientViewModel: AuthorizationControlControllerDelegate {
    func peripheralDiscovered(sender: AuthorizationControlController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber) {
        let device = Device(name: peripheralName, uuid: peripheralID.uuidString, advertisedName: advertisingName, rssi: rssi, serviceData: serviceData)
        deviceList.append(device)
        deviceList.sort(by: { $0.rssi.compare($1.rssi) == .orderedDescending })
    }

    func connectedToPeripheral(sender: AuthorizationControlController) {
        isPeripheralConnected = true
    }

    func didDisconnectFromPeripheral(sender: AuthorizationControlController) {
        connectedMessage = "Currently disconnected"
        displayMessageInConsole(message: "\(#function) wait for the user to switch back to peripheral view")
    }

    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String) {
        ConsoleOut.shared.logMessage(message: "\(cbUUID) notification/indication: \(message)")
        if cbUUID == ACCharacteristicUUID.status.cbUUID {
            indicationsMessageStatus = message
        }
    }
}

extension AuthorizationControlClientViewModel: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        consoleMessages = message + "\n" + consoleMessages
    }
}

// MARK: - Read Characteristics
extension AuthorizationControlClientViewModel {
    func readACStatusCharacteristic() {
        authorizationControlController?.readACStatusCharacteristic() { message in
            self.readMessageACStatusCharacteristic = message
        }
    }
}

// MARK: - Command Control Point
extension AuthorizationControlClientViewModel {
    func getAllActiveDescriptors() {
        getAllActiveDescriptorsMessage = nil
        authorizationControlController?.getAllActiveDescriptors() { message in
            self.getAllActiveDescriptorsMessage = (self.getAllActiveDescriptorsMessage ?? "") + "\n\n" + message
        }
    }
    
    func getResourceHandleToUUIDMap() {
        getResourceHandleToUUIDMapMessage = nil
        authorizationControlController?.getResourceHandleToUUIDMap() { message in
            self.getResourceHandleToUUIDMapMessage = (self.getResourceHandleToUUIDMapMessage ?? "") + "\n\n" + message
        }
    }
    
    func getRestrictionMapIDList() {
        getRestrictionMapIDListMessage = nil
        authorizationControlController?.getRestrictionMapIDList() { message in
            self.getRestrictionMapIDListMessage = (self.getRestrictionMapIDListMessage ?? "") + "\n\n" + message
        }
    }
    
    func getACSFeatures() {
        getACSFeaturesMessage = nil
        authorizationControlController?.getACSFeatures() { message in
            self.getACSFeaturesMessage = (self.getACSFeaturesMessage ?? "") + "\n\n" + message
        }
    }
    
    func getATTMTU() {
        getATTMTUMessage = nil
        authorizationControlController?.getATTMTU() { message in
            self.getATTMTUMessage = (self.getATTMTUMessage ?? "") + "\n\n" + message
        }
    }
    
    func ecdhConfirmationCode() {
        ecdhConfirmationCodeMessage = nil
        authorizationControlController?.ecdhConfirmationCode() { message in
            self.ecdhConfirmationCodeMessage = (self.ecdhConfirmationCodeMessage ?? "") + "\n\n" + message
        }
    }
    
    func keyExchangeECDH() {
        keyExchangeECDHMessage = nil
        authorizationControlController?.keyExchangeECDH() { message in
            self.keyExchangeECDHMessage = (self.keyExchangeECDHMessage ?? "") + "\n\n" + message
        }
    }
    
    func keyExchangeKDF() {
        keyExchangeKDFMessage = nil
        authorizationControlController?.keyExchangeKDF() { message in
            self.keyExchangeKDFMessage = (self.keyExchangeKDFMessage ?? "") + "\n\n" + message
        }
    }
    
    func setClientNonceFixed() {
        setClientNonceFixedMessage = nil
        authorizationControlController?.setClientNonceFixed() { message in
            self.setClientNonceFixedMessage = (self.setClientNonceFixedMessage ?? "") + "\n\n" + message
        }
    }
    
    func invalidateKey() {
        invalidateKeyMessage = nil
        authorizationControlController?.invalidateKey() { message in
            self.invalidateKeyMessage = (self.invalidateKeyMessage ?? "") + "\n\n" + message
        }
    }
    
    func startKeyExchange() {
        startKeyExchangeMessage = nil
        authorizationControlController?.startKeyExchange() { message in
            self.startKeyExchangeMessage = (self.startKeyExchangeMessage ?? "") + "\n\n" + message
        }
    }
    
    func ecdhConfirmationRandomNumber() {
        ecdhConfirmationRandomNumberMessage = nil
        authorizationControlController?.ecdhConfirmationRandomNumber() { message in
            self.ecdhConfirmationRandomNumberMessage = (self.ecdhConfirmationRandomNumberMessage ?? "") + "\n\n" + message
        }
    }
}

// MARK: - Secure Request
extension AuthorizationControlClientViewModel {
    func sendSecureRequest() {
        sendSecureRequestMessage = nil
        authorizationControlController?.sendSecureRequest() { message in
            self.sendSecureRequestMessage = (self.sendSecureRequestMessage ?? "") + "\n\n" + message
        }
    }
}
