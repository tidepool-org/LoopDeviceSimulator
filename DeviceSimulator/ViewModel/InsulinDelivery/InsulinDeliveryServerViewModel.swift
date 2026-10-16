//
//  InsulinDeliveryServerViewModel.swift
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
class InsulinDeliveryServerViewModel {

    @ObservationIgnored private var server: GATTServer?
    @ObservationIgnored private var mockInsulinDeliveryPump: MockInsulinDeliveryPump?

    var consoleMessages: String = ""
    var isServerBusy = false {
        didSet {
            if oldValue != isServerBusy { SessionLog.shared.stimulus("Server Busy → \(isServerBusy ? "on" : "off")") }
            if mockInsulinDeliveryPump?.recordAccessControlPoint.isServerBusy != isServerBusy {
                mockInsulinDeliveryPump?.recordAccessControlPoint.isServerBusy = isServerBusy
            }
        }
    }
    var procedureAlreadyInProgress = false {
        didSet { if oldValue != procedureAlreadyInProgress { SessionLog.shared.stimulus("Procedure Already In Progress → \(procedureAlreadyInProgress ? "on" : "off")") } }
    }
    var outOfRangeSchedule = false {
        didSet { if oldValue != outOfRangeSchedule { SessionLog.shared.stimulus("Out of Range Schedule → \(outOfRangeSchedule ? "on" : "off")") } }
    }
    var numberOfSubscribedDevices: Int = 0
    var readyToDisconnect = false {
        didSet { if oldValue != readyToDisconnect { SessionLog.shared.stimulus("Ready to Disconnect → \(readyToDisconnect ? "on" : "off")") } }
    }
    var isPumpPoweredOn = true {
        didSet {
            SessionLog.shared.stimulus("Power On Pump → \(isPumpPoweredOn ? "on" : "off")")
            if isPumpPoweredOn {
                startServer()
            } else {
                stopServer()
            }
        }
    }
    var isPumpBehaviourEnabled = false {
        didSet {
            // Also mirrored from the pump on every update; only a real change is a stimulus.
            if oldValue != isPumpBehaviourEnabled { SessionLog.shared.stimulus("Pump behaviour → \(isPumpBehaviourEnabled ? "on" : "off")") }
            mockInsulinDeliveryPump?.isPumpBehaviourEnabled = isPumpBehaviourEnabled
        }
    }
    var isAuthorizationControlEnabled = false {
        didSet {
            if oldValue != isAuthorizationControlEnabled { SessionLog.shared.stimulus("Authorization Control → \(isAuthorizationControlEnabled ? "on" : "off")") }
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
    var isTempBasalString: String = ""
    var bolusDeliveryString: String = ""
    
    @ObservationIgnored private var serverName: String?
    
    /// `nil` keeps the current name (restart); an empty string falls back to the pump default.
    func startServer(serverName: String? = nil) {
        if let serverName = serverName {
            self.serverName = serverName.isEmpty ? nil : serverName
        }
        let server = GATTServer(advertisedName: self.serverName ?? InsulinDeliveryConstants.serverName, advertisedServices: [InsulinDeliveryCharacteristicUUID.service.cbUUID, ACCharacteristicUUID.service.cbUUID])
        self.server = server
        self.server?.delegate = self

        let messageQueue = MessageQueue(gattService: server)
        mockInsulinDeliveryPump = MockInsulinDeliveryPump(gattServer: server, messageQueue: messageQueue)
        mockInsulinDeliveryPump?.delegate = self
        mockPumpDidUpdate(mockInsulinDeliveryPump!)
        SessionLog.shared.context = SessionLog.Context(mode: .pump, role: .server, scenario: "mock pump", scenarioVersion: nil)
        SessionLog.shared.log(.lifecycle, "pump server started, advertising \(self.serverName ?? InsulinDeliveryConstants.serverName)")
    }

    func stopServer() {
        if mockInsulinDeliveryPump != nil { SessionLog.shared.log(.lifecycle, "pump server stopped") }
        SessionLog.shared.context = SessionLog.Context()
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
        SessionLog.shared.stimulus("Restart Server")
        stopServer()
        startServer()
        consoleMessages.append("server restarted")
    }

    func clearConsole() {
        consoleMessages.removeAll()
    }
}

// MARK: - Console Out Delegate

extension InsulinDeliveryServerViewModel: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        DispatchQueue.main.async {
            self.consoleMessages = message + "\n" + self.consoleMessages
        }
    }
}

// MARK: - GATT Service Delegate

extension InsulinDeliveryServerViewModel: GATTServiceDelegate {
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

// MARK: - Annunciations

extension InsulinDeliveryServerViewModel {
    func issueAnnunciation() {
        guard let annunciationTypeToIssue else { return }
        SessionLog.shared.stimulus("Issue Annunciation: \(annunciationTypeToIssue.description)")
        mockInsulinDeliveryPump?.issueGeneralAnnunciation(annunciationType: annunciationTypeToIssue)
    }
}

// MARK: - Authorization Control
extension InsulinDeliveryServerViewModel {
    func sendSecureIndication() {
        SessionLog.shared.stimulus("Send secure indication")
        let message = "This is a secure indication".data(using: .utf8)!
        mockInsulinDeliveryPump?.sendSecureIndication(message, to: 1)
    }
}

// MARK: - E2E Protection Delegate

extension InsulinDeliveryServerViewModel: E2EProtectionDelegate {
    var isE2EProtectionSupported: Bool {
        get {
            mockInsulinDeliveryPump?.featureCharacteristic.flags.contains(.supportedE2EProtection) ?? false
        }
        set {
            SessionLog.shared.stimulus("E2E Protection Supported → \(newValue ? "on" : "off")")
            if newValue {
                mockInsulinDeliveryPump?.featureCharacteristic.flags.insert(.supportedE2EProtection)
            } else {
                mockInsulinDeliveryPump?.featureCharacteristic.flags.remove(.supportedE2EProtection)
            }
        }
    }
}

// MARK: - Mock Pump Delegate
extension InsulinDeliveryServerViewModel: MockInsulinDeliveryPumpDelegate {
    func mockPumpDidUpdate(_ pump: InsulinDeliveryServiceKit.MockInsulinDeliveryPump) {
        therapyStateString = String(describing: pump.therapyState)
        operationalStateString = String(describing: pump.operationalState)
        isPumpBehaviourEnabled = pump.isPumpBehaviourEnabled
        isAuthorizationControlEnabled = pump.isAuthorizationControlEnabled
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        reservoirLevelString = String(describing: formatter.string(from: pump.reservoirRemaining)!)
        basalDeliveryString = pump.activeBasalRate != nil ? String(describing: (pump.activeBasalRate)) : "no basal delivery"
        isTempBasalString = pump.isTempBasal ? "yes" : "no"
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
