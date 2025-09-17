//
//  InsulinDeliveryClientViewModel.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

class InsulinDeliveryClientViewModel: ObservableObject {

    private var insulinDeliveryController: InsulinDeliveryController?

    @Published var deviceList: [Device] = []
    
    @Published var connectedDevice: Device? = nil {
        didSet {
            connectedMessage = "Disconnect from \(connectedDevice?.name ?? "Unknown device")"
        }
    }

    @Published var connectedMessage: String = "Currently Disconnected"
    
    @Published var isPeripheralConnected: Bool = false

    // MARK: - Configure Characterist
    
    @Published var indicationsEnabledStatus: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDStatusIndications(enabled: indicationsEnabledStatus) { message in
                self.indicationsEnabledMessageStatus = message
            }
        }
    }
    @Published var indicationsMessageStatus: String? = nil
    @Published var indicationsEnabledMessageStatus: String? = nil
    
    @Published var indicationsEnabledStatusChanged: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDStatusChangedIndications(enabled: indicationsEnabledStatusChanged) { message in
                self.indicationsEnabledMessageStatusChanged = message
            }
        }
    }
    @Published var indicationsMessageStatusChanged: String? = nil
    @Published var indicationsEnabledMessageStatusChanged: String? = nil
    
    @Published var indicationsEnabledAnnunciationStatus: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDAnnunciationStatusIndications(enabled: indicationsEnabledAnnunciationStatus) { message in
                self.indicationsEnabledMessageAnnunciationStatus = message
            }
        }
    }
    @Published var indicationsMessageAnnunciationStatus: String? = nil
    @Published var indicationsEnabledMessageAnnunciationStatus: String? = nil
    
    @Published var indicationsEnabledStatusReaderControlPoint: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDStatusReaderControlPointIndications(enabled: indicationsEnabledStatusReaderControlPoint) { message in
                self.indicationsEnabledMessageStatusReaderControlPoint = message
            }
        }
    }
    @Published var indicationsEnabledMessageStatusReaderControlPoint: String? = nil
    
    @Published var indicationsEnabledCommandControlPoint: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDCommandControlPointIndications(enabled: indicationsEnabledCommandControlPoint) { message in
                self.indicationsEnabledMessageCommandControlPoint = message
            }
        }
    }
    @Published var indicationsEnabledMessageCommandControlPoint: String? = nil
    
    @Published var indicationsEnabledCommandData: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDCommandDataIndications(enabled: indicationsEnabledCommandData) { message in
                self.indicationsEnabledMessageCommandData = message
            }
        }
    }
    @Published var indicationsEnabledMessageCommandData: String? = nil
    
    @Published var indicationsEnabledRecordAccessControlPoint: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDRecordAccessControlPointIndications(enabled: indicationsEnabledRecordAccessControlPoint) { message in
                self.indicationsEnabledMessageRecordAccessControlPoint = message
            }
        }
    }
    @Published var indicationsEnabledMessageRecordAccessControlPoint: String? = nil
    
    @Published var indicationsEnabledHistoryData: Bool = false {
        didSet {
            insulinDeliveryController?.configureIDDHistoryDataIndications(enabled: indicationsEnabledHistoryData) { message in
                self.indicationsEnabledMessageHistoryData = message
            }
        }
    }
    @Published var indicationsEnabledMessageHistoryData: String? = nil

    @Published var indicationsEnabledDeviceTimeControlPoint: Bool = false {
        didSet {
            insulinDeliveryController?.configureDeviceTimeControlPointIndications(enabled: indicationsEnabledDeviceTimeControlPoint) { message in
                self.indicationsEnabledMessageDeviceTimeControlPoint = message
            }
        }
    }
    @Published var indicationsMessageDeviceTime: String? = nil
    @Published var indicationsEnabledMessageDeviceTimeControlPoint: String? = nil

    // MARK: - Read Characterist
    
    @Published var readMessageIDDFeatureCharacteristic: String? = nil
    @Published var readMessageIDDStatusCharacteristic: String? = nil
    @Published var readMessageIDDStatusChangedCharacteristic: String? = nil
    @Published var readMessageIDDAnnunciationStatusCharacteristic: String? = nil
    @Published var readMessageDeviceTimeCharacteristic: String? = nil
    
    @Published var setDeviceTimeMessage: String? = nil
    @Published var playBeepMessage: String? = nil
    
    // MARK: - Selected Status
    
    @Published var selectedStatus: Bool = false
    @Published var selectedStatusChanged: Bool = false
    @Published var selectedAnnunciationStatus: Bool = false
    @Published var selectedActiveBasalRate: Bool = false
    @Published var selectedActiveBolusIDs: Bool = false
    @Published var selectedActiveBolusProgrammed: Bool = false
    @Published var selectedActiveBolusDelivered: Bool = false
    @Published var selectedActiveBolusRemaining: Bool = false
    @Published var selectedAvailableBolus: Bool = false
    @Published var selectedTotalDailyInsulin: Bool = false
    @Published var selectedDeliveredInsulin: Bool = false
    @Published var selectedStatusMessage: String? = nil
   
