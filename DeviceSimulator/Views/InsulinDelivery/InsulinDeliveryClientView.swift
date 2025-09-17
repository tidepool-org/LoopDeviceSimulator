//
//  InsulinDeliveryClientView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import InsulinDeliveryServiceKit

struct InsulinDeliveryClientView: View {
    @ObservedObject var viewModel: InsulinDeliveryClientViewModel
    
    var body: some View {
        Group {
            if viewModel.isPeripheralConnected {
                VStack {
                    RoundedCardScrollView(title: "Insulin Delivery Client") {
                        RoundedCard {
                            Button(action: viewModel.stopClient) {
                                Text(viewModel.connectedMessage)
                                Spacer()
                            }
                            Divider()
                            Button(action: viewModel.switchToPeripheralList) {
                                Text("Display Peripheral List")
                                Spacer()
                            }
                            Divider()
                            Button(action: viewModel.clearConsole) {
                                Text("Clear Console")
                                Spacer()
                            }
                        }
                        
                        configurationControls
                        
                        RoundedCard {
                            readCharacteristics
                        }
                        
                        generalControls
                        
                        statusReaderControls
                        
                        selectedStatus
                        
                        commandControls
                        
                        racpControls
                        
                        RoundedCard {
                            racpCommands
                        }
                        
                        RoundedCard(title: "Console") {
                            TextEditor(text: .constant(viewModel.consoleMessages))
                        }
                    }
                }
            } else {
                deviceList
            }
        }
        .onAppear(perform: { viewModel.startClient() })
        .onDisappear(perform: { viewModel.stopClient() })
    }
    
    @ViewBuilder
    private var configurationControls: some View {
        RoundedCard(title: "Configure Indications/Notifications") {
            Toggle("Configure Status", isOn: $viewModel.indicationsEnabledStatus)
            Toggle("Configure Status Changed", isOn: $viewModel.indicationsEnabledStatusChanged)
            Toggle("Configure Annunciation Status", isOn: $viewModel.indicationsEnabledAnnunciationStatus)
            Toggle("Configure Status Reader Control Point", isOn: $viewModel.indicationsEnabledStatusReaderControlPoint)
            Toggle("Configure Command Control Point", isOn: $viewModel.indicationsEnabledCommandControlPoint)
            Toggle("Configure Command Data", isOn: $viewModel.indicationsEnabledCommandData)
            Toggle("Configure Recoard Access Control Point", isOn: $viewModel.indicationsEnabledRecordAccessControlPoint)
            Toggle("Configure History Data", isOn: $viewModel.indicationsEnabledHistoryData)
            Toggle("Configure Device time Control Point", isOn: $viewModel.indicationsEnabledDeviceTimeControlPoint)
            if viewModel.indicationsEnabledMessageStatus != nil ||
                viewModel.indicationsEnabledMessageStatusChanged != nil ||
                viewModel.indicationsEnabledMessageAnnunciationStatus != nil ||
                viewModel.indicationsEnabledMessageStatusReaderControlPoint != nil ||
                viewModel.indicationsEnabledMessageCommandControlPoint != nil ||
                viewModel.indicationsEnabledMessageCommandData != nil ||
                viewModel.indicationsEnabledMessageRecordAccessControlPoint != nil ||
                viewModel.indicationsEnabledMessageHistoryData != nil ||
                viewModel.indicationsEnabledMessageDeviceTimeControlPoint != nil
            {
                MessageView(message: "Status: \(String(describing: viewModel.indicationsEnabledMessageStatus)) Status Changed: \(String(describing: viewModel.indicationsEnabledMessageStatusChanged))  Annunciation Status: \(String(describing: viewModel.indicationsEnabledMessageAnnunciationStatus)) Status Reader: \(String(describing: viewModel.indicationsEnabledMessageStatusReaderControlPoint)) Command Control Point: \(String(describing: viewModel.indicationsEnabledMessageCommandControlPoint)) Command Data: \(String(describing: viewModel.indicationsEnabledMessageCommandData)) Recoard Access Control Point: \(String(describing: viewModel.indicationsEnabledMessageRecordAccessControlPoint)) History Data: \(String(describing: viewModel.indicationsEnabledMessageHistoryData)) Device Time Control Point: \(String(describing: viewModel.indicationsEnabledMessageDeviceTimeControlPoint))")
            }
        }
    }
    
