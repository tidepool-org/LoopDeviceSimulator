//
//  InsulinDeliveryServiceViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

@Observable
class InsulinDeliveryServiceViewModel {

    @ObservationIgnored private var server: GATTServer?
    @ObservationIgnored private var mockInsulinDeliveryPump: MockInsulinDeliveryPump?

    var consoleMessages: String = ""
    var isServerBusy = false {
        didSet {
            if mockInsulinDeliveryPump?.recordAccessControlPoint.isServerBusy != isServerBusy {
                mockInsulinDeliveryPump?.recordAccessControlPoint.isServerBusy = isServerBusy
            }
        }
    }
    var procedureAlreadyInProgress = false
    var outOfRangeSchedule = false
    var numberOfSubscribedDevices: Int = 0
    var readyToDisconnect = false
    var isPumpPoweredOn = true {
        didSet {
            if isPumpPoweredOn {
                startServer()
            } else {
                stopServer()
            }
        }
    }
    var isPumpBehaviourEnabled = false {
        didSet {
            mockInsulinDeliveryPump?.isPumpBehaviourEnabled = isPumpBehaviourEnabled
        }
    }
    var isAuthorizationControlEnabled = false {
        didSet {
            mockInsulinDeliveryPump?.isAuthorizationControlEnabled = isAuthorizationControlEnabled
        }
    }
    
    @ObservationIgnored var oobRandomNumberString: String {
        guard let oobString = mockInsulinDeliveryPump?.securityManager.configuration.oobRandomNumber else {
            return "Unknown"
        }
        return String(data: oobString, encoding: .utf8)!
    }
    
    var annunciationTypeToIssue: AnnunciationType?
        
    var therapyStateString: String = String(describing: InsulinTherapyControlState.undetermined)
    var operationalStateString: String = String(describing: PumpOperationalState.undetermined)
    var reservoirLevelString: String = ""
    var basalDeliveryString: String = ""
    var bolusDeliveryString: String = ""
    
    @ObservationIgnored private var serverName: String?
    
    func startServer(serverName: String? = nil) {
        if let serverName = serverName {
            self.serverName = serverName
        }
        let server = GATTServer(advertisedName: self.serverName ?? InsulinDeliveryConstants.serverName, advertisedServices: [InsulinDeliveryCharacteristicUUID.service.cbUUID, ACCharacteristicUUID.service.cbUUID])
        self.server = server
        self.server?.delegate = self

        let messageQueue = MessageQueue(gattService: server)
        mockInsulinDeliveryPump = MockInsulinDeliveryPump(gattServer: server, messageQueue: messageQueue)
        mockInsulinDeliveryPump?.delegate = self
        mockPumpDidUpdate(mockInsulinDeliveryPump!)
    }

    func stopServer() {
        server?.disconnect()
        server = nil
        mockInsulinDeliveryPump = nil
        isServerBusy = false
        procedureAlreadyInProgress = false
        outOfRangeSchedule = false
        numberOfSubscribedDevices = 0
        therapyStateString = String(describing: InsulinTherapyControlState.undetermined)
        operationalStateString = String(describing: PumpOperationalState.undetermined)
    }

    func restartServer() {
        stopServer()
        startServer()
        consoleMessages.append("server restarted")
    }

    func clearConsole() {
        consoleMessages.removeAll()
    }
}

// MARK: - Console Out Delegate

extension InsulinDeliveryServiceViewModel: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        DispatchQueue.main.async {
            self.consoleMessages = message + "\n" + self.consoleMessages
        }
    }
}

// MARK: - GATT Service Delegate

extension InsulinDeliveryServiceViewModel: GATTServiceDelegate {
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

// MARK: - Annunciations

extension InsulinDeliveryServiceViewModel {
    func issueAnnunciation() {
        guard let annunciationTypeToIssue else { return }
        mockInsulinDeliveryPump?.issueGeneralAnnunciation(annunciationType: annunciationTypeToIssue)
    }
}

// MARK: - Authorization Control
extension InsulinDeliveryServiceViewModel {
    func sendSecureIndication() {
        let message = "This is a secure indication".data(using: .utf8)!
        mockInsulinDeliveryPump?.sendSecureIndication(message, to: 1)
    }
}

// MARK: - E2E Protection Delegate

extension InsulinDeliveryServiceViewModel: E2EProtectionDelegate {
    var isE2EProtectionSupported: Bool {
        get {
            mockInsulinDeliveryPump?.featureCharacteristic.flags.contains(.supportedE2EProtection) ?? false
        }
        set {
            if newValue {
                mockInsulinDeliveryPump?.featureCharacteristic.flags.insert(.supportedE2EProtection)
            } else {
                mockInsulinDeliveryPump?.featureCharacteristic.flags.remove(.supportedE2EProtection)
            }
        }
    }
}

// MARK: - Mock Pump Delegate
extension InsulinDeliveryServiceViewModel: MockInsulinDeliveryPumpDelegate {
    func mockPumpDidUpdate(_ pump: InsulinDeliveryServiceKit.MockInsulinDeliveryPump) {
        therapyStateString = String(describing: pump.therapyState)
        operationalStateString = String(describing: pump.operationalState)
        isPumpBehaviourEnabled = pump.isPumpBehaviourEnabled
        isAuthorizationControlEnabled = pump.isAuthorizationControlEnabled
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        reservoirLevelString = String(describing: formatter.string(from: pump.reservoirRemaining)!)
        basalDeliveryString = String(describing: pump.activeBasalRate)
        let activeBolusDeliveryStatus = pump.activeBolusDeliveryStatus
        bolusDeliveryString = activeBolusDeliveryStatus.progressState == .noActiveBolus ? "no active bolus" : "\(String(describing: activeBolusDeliveryStatus.insulinDelivered)) of \(String(describing: activeBolusDeliveryStatus.insulinProgrammed))"
    }
}

extension MockInsulinDeliveryPump {
    func getFeatureCharacteristic() -> Data {
        let qualityOfProtection : QualityOfProtection = [.confidentiality, .integrity, .authentication]
        let flags : FeaturesFlag = [.descriptorsSupported, .resourceHandleToUUIDMapSupported, .initiatePairingSupported, .keyExchangeECDHSupported, .keyExchangeKDFSupported, .invalidateEstablishedSecuritySupported, .protectedResourceWriteSupported, .protectedResourceReadSupported, .protectedResourceNotificationSupported, .protectedResourceIndicationSupported , .keyFormatServerUncompressedPlainSupported, .keyFormatClientUncompressedPlainSupported]
        let oobKeyExchangeCapabilities : OOBCapability = [.string, .onPaper]
        let confirmationStaticOOBNumberCapabilities : OOBCapability = [.string, .onPaper]
        let confirmationInputNumberMaxValue : UInt32 = 0
        let confirmationInputCapabilities : ConfirmationInputCapability = []
        let confirmationOutputNumberMaxValue : UInt32 = 1000
        let confirmationOutputCapabilities : ConfirmationOutputCapability = [.outputNumeric]
                
        var features = Data(flags.rawValue)
        features.append(qualityOfProtection.rawValue)
        features.append(oobKeyExchangeCapabilities.rawValue)
        features.append(confirmationStaticOOBNumberCapabilities.rawValue)
        features.append(confirmationInputNumberMaxValue)
        features.append(confirmationInputCapabilities.rawValue)
        features.append(confirmationOutputNumberMaxValue)
        features.append(confirmationOutputCapabilities.rawValue)

        return features
    }
}