//    func getSelectedStatusInformation() {
//        selectedStatusMessage = nil
//        var selectedStatuses: IDDSelectedStatusFlag = .allZeros
//        if selectedStatus { selectedStatuses.insert(.statusIndication) }
//        if selectedStatusChanged { selectedStatuses.insert(.statusChangedIndication) }
//        if selectedAnnunciationStatus { selectedStatuses.insert(.annunciationStatusIndication) }
//        if selectedActiveBasalRate { selectedStatuses.insert(.getActiveBasalRateDelivery) }
//        if selectedActiveBolusIDs { selectedStatuses.insert(.getActiveBolusIDs) }
//        if selectedActiveBolusProgrammed { selectedStatuses.insert(.getActiveBolusProgrammed) }
//        if selectedActiveBolusDelivered { selectedStatuses.insert(.getActiveBolusDelivered) }
//        if selectedActiveBolusRemaining { selectedStatuses.insert(.getActiveBolusRemaining) }
//        if selectedAvailableBolus { selectedStatuses.insert(.getAvailableBoluses) }
//        if selectedTotalDailyInsulin { selectedStatuses.insert(.getTotalDailyInsulinStatus) }
//        if selectedDeliveredInsulin { selectedStatuses.insert(.getDeliveredInsulin) }
//        insulinDeliveryController?.getSelectedStatus(selectedStatuses) { message in
//            var statusMessages: String = ""
//            if let selectedStatusMessage = self.selectedStatusMessage {
//                statusMessages = selectedStatusMessage
//            }
//            statusMessages.append("\n\n\(message)")
//            self.selectedStatusMessage = statusMessages
//        }
//    }
    
    // MARK: - Status Reader
    @Published var resetStatusMessage: String? = nil
    @Published var statusToReset: IDStatusChangedFlag = .allFlags
    @Published var getActiveBolusIDsMessage: String? = nil
    @Published var getActiveBolusDeliveryMessage: String? = nil
    @Published var getActiveBasalDeliveryMessage: String? = nil
    @Published var getTotalDailyInsulinStatusMessage: String? = nil
    @Published var getCounterMessage: String? = nil
    @Published var getDeliveredInsulinMessage: String? = nil
    @Published var getInsulinOnBoardMessage: String? = nil
    @Published var bolusValueSelection: BolusValueSelection = .remaining
    @Published var bolusIDString: String = "1"
    var bolusID: BolusID { BolusID(bolusIDString) ?? 1 }
    @Published var counterType: CounterType = .lifetime
    @Published var counterValueSelection: CounterValueSelection = .remaining
    
    // MARK: - Command Control Point
    @Published var therapyControlState: InsulinTherapyControlState = .stop
    @Published var setTherapyControlStateMessage: String? = nil
    @Published var setFlightModeMessage: String? = nil
    @Published var annunciationIDString: String = "1"
    var annunciationID: AnnunciationIdentifier { AnnunciationIdentifier(annunciationIDString) ?? 1 }
    @Published var annunciationMessage: String? = nil
    @Published var basalProfileNumberString: String = "1"
    var basalProfileNumber: UInt8 {  UInt8(basalProfileNumberString) ?? 1}
    @Published var basalRateProfileMessage: String? = nil
    @Published var setTempBasalMessage: String? = nil
    @Published var tempBasalMessage: String? = nil
    @Published var tempBasalAmountString: String = "1"
    var tempBasalAmount: Double { Double(tempBasalAmountString) ?? 1}
    @Published var replaceExistingTempBasal: Bool = false
    @Published var bolusMessage: String? = nil
    @Published var bolusAmountString: String = "2"
    var bolusAmount: Double { Double(bolusAmountString) ?? 2}
    @Published var cancelBolusIDString: String = "1"
    var cancelBolusID: Double { Double(cancelBolusIDString) ?? 1}
    @Published var getAvailableBolusesMessage: String? = nil
    @Published var getTemplateStatusDetailsMessage: String? = nil
    @Published var activateProfilesMessage: String? = nil
    @Published var profileTemplateNumberString: String = "1"
    var profileTemplateNumber: TemplateNumber { TemplateNumber(profileTemplateNumberString) ?? 1}
    @Published var getActivatedProfilesMessage: String? = nil
    @Published var primingMessage: String? = nil
    @Published var primingAmountString: String = "1.2"
    var primingAmount: Double { Double(primingAmountString) ?? 1.2}
    @Published var setInitialReservoirFillMessage: String? = nil
    @Published var initialReservoirFillLevelString = "100"
    var initialReservoirFillLevel: Int { Int(initialReservoirFillLevelString) ?? 100}
    @Published var maxBolusAmountMessage: String? = nil
    @Published var maxBolusAmountString: String = "10"
    var maxBolusAmount: Double { Double(maxBolusAmountString) ?? 10}

    // MARK: - Write Characterist
    @Published var maxBasalRateMessage: String? = nil
    @Published var maxBasalRateAmountString: String = ""
    var maxBasalRateAmount: Double { Double(maxBasalRateAmountString) ?? 8.0 }
    
    @Published var localBolusMessage: String? = nil
    @Published var localBolusStatus: Bool = true
    @Published var localBolusStepValueString: String = ""
    var localBolsuStepValue: Double { Double(localBolusStepValueString) ?? 1.0 }
    @Published var localBolusMaxAmountString: String = ""
    var localBolusMaxAmount: Double { Double(localBolusMaxAmountString) ?? 10.0 }

    @Published var autoStopMessage: String? = nil
    @Published var autoStopStatus: Bool = true
    @Published var maxAutoStopTimeoutString: String = ""
    var maxAutoStopTimeout: UInt16 { UInt16(maxAutoStopTimeoutString) ?? 300 }
    @Published var autoStopCounterString: String = ""
    var autoStopCounter: UInt16 { UInt16(autoStopCounterString) ?? 15 }
    @Published var resetAutoStopMessage: String? = nil
    @Published var lastUserInteractionString: String = ""
    var lastUserInteraction: UInt16 { UInt16(lastUserInteractionString) ?? 15 }
    
    @Published var suspendSignalMessage: String? = nil
    @Published var suspendSignalStatus: Bool = true
    @Published var suspendSignalRepeats: Bool = true
    @Published var suspendSignalStartTimeString: String = ""
    var suspendSignalStartTime: UInt16 { UInt16(suspendSignalStartTimeString) ?? 480 }
    @Published var suspendSignalDurationString: String = ""
    var suspendSignalDuration: UInt16 { UInt16(suspendSignalDurationString) ?? 1320 }
    
    @Published var lifetimeWarningLimitMessage: String? = nil
    @Published var lifetimeWarningLimitStatus: Bool = true
    @Published var lifetimeWarningLimitString: String = ""
    var lifetimeWarningLimit: UInt16 { UInt16(lifetimeWarningLimitString) ?? 10 }
    
    @Published var reservoirLevelWarningLimitMessage: String? = nil
    @Published var reservoirLevelWarningLimitStatus: Bool = true
    @Published var reservoirLevelWarningLimitString: String = ""
    var reservoirLevelWarningLimit: Double { Double(reservoirLevelWarningLimitString) ?? 60.0 }
    
    @Published var insulinDeliveryStartSoundParametersMessage: String? = nil
    @Published var insulinDeliveryStartSoundStatus: Bool = true
    
    // MARK: - RACP
    
    @Published var racpMessage: String? = nil
    @Published var racpOperator: IDRACPOperator = .allRecords
    @Published var minRecordNumberString: String = ""
    @Published var maxRecordNumberString: String = ""
    
    // Primarily used for testing
    private let dateGenerator: () -> Date
    private var now: Date { dateGenerator() }

    @Published var consoleMessages: String = ""

    init(dateGenerator: @escaping () -> Date = { Date() }) {
        self.dateGenerator = dateGenerator
    }
    
    // MARK: - Peripheral Connection

    func startClient() {
        insulinDeliveryController = InsulinDeliveryController()
        insulinDeliveryController?.delegate = self
    }

    func stopClient() {
        disconnect()
        reset()
        insulinDeliveryController?.centralManager?.stopScan()
        consoleMessages.removeAll()
        isPeripheralConnected = false
    }

    func connectToDevice(_ device: Device) {
        guard let uuid = UUID(uuidString: device.uuid) else { return }
        connectedDevice = device
        insulinDeliveryController?.connectToPeripheralWithUUID(uuid: uuid)
    }

    func refreshList() {
        deviceList.removeAll()
        insulinDeliveryController?.scanForPeripherals()
    }

    func disconnect() {
        insulinDeliveryController?.disconnectFromPeripheral()
    }
    
    func switchToPeripheralList() {
        isPeripheralConnected = false
    }

    func clearConsole() {
        consoleMessages.removeAll()
    }

    private func reset() {
        indicationsEnabledStatus = false
        indicationsEnabledStatusChanged = false
        indicationsEnabledAnnunciationStatus = false
        indicationsEnabledStatusReaderControlPoint = false
        indicationsEnabledCommandControlPoint = false
        indicationsEnabledCommandData = false
        indicationsEnabledRecordAccessControlPoint = false
        indicationsEnabledHistoryData = false
        indicationsMessageStatus = nil
        indicationsMessageStatusChanged = nil
        indicationsMessageAnnunciationStatus = nil
        indicationsEnabledMessageStatus = nil
        indicationsEnabledMessageStatusChanged = nil
        indicationsEnabledMessageAnnunciationStatus = nil
        indicationsEnabledMessageStatusReaderControlPoint = nil
        indicationsEnabledMessageCommandControlPoint = nil
        indicationsEnabledMessageCommandData = nil
        indicationsEnabledMessageRecordAccessControlPoint = nil
        indicationsEnabledMessageHistoryData = nil
        readMessageIDDFeatureCharacteristic = nil
        readMessageIDDStatusCharacteristic = nil
        readMessageIDDStatusChangedCharacteristic = nil
        readMessageIDDAnnunciationStatusCharacteristic = nil
        selectedStatus = false
        selectedStatusChanged = false
        selectedAnnunciationStatus = false
        selectedActiveBasalRate = false
        selectedActiveBolusIDs = false
        selectedActiveBolusProgrammed = false
        selectedActiveBolusDelivered = false
        selectedActiveBolusRemaining = false
        selectedAvailableBolus = false
        selectedTotalDailyInsulin = false
        selectedDeliveredInsulin = false
        selectedStatusMessage = nil
        maxBasalRateMessage = nil
        maxBasalRateAmountString = ""
        localBolusMessage = nil
        localBolusStepValueString = ""
        localBolusMaxAmountString = ""
        autoStopMessage = nil
        maxAutoStopTimeoutString = ""
        autoStopCounterString = ""
        resetAutoStopMessage = nil
        suspendSignalMessage = nil
        suspendSignalStartTimeString = ""
        suspendSignalDurationString = ""
        lifetimeWarningLimitString = ""
        lifetimeWarningLimitMessage = nil
        reservoirLevelWarningLimitString = ""
        reservoirLevelWarningLimitMessage = nil
        insulinDeliveryStartSoundParametersMessage = nil
        racpMessage = nil
        racpOperator = .allRecords
        minRecordNumberString = ""
        maxRecordNumberString = ""
        resetStatusMessage = nil
        getActiveBolusIDsMessage = nil
        getActiveBolusDeliveryMessage = nil
        getActiveBasalDeliveryMessage = nil
        getTotalDailyInsulinStatusMessage = nil
        getCounterMessage = nil
        getDeliveredInsulinMessage = nil
        getInsulinOnBoardMessage = nil
        setTherapyControlStateMessage = nil
        setFlightModeMessage = nil
        annunciationMessage = nil
        basalRateProfileMessage = nil
        setTempBasalMessage = nil
        tempBasalMessage = nil
        bolusMessage = nil
        getAvailableBolusesMessage = nil
        getTemplateStatusDetailsMessage = nil
        activateProfilesMessage = nil
        getActivatedProfilesMessage = nil
        primingMessage = nil
        setInitialReservoirFillMessage = nil
        maxBolusAmountMessage = nil
        refreshList()
    }
}