    @ViewBuilder
    private var readCharacteristics: some View {
        VStack {
            readIDDFeatureCharacteristic
            Divider()
            readIDDStatusCharacteristic
            Divider()
            readIDDStatusChangedCharacteristic
            Divider()
            readIDDAnnunciationStatusCharacteristic
            Divider()
            readDeviceTimeCharacteristic
        }
    }
        
    private var readIDDFeatureCharacteristic: some View {
        VStack {
            Button(action: viewModel.readIDDFeatureCharacteristic) {
                Text("Read IDD Feature Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageIDDFeatureCharacteristic {
                MessageView(message: message)
            }
        }
    }
    
    private var readIDDStatusCharacteristic: some View {
        VStack {
            Button(action: viewModel.readIDDStatusCharacteristic) {
                Text("Read IDD Status Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageIDDStatusCharacteristic {
                MessageView(message: message)
            }
            if let message = viewModel.indicationsMessageStatus {
                MessageView(message: message)
            }
        }
    }
    
    private var readIDDStatusChangedCharacteristic: some View {
        VStack {
            Button(action: viewModel.readIDDStatusChangedCharacteristic) {
                Text("Read IDD Status Changed Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageIDDStatusChangedCharacteristic {
                MessageView(message: message)
            }
            if let message = viewModel.indicationsMessageStatusChanged {
                MessageView(message: message)
            }
        }
    }
    
    private var readIDDAnnunciationStatusCharacteristic: some View {
        VStack {
            Button(action: viewModel.readIDDAnnunciationStatusCharacteristic) {
                Text("Read IDD Annunciation Status Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageIDDAnnunciationStatusCharacteristic {
                MessageView(message: message)
            }
            if let message = viewModel.indicationsMessageAnnunciationStatus {
                MessageView(message: message)
            }
        }
    }
    
    private var readDeviceTimeCharacteristic: some View {
        VStack {
            Button(action: viewModel.readDeviceTimeCharacteristic) {
                Text("Read Device Time Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageDeviceTimeCharacteristic {
                MessageView(message: message)
            }
            if let message = viewModel.indicationsMessageDeviceTime {
                MessageView(message: message)
            }
        }
    }
    
    private var generalControls: some View {
        RoundedCard() {
            setDeviceTime
            Divider()
            playBeepSound
        }
    }
    
    private var setDeviceTime: some View {
        VStack {
            Button(action: viewModel.setDeviceTime) {
                Text("Set Device Time")
            }
            .padding()
            if let message = viewModel.setDeviceTimeMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var playBeepSound: some View {
        VStack {
            Button(action: viewModel.playBeepSound) {
                Text("Play Beep Sound")
            }
            .padding()
            if let message = viewModel.playBeepMessage {
                MessageView(message: message)
            }
        }
    }
    
    @ViewBuilder
    private var selectedStatus: some View {
        RoundedCard(title: "Get Selected Status Information") {
            Toggle("Status", isOn: $viewModel.selectedStatus)
            Toggle("Status Changed", isOn: $viewModel.selectedStatusChanged)
            Toggle("Annunciation Status", isOn: $viewModel.selectedAnnunciationStatus)
            Toggle("Active Basal Rate Delivery", isOn: $viewModel.selectedActiveBasalRate)
            Toggle("Active Bolus IDs", isOn: $viewModel.selectedActiveBolusIDs)
            Toggle("Active Bolus Delivery (Programmed)", isOn: $viewModel.selectedActiveBolusProgrammed)
            Toggle("Active Bolus Delivery (Delivered)", isOn: $viewModel.selectedActiveBolusDelivered)
            Toggle("Active Bolus Delivery (Remaining)", isOn: $viewModel.selectedActiveBolusRemaining)
            Toggle("Available Boluses", isOn: $viewModel.selectedAvailableBolus)
            Toggle("Total Daily Insulin", isOn: $viewModel.selectedTotalDailyInsulin)
            Toggle("Get Delivered Insulin", isOn: $viewModel.selectedDeliveredInsulin)
            Button(action: viewModel.getSelectedStatusInformation) {
                Text("Get Selected Status")
            }
            .padding()
            if let message = viewModel.selectedStatusMessage {
                MessageView(message: message)
            }
        }
    }

    
    private var statusReaderControls: some View {
        RoundedCard(title: "Status Reader") {
            resetStatus
            getActiveBolusIDs
            getActiveBolusDelivery
            getActiveBasalDelivery
            getTotalDailyInsulinStatus
            getCounter
            getDeliveredInsulin
            getInsulinOnBoard
        }
    }
    
    private var resetStatus: some View {
        VStack {
            statusToReset
            Button(action: { viewModel.resetStatus() }) {
                Text("Reset Status")
            }
            if let message = viewModel.resetStatusMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var statusToReset: some View {
        MockPumpStatusView(statusFlag: $viewModel.statusToReset)
    }

    struct MockPumpStatusView: View {
        @Binding var statusFlag: IDStatusChangedFlag
        
        var body: some View {
            HStack {
                Picker("Reset status:", selection: $statusFlag) {
                    ForEach(statusFlags, id: \.self) { statusFlag in
                        Text(pickerValue(for: statusFlag)).tag(statusFlag)
                    }
                }
            }
        }
        
        private func pickerValue(for statusFlag: IDStatusChangedFlag) -> String {
            return "\(statusFlag.name)"
        }
        
        private var statusFlags: [IDStatusChangedFlag] {
            [.allFlags,
             .therapyControlStateChanged,
             .operationalStateChanged,
             .reservoirStatusChanged,
             .annunciationStatusChanged,
             .totalDailyInsulinStatusChanged,
             .activeBasalRateStatusChanged,
             .activeBolusStatusChanged,
             .historyEventRecordedChanged]
        }
    }
    
    private var getActiveBolusIDs: some View {
        VStack {
            Divider()
            Button(action: viewModel.getActiveBolusIDs ) {
                Text("Get Active Bolus IDs")
            }
            if let message = viewModel.getActiveBolusIDsMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getActiveBolusDelivery: some View {
        VStack {
            Divider()
            HStack {
                Text("Bolus ID")
                Spacer()
                NumberEntryEntryView(title: "Enter ID", number: $viewModel.bolusIDString)
            }
            SingleSelectionCheckList<BolusValueSelection>(items: BolusValueSelection.allCases, selectedItem: $viewModel.bolusValueSelection)
            Button(action: { viewModel.getActiveBolusDelivery() }) {
                Text("Get Active Bolus Delivery")
            }
            if let message = viewModel.getActiveBolusDeliveryMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getActiveBasalDelivery: some View {
        VStack {
            Divider()
            Button(action: viewModel.getActiveBasalDelivery) {
                Text("Get Active Basal Delivery")
            }
            if let message = viewModel.getActiveBasalDeliveryMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getTotalDailyInsulinStatus: some View {
        VStack {
            Divider()
            Button(action: viewModel.getTotalDailyInsulinStatus) {
                Text("Get Total Daily Insulin Status")
            }
            if let message = viewModel.getTotalDailyInsulinStatusMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getCounter: some View {
        VStack {
            Divider()
            SingleSelectionCheckList<CounterType>(items: CounterType.allCases, selectedItem: $viewModel.counterType)
            SingleSelectionCheckList<CounterValueSelection>(items: CounterValueSelection.allCases, selectedItem: $viewModel.counterValueSelection)
            Button(action: viewModel.getCounter) {
                Text("Get Counter")
            }
            if let message = viewModel.getCounterMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getDeliveredInsulin: some View {
        VStack {
            Divider()
            Button(action: viewModel.getDeliveredInsulin) {
                Text("Get Delivered Insulin")
            }
            if let message = viewModel.getDeliveredInsulinMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var getInsulinOnBoard: some View {
        VStack {
            Divider()
            Button(action: viewModel.getInsulinOnBoard) {
                Text("Get Insulin on Board")
            }
            if let message = viewModel.getInsulinOnBoardMessage {
                MessageView(message: message)
            }
        }.padding(.vertical)
    }
    
    private var commandControls: some View {
        RoundedCard(title: "IDD Command Control Point") {
            setTherapyControlState
            setFlightMode
            annunciationControls
            basalProfileControls
            tempBasalControls
            bolusControls
            getAvailableBoluses
            getTemplateStatusDetails
            activateProfileTemplateControls
            getActivatedProfiles
            primingControls
            setInitialResevoirFillLevel
            maxBolusAmountControls
            maxBasalRateControls
            localBolusControls
            autoStopControls
            resetAutoStopTimeoutControls
            suspendSignalControls
            lifetimelWarningLimitControls
            reservoirLevelWarningLimitControls
            insulinDeliveryStartSoundControls
        }
    }
    
    private var setTherapyControlState: some View {
        VStack {
            SingleSelectionCheckList<InsulinTherapyControlState>(items: InsulinTherapyControlState.allCases, selectedItem: $viewModel.therapyControlState)
            Button(action: viewModel.setTherapyControlState) {
                Text("Set Therapy Control State")
            }
            if let message = viewModel.setTherapyControlStateMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var setFlightMode: some View {
        VStack {
            Divider()
            Button(action: viewModel.setFlightMode) {
                Text("Set Flight Mode")
            }
            if let message = viewModel.setFlightModeMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var annunciationControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Annunciation ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Annunication ID", number: $viewModel.annunciationIDString)
            }
            Button(action: viewModel.snoozeAnnunciation ) {
                Text("Snooze Annunciation")
            }
            Button(action: viewModel.confirmAnnunciation ) {
                Text("Confirm Annunciation")
            }
            if let message = viewModel.annunciationMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var basalProfileControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Basal Profile")
                Spacer()
                NumberEntryEntryView(title: "Enter Profile Number", number: $viewModel.basalProfileNumberString)
            }
            Button(action: viewModel.readBasalProfile ) {
                Text("Read Basal Profile")
            }
            Button(action: viewModel.writeBasalProfile ) {
                Text("Write Basal Profile")
            }
            if let message = viewModel.basalRateProfileMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var tempBasalControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Temp Basal")
                Spacer()
                NumberEntryEntryView(title: "Enter Amount", number: $viewModel.tempBasalAmountString)
            }
            Toggle("Replace Temp Basal", isOn: $viewModel.replaceExistingTempBasal)
            Button(action: viewModel.setTemplBasal) {
                Text("Set Temp Basal")
            }
            Button(action: viewModel.cancelTempBasal) {
                Text("Cancel Temp Basal")
            }
            if let message = viewModel.tempBasalMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var bolusControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Bolus")
                Spacer()
                NumberEntryEntryView(title: "Enter Amount", number: $viewModel.bolusAmountString)
            }
            Button(action: viewModel.setBolus) {
                Text("Set Bolus")
            }
            HStack {
                Text("Bolus ID")
                Spacer()
                NumberEntryEntryView(title: "Enter ID", number: $viewModel.bolusIDString)
            }
            Button(action: viewModel.cancelBolus) {
                Text("Cancel Bolus")
            }
            if let message = viewModel.bolusMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getAvailableBoluses: some View {
        VStack {
            Divider()
            Button(action: viewModel.getAvailableBoluses) {
                Text("Get Available Boluses")
            }
            if let message = viewModel.getAvailableBolusesMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getTemplateStatusDetails: some View {
        VStack {
            Divider()
            Button(action: viewModel.getTemplateStatusDetails) {
                Text("Get Template Status and Details")
            }
            if let message = viewModel.getTemplateStatusDetailsMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var activateProfileTemplateControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Profile Template")
                Spacer()
                NumberEntryEntryView(title: "Enter Number", number: $viewModel.profileTemplateNumberString)
            }
            Button(action: viewModel.resetTemplateStatus) {
                Text("Reset Profile Template")
            }
            Button(action: viewModel.activateProfileTemplates) {
                Text("Activate Profile Template")
            }
            if let message = viewModel.activateProfilesMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getActivatedProfiles: some View {
        VStack {
            Divider()
            Button(action: viewModel.getActivatedProfiles) {
                Text("Get Activated Profiles")
            }
            if let message = viewModel.getActivatedProfilesMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var primingControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Priming")
                Spacer()
                NumberEntryEntryView(title: "Enter Amount", number: $viewModel.primingAmountString)
            }
            Button(action: viewModel.startPriming) {
                Text("Start Priming")
            }
            Button(action: viewModel.stopPriming) {
                Text("Stop Priming")
            }
            if let message = viewModel.primingMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var setInitialResevoirFillLevel: some View {
        VStack {
            Divider()
            HStack {
                Text("Initial Reservoir Fill")
                Spacer()
                NumberEntryEntryView(title: "Enter value", number: $viewModel.initialReservoirFillLevelString)
            }
            Button(action: viewModel.setInitialReservoirFillLevel) {
                Text("Set Initial Reservoir Fill Level")
            }
            if let message = viewModel.setInitialReservoirFillMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var maxBolusAmountControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Max Bolus")
                Spacer()
                NumberEntryEntryView(title: "Enter Amount", number: $viewModel.maxBolusAmountString)
            }
            Button(action: viewModel.getMaxBolusAmount) {
                Text("Get Max Bolus Amount")
            }
            Button(action: viewModel.setMaxBolusAmount) {
                Text("Set Max Bolus Amount")
            }
            if let message = viewModel.maxBolusAmountMessage {
                MessageView(message: message)
            }
        }
    }

    private var maxBasalRateControls: some View {
        VStack {
            Divider()
            HStack {
                Text("Max Basal Rate Amount")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.maxBasalRateAmountString)
            }
            Button(action: viewModel.getMaxBasalRateAmount) {
                Text("Get Max Basal Rate")
            }
            .padding(.vertical)
            Button(action: viewModel.setMaxBasalRateAmount) {
                Text("Set Max Basal Rate")
            }
            .padding(.vertical)
            if let message = viewModel.maxBasalRateMessage {
                MessageView(message: message)
            }
        }
    }

    private var localBolusControls: some View {
        VStack {
            Divider()
            Toggle("Local Bolus Status", isOn: $viewModel.localBolusStatus)
            HStack {
                Text("Local Bolus Step Size")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.localBolusStepValueString)
            }
            HStack {
                Text("Local Bolus Max Amount")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.localBolusMaxAmountString)
            }
            Button(action: viewModel.getLocalBolusParameters) {
                Text("Get Local Bolus Parameters")
            }
            .padding(.vertical)
            Button(action: viewModel.setLocalBolusParameters) {
                Text("Set Local Bolus Parameters")
            }
            .padding(.vertical)
            if let message = viewModel.localBolusMessage {
                MessageView(message: message)
            }
        }
    }

    private var autoStopControls: some View {
        VStack {
            Divider()
            Toggle("Automatic Stop Status", isOn: $viewModel.autoStopStatus)
            HStack {
                Text("Max Automatic Stop Timeout")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.maxAutoStopTimeoutString)
            }
            Button(action: viewModel.getAutoStopParameters) {
                Text("Get Automatic Stop Parameters")
            }
            .padding(.vertical)
            Button(action: viewModel.setAutoStopParameters) {
                Text("Set Automatic Stop Parameters")
            }
            .padding(.vertical)
            if let message = viewModel.autoStopMessage {
                MessageView(message: message)
            }
        }
    }

    private var resetAutoStopTimeoutControls: some View {
        VStack {
            HStack {
                Text("Last User Interaction")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.lastUserInteractionString)
            }
            Button(action: viewModel.resetAutoStopTimeout) {
                Text("Reset Automatic Stop Timeout")
            }
            .padding(.vertical)
            if let message = viewModel.resetAutoStopMessage {
                MessageView(message: message)
            }
        }
    }

    private var suspendSignalControls: some View {
        VStack {
            Divider()
            Toggle("Suspend Signal Status", isOn: $viewModel.suspendSignalStatus)
            Toggle("Suspend Signal Repeats", isOn: $viewModel.suspendSignalRepeats)
            HStack {
                Text("Suspend Signal Start Time")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.suspendSignalStartTimeString)
            }
            HStack {
                Text("Suspend Signal Duration")
                NumberEntryEntryView(title: "Enter value", number: $viewModel.suspendSignalDurationString)
            }
            Button(action: viewModel.getSuspendSignalParameters) {
                Text("Get Suspend Signal Parameters")
            }
            .padding(.vertical)
            Button(action: viewModel.setSuspendSignalParameters) {
                Text("Set Suspend Signal Parameters")
            }
            .padding(.vertical)
            if let message = viewModel.suspendSignalMessage {
                MessageView(message: message)
            }
        }
    }

    private var lifetimelWarningLimitControls: some View {
        VStack {
            Divider()
            Toggle("Lifetime Warning Limit Status", isOn: $viewModel.lifetimeWarningLimitStatus)
            HStack {
                Text("Lifetime Warning Limit (days)")
                NumberEntryEntryView(title: "Enter Limit", number: $viewModel.lifetimeWarningLimitString)
            }
            Button(action: viewModel.getLifetimeWarningLimit) {
                Text("Get Lifetime Warning Limit")
            }
            .padding(.vertical)
            Button(action: viewModel.setLifetimeWarningLimit) {
                Text("Set Lifetime Level Warning Limit")
            }
            .padding(.vertical)
            if let message = viewModel.lifetimeWarningLimitMessage {
                MessageView(message: message)
            }
        }
    }

    private var reservoirLevelWarningLimitControls: some View {
        VStack {
            Divider()
            Toggle("Reservoir Level Warning Limit Status", isOn: $viewModel.reservoirLevelWarningLimitStatus)
            HStack {
                Text("Reservoir Level Warning Limit (IU)")
                NumberEntryEntryView(title: "Enter Limit", number: $viewModel.reservoirLevelWarningLimitString)
            }
            Button(action: viewModel.getReservoirLevelWarningLimit) {
                Text("Get Reservoir Level Warning Limit")
            }
            .padding(.vertical)
            Button(action: viewModel.setReservoirLevelWarningLimit) {
                Text("Set Reservoir Level Warning Limit")
            }
            .padding(.vertical)
            if let message = viewModel.reservoirLevelWarningLimitMessage {
                MessageView(message: message)
            }
        }
    }

    private var insulinDeliveryStartSoundControls: some View {
        VStack {
            Divider()
            Toggle("Insulin Delivery Start Sound Status", isOn: $viewModel.insulinDeliveryStartSoundStatus)
            Button(action: viewModel.getInsulinDeliveryStartSoundParameters) {
                Text("Get Insulin Delivery Start Sound Parameters")
            }
            .padding(.vertical)
            Button(action: viewModel.setInsulinDeliveryStartSoundParameters) {
                Text("Set Insulin Delivery Start Sound Parameters")
            }
            .padding(.vertical)
            if let message = viewModel.insulinDeliveryStartSoundParametersMessage {
                MessageView(message: message)
            }
        }
    }
    
    @ViewBuilder
    private var racpControls: some View {
        RoundedCard(title: "Stored Records") {
            SingleSelectionCheckList<IDRACPOperator>(items: IDRACPOperator.allCases, selectedItem: $viewModel.racpOperator)
            Divider()

            HStack {
                Text("Min Record #")
                minRecordNumberEntry
            }
            Divider()

            HStack {
                Text("Max Record #")
                maxRecordNumberEntry
            }
        }
    }
    
    @ViewBuilder
    private var racpCommands: some View {
        VStack {
            Button(action: viewModel.requestStoredRecords) {
                Text("Request Stored Records (Record Number)")
            }
            .padding()
            Button(action: viewModel.requestNumberOfStoredRecords) {
                Text("Request Number of Stored Records (Record Number)")
            }
            .padding()
            Button(action: viewModel.deleteStoredRecords) {
                Text("Delete Stored Records")
            }
            .padding()
            Button(action: viewModel.abortOperation) {
                Text("Abort Operation Records")
            }
            .padding()
            if let message = viewModel.racpMessage {
                Divider()
                MessageView(message: message)
            }
        }
    }
    
    private var minRecordNumberEntry: some View {
        NumberEntryEntryView(title: "Enter Min Record Number", number: $viewModel.minRecordNumberString)
    }

    private var maxRecordNumberEntry: some View {
        NumberEntryEntryView(title: "Enter Max Record Number", number: $viewModel.maxRecordNumberString)
    }

    @ViewBuilder
    private var deviceList: some View {
        RoundedCardScrollView(title: "Discovered Peripherals") {
            RoundedCard() {
                Button(action: viewModel.refreshList) {
                    Text("Refresh List")
                    Spacer()
                }
            }
            Text("Select Insulin Delivery Service to connect")
            ForEach(viewModel.deviceList, id:\.self) { device in
                RoundedCard() {
                    Button(action: { viewModel.connectToDevice(device) }) {
                        DeviceView(device: device)
                    }
                }
            }
        }
    }
}

extension IDStatusChangedFlag {
    fileprivate var name: String {
        switch self {
        case .allFlags: return "allFlags"
        case .therapyControlStateChanged: return "therapyControlStateChanged"
        case .operationalStateChanged: return "operationalStateChanged"
        case .reservoirStatusChanged: return "reservoirStatusChanged"
        case .annunciationStatusChanged: return "annunciationStatusChanged"
        case .totalDailyInsulinStatusChanged: return "totalDailyInsulinStatusChanged"
        case .activeBasalRateStatusChanged: return "activeBasalRateStatusChanged"
        case .activeBolusStatusChanged: return "activeBolusStatusChanged"
        case .historyEventRecordedChanged: return "historyEventRecordedChanged"
        default: return ""
        }
    }
}

struct InsulinDeliveryClientView_Previews: PreviewProvider {
    static var previews: some View {
        InsulinDeliveryClientView(viewModel: InsulinDeliveryClientViewModel())
    }
}