extension InsulinDeliveryClientViewModel: InsulinDeliveryControllerDelegate {
    func peripheralDiscovered(sender: InsulinDeliveryController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber) {
        let device = Device(name: peripheralName, uuid: peripheralID.uuidString, advertisedName: advertisingName, rssi: rssi, serviceData: serviceData)
        deviceList.append(device)
        deviceList.sort(by: { $0.rssi.compare($1.rssi) == .orderedDescending })
    }

    func connectedToPeripheral(sender: InsulinDeliveryController) {
        isPeripheralConnected = true
    }

    func didDisconnectFromPeripheral(sender: InsulinDeliveryController) {
        connectedMessage = "Currently disconnected"
        displayMessageInConsole(message: "\(#function) wait for the user to switch back to peripheral view")
    }

    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String) {
        ConsoleOut.shared.logMessage(message: "\(cbUUID) notification/indication: \(message)")
        if cbUUID == InsulinDeliveryCharacteristicUUID.status.cbUUID {
            indicationsMessageStatus = message
        } else if cbUUID == InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID {
            indicationsMessageStatusChanged = message
        } else if cbUUID == InsulinDeliveryCharacteristicUUID.annunciationStatus.cbUUID {
            indicationsMessageAnnunciationStatus = message
        } else if cbUUID == InsulinDeliveryCharacteristicUUID.historyData.cbUUID {
            racpMessage = (racpMessage ?? "") + "\n\n" + message
        }
    }
}

extension InsulinDeliveryClientViewModel: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        consoleMessages = message + "\n" + consoleMessages
    }
}

// MARK: - Read Characteristics
extension InsulinDeliveryClientViewModel {
    func readIDDFeatureCharacteristic() {
        insulinDeliveryController?.readIDDFeatureCharacteristic() { message in
            self.readMessageIDDFeatureCharacteristic = message
        }
    }
    
    func readIDDStatusCharacteristic() {
        insulinDeliveryController?.readIDDStatusCharacteristic() { message in
            self.readMessageIDDStatusCharacteristic = message
        }
    }
    
    func readIDDStatusChangedCharacteristic() {
        insulinDeliveryController?.readIDDStatusChangedCharacteristic() { message in
            self.readMessageIDDStatusChangedCharacteristic = message
        }
    }
    
    func readIDDAnnunciationStatusCharacteristic() {
        insulinDeliveryController?.readIDDAnnunciationStatusCharacteristic() { message in
            self.readMessageIDDAnnunciationStatusCharacteristic = message
        }
    }
}

// MARK: - Device Time
extension InsulinDeliveryClientViewModel {
    func readDeviceTimeCharacteristic() {
        insulinDeliveryController?.readDeviceTimeCharacteristic() { message in
            self.readMessageDeviceTimeCharacteristic = message
        }
    }
    
    func setDeviceTime() {
        insulinDeliveryController?.setDeviceTime() { message in
            self.setDeviceTimeMessage = message
        }
    }
}

// MARK: - Immediate Alert
extension InsulinDeliveryClientViewModel {
    func playBeepSound() {
        insulinDeliveryController?.playBeepSound() { message in
            self.playBeepMessage = message
        }
    }
}

// MARK: - Status Reader Control Point
extension InsulinDeliveryClientViewModel {
    func resetStatus() {
        resetStatusMessage = nil
        insulinDeliveryController?.resetStatus(statusToReset) { message in
            self.resetStatusMessage = (self.resetStatusMessage ?? "") + "\n\n" + message
        }
    }
    
    func getActiveBolusIDs() {
        getActiveBolusIDsMessage = nil
        insulinDeliveryController?.getActiveBolusIDs() { message in
            self.getActiveBolusIDsMessage = (self.getActiveBolusIDsMessage ?? "") + "\n\n" + message
        }
    }
    
    func getActiveBolusDelivery() {
        getActiveBolusDeliveryMessage = nil
        insulinDeliveryController?.getActiveBolusDelivery(bolusID, valueSelection: bolusValueSelection) { message in
            self.getActiveBolusDeliveryMessage = (self.getActiveBolusDeliveryMessage ?? "") + "\n\n" + message
        }
    }
    
    func getActiveBasalDelivery() {
        getActiveBasalDeliveryMessage = nil
        insulinDeliveryController?.getActiveBasalRateDelivery() { message in
            self.getActiveBasalDeliveryMessage = (self.getActiveBasalDeliveryMessage ?? "") + "\n\n" + message
        }
    }
    
    func getTotalDailyInsulinStatus() {
        getTotalDailyInsulinStatusMessage = nil
        insulinDeliveryController?.getTotalDailyInsulinStatus() { message in
            self.getTotalDailyInsulinStatusMessage = (self.getTotalDailyInsulinStatusMessage ?? "") + "\n\n" + message
        }
    }
    
    func getCounter() {
        getCounterMessage = nil
        insulinDeliveryController?.getCounter(for: counterType, valueSelection: counterValueSelection) { message in
            self.getCounterMessage = (self.getCounterMessage ?? "") + "\n\n" + message
        }
    }
    
    func getDeliveredInsulin() {
        getDeliveredInsulinMessage = nil
        insulinDeliveryController?.getDeliveredInsulin() { message in
            self.getDeliveredInsulinMessage = (self.getDeliveredInsulinMessage ?? "") + "\n\n" + message
        }
    }
    
    func getInsulinOnBoard() {
        getInsulinOnBoardMessage = nil
        insulinDeliveryController?.getInsulinOnBoard() { message in
            self.getInsulinOnBoardMessage = (self.getInsulinOnBoardMessage ?? "") + "\n\n" + message
        }
    }
}


// MARK: - Command Control Point
extension InsulinDeliveryClientViewModel {
    func setTherapyControlState() {
        setTherapyControlStateMessage = nil
        insulinDeliveryController?.setTherapyControlState(therapyControlState) { message in
            self.setTherapyControlStateMessage = (self.setTherapyControlStateMessage ?? "") + "\n\n" + message
        }
    }
    
    func setFlightMode() {
        setFlightModeMessage = nil
        insulinDeliveryController?.setFlightMode { message in
            self.setFlightModeMessage = (self.setFlightModeMessage ?? "") + "\n\n" + message
        }
    }
    
    func snoozeAnnunciation() {
        annunciationMessage = nil
        insulinDeliveryController?.snoozeAnnunciation(annunciationID) { message in
            self.annunciationMessage = (self.annunciationMessage ?? "") + "\n\n" + message
        }
    }
    
    func confirmAnnunciation() {
        annunciationMessage = nil
        insulinDeliveryController?.confirmAnnunciation(annunciationID) { message in
            self.annunciationMessage = (self.annunciationMessage ?? "") + "\n\n" + message
        }
    }
    
    func readBasalProfile() {
        basalRateProfileMessage = nil
        insulinDeliveryController?.readBasalProfile(basalProfileNumber) { message in
            self.basalRateProfileMessage = (self.basalRateProfileMessage ?? "") + "\n\n" + message
        }
    }
    
    func writeBasalProfile() {
        basalRateProfileMessage = nil
        insulinDeliveryController?.writeBasalProfile(basalProfileNumber) { message in
            self.basalRateProfileMessage = (self.basalRateProfileMessage ?? "") + "\n\n" + message
        }
    }
    
    func setTemplBasal() {
        tempBasalMessage = nil
        insulinDeliveryController?.setTempBasal(tempBasalAmount, replaceExisting: replaceExistingTempBasal) { message in
            self.tempBasalMessage = (self.tempBasalMessage ?? "") + "\n\n" + message
        }
    }
    
    func cancelTempBasal() {
        tempBasalMessage = nil
        insulinDeliveryController?.cancelTempBasal { message in
            self.tempBasalMessage = (self.tempBasalMessage ?? "") + "\n\n" + message
        }
    }
    
    func setBolus() {
        bolusMessage = nil
        insulinDeliveryController?.setBolus(bolusAmount) { message in
            self.bolusMessage = (self.bolusMessage ?? "") + "\n\n" + message
        }
    }
    
    func cancelBolus() {
        bolusMessage = nil
        insulinDeliveryController?.cancelBolus(with: bolusID) { message in
            self.bolusMessage = (self.bolusMessage ?? "") + "\n\n" + message
        }
    }
    
    func getAvailableBoluses() {
        getAvailableBolusesMessage = nil
        insulinDeliveryController?.getAvailableBoluses { message in
            self.getAvailableBolusesMessage = (self.getAvailableBolusesMessage ?? "") + "\n\n" + message
        }
    }
    
    func getTemplateStatusDetails() {
        getTemplateStatusDetailsMessage = nil
        insulinDeliveryController?.getTemplateStatusDetails { message in
            self.getTemplateStatusDetailsMessage = (self.getTemplateStatusDetailsMessage ?? "") + "\n\n" + message
        }
    }
    
    func resetTemplateStatus() {
        activateProfilesMessage = nil
        insulinDeliveryController?.resetTemplateStatus([profileTemplateNumber]) { message in
            self.activateProfilesMessage = (self.activateProfilesMessage ?? "") + "\n\n" + message
        }
    }
    
    func activateProfileTemplates() {
        activateProfilesMessage = nil
        insulinDeliveryController?.activateProfileTemplates([profileTemplateNumber]) { message in
            self.activateProfilesMessage = (self.activateProfilesMessage ?? "") + "\n\n" + message
        }
    }
    
    func getActivatedProfiles() {
        getActivatedProfilesMessage = nil
        insulinDeliveryController?.getActivatedProfiles { message in
            self.getActivatedProfilesMessage = (self.getActivatedProfilesMessage ?? "") + "\n\n" + message
        }
    }
    
    func startPriming() {
        primingMessage = nil
        insulinDeliveryController?.startPriming(amount: primingAmount) { message in
            self.primingMessage = (self.primingMessage ?? "") + "\n\n" + message
        }
    }
    
    func stopPriming() {
        primingMessage = nil
        insulinDeliveryController?.stopPriming { message in
            self.primingMessage = (self.primingMessage ?? "") + "\n\n" + message
        }
    }
    
    func setInitialReservoirFillLevel() {
        setInitialReservoirFillMessage = nil
        insulinDeliveryController?.setInitialReservoirFillLevel(initialReservoirFillLevel) { message in
            self.setInitialReservoirFillMessage = (self.setInitialReservoirFillMessage ?? "") + "\n\n" + message
        }
    }
    
    func getMaxBolusAmount() {
        maxBolusAmountMessage = nil
        insulinDeliveryController?.getMaxBolusAmount { message in
            self.maxBolusAmountMessage = (self.maxBolusAmountMessage ?? "") + "\n\n" + message
        }
    }
    
    func setMaxBolusAmount() {
        maxBolusAmountMessage = nil
        insulinDeliveryController?.setMaxBolusAmount(maxBolusAmount) { message in
            self.maxBolusAmountMessage = (self.maxBolusAmountMessage ?? "") + "\n\n" + message
        }
    }
    
    
//    func getMaxBasalRateAmount() {
//        maxBasalRateMessage = nil
//        sendCommand(.getMaxBasalRateAmount) { message in
//            self.maxBasalRateMessage = (self.maxBasalRateMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setMaxBasalRateAmount() {
//        maxBasalRateMessage = nil
//        let operand = Data(maxBasalRateAmount.sfloat)
//        sendCommand(.setMaxBasalRateAmount, operand: operand) { message in
//            self.maxBasalRateMessage = (self.maxBasalRateMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getLocalBolusParameters() {
//        localBolusMessage = nil
//        sendCommand(.getLocalBolusParameters) { message in
//            self.localBolusMessage = (self.localBolusMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setLocalBolusParameters() {
//        localBolusMessage = nil
//        var operand = localBolusStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        if localBolusStatus {
//            operand.append(localBolsuStepValue.sfloat)
//            operand.append(localBolusMaxAmount.sfloat)
//        }
//        sendCommand(.setLocalBolusParameters, operand: operand) { message in
//            self.localBolusMessage = (self.localBolusMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getAutoStopParameters() {
//        autoStopMessage = nil
//        sendCommand(.getAutomaticStopParameters) { message in
//            self.autoStopMessage = (self.autoStopMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setAutoStopParameters() {
//        autoStopMessage = nil
//        var operand = autoStopStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        if autoStopStatus {
//            operand.append(maxAutoStopTimeout)
//        }
//        sendCommand(.setAutomaticStopParameters, operand: operand) { message in
//            self.autoStopMessage = (self.autoStopMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func resetAutoStopTimeout() {
//        resetAutoStopMessage = nil
//        let operand = Data(lastUserInteraction)
//        sendCommand(.resetAutomaticStopTimeout, operand: operand) { message in
//            self.resetAutoStopMessage = (self.resetAutoStopMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getSuspendSignalParameters() {
//        suspendSignalMessage = nil
//        sendCommand(.getAcousticSignalSuspensionParameters) { message in
//            self.suspendSignalMessage = (self.suspendSignalMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setSuspendSignalParameters() {
//        suspendSignalMessage = nil
//        var operand = suspendSignalStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        if suspendSignalStatus {
//            operand.append(suspendSignalStartTime)
//            operand.append(suspendSignalDuration)
//            operand.append(suspendSignalRepeats ? IDDRepeatFlag.repeating.rawValue : IDDRepeatFlag.once.rawValue)
//        }
//        sendCommand(.setAcousticSignalSuspensionParameters, operand: operand) { message in
//            self.suspendSignalMessage = (self.suspendSignalMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getLifetimeWarningLimit() {
//        lifetimeWarningLimitMessage = nil
//        sendCommand(.getLifetimeWarningLimit) { message in
//            self.lifetimeWarningLimitMessage = (self.lifetimeWarningLimitMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setLifetimeWarningLimit() {
//        lifetimeWarningLimitMessage = nil
//        var operand = lifetimeWarningLimitStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        if lifetimeWarningLimitStatus {
//            operand.append(lifetimeWarningLimit)
//        }
//        sendCommand(.setLifetimeWarningLimit, operand: operand) { message in
//            self.lifetimeWarningLimitMessage = (self.lifetimeWarningLimitMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getReservoirLevelWarningLimit() {
//        reservoirLevelWarningLimitMessage = nil
//        sendCommand(.getReservoirLevelWarningLimit) { message in
//            self.reservoirLevelWarningLimitMessage = (self.reservoirLevelWarningLimitMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setReservoirLevelWarningLimit() {
//        reservoirLevelWarningLimitMessage = nil
//        var operand = reservoirLevelWarningLimitStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        if reservoirLevelWarningLimitStatus {
//            operand.append(reservoirLevelWarningLimit.sfloat)
//        }
//        sendCommand(.setReservoirLevelWarningLimit, operand: operand) { message in
//            self.reservoirLevelWarningLimitMessage = (self.reservoirLevelWarningLimitMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func getInsulinDeliveryStartSoundParameters() {
//        insulinDeliveryStartSoundParametersMessage = nil
//        sendCommand(.getInsulinDeliveryStartSoundParameters) { message in
//            self.insulinDeliveryStartSoundParametersMessage = (self.insulinDeliveryStartSoundParametersMessage ?? "") + "\n\n" + message
//        }
//    }
//    
//    func setInsulinDeliveryStartSoundParameters() {
//        insulinDeliveryStartSoundParametersMessage = nil
//        let operand = insulinDeliveryStartSoundStatus ? Data(IDDStatusFlag.enabled.rawValue) : Data(IDDStatusFlag.disabled.rawValue)
//        sendCommand(.setInsulinDeliveryStartSoundParameters, operand: operand) { message in
//            self.insulinDeliveryStartSoundParametersMessage = (self.insulinDeliveryStartSoundParametersMessage ?? "") + "\n\n" + message
//        }
//    }
    
//    func sendCommand(_ opcode: IDCommandControlPointOpcode, operand: Data? = nil, completion: @escaping MessageCompletion) {
//        insulinDeliveryController?.sendCommand(opcode: opcode, operand: operand, completion: completion)
//    }
}

// MARK: - RACP Commands
extension InsulinDeliveryClientViewModel {
    private var minRecordNumber: RecordNumber? {
        UInt32(minRecordNumberString)
    }
    
    private var maxRecordNumber: RecordNumber? {
        UInt32(maxRecordNumberString)
    }

    func requestStoredRecords() {
        racpMessage = nil
        insulinDeliveryController?.requestStoredRecords(racpOperator: racpOperator, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber) { message in
            self.racpMessage = (self.racpMessage ?? "") + "\n\n" + message
        }
    }

    func deleteStoredRecords() {
        racpMessage = nil
        insulinDeliveryController?.deleteStoredRecords(racpOperator: racpOperator, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber) { message in
            self.racpMessage = (self.racpMessage ?? "") + "\n\n" + message
        }
    }

    func requestNumberOfStoredRecords() {
        racpMessage = nil
        insulinDeliveryController?.requestNumberOfStoredRecords(racpOperator: racpOperator, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber) { message in
            self.racpMessage = (self.racpMessage ?? "") + "\n\n" + message
        }
    }

    func abortOperation() {
        racpMessage = nil
        insulinDeliveryController?.racpAbortOperation() { message in
            self.racpMessage = (self.racpMessage ?? "") + "\n\n" + message
        }
    }
}
