//
//  InsulinDeliveryServerView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import InsulinDeliveryServiceKit

struct InsulinDeliveryServerView: View {
    @Bindable var viewModel: InsulinDeliveryServerViewModel

    var body: some View {
        insulinDeliveryServer
            .onAppear(perform: { viewModel.startServer() })
            .onDisappear(perform: { viewModel.stopServer() })
    }

    private var insulinDeliveryServer: some View {
        VStack {
            RoundedCardScrollView(title: "Insulin Delivery Server") {
                Text("Number of Subscribed Devices: \(viewModel.numberOfSubscribedDevices)")
                insulinDeliveryServerControls
            }
        }
    }
    
    @ViewBuilder
    private var insulinDeliveryServerControls: some View {
        RoundedCard(title: "Delivery State") {
            RoundedCardValueRow(label: "Therapy State", value: viewModel.therapyStateString)
            RoundedCardValueRow(label: "Operational State", value: viewModel.operationalStateString)
            RoundedCardValueRow(label: "Reservoir Level", value: viewModel.reservoirLevelString)
            RoundedCardValueRow(label: "Basal delivery", value: viewModel.basalDeliveryString)
            RoundedCardValueRow(label: "Bolus delivery", value: viewModel.bolusDeliveryString)
        }
        
        RoundedCard {
            Button(action: viewModel.restartServer) {
                Text("Restart Server")
                    .multilineTextAlignment(.leading)
            }
            Divider()
            RoundedCardToggleRow(label: "Power On Pump", enabled: $viewModel.isPumpPoweredOn, toggleTintColor: .accentColor)
            Divider()
            RoundedCardToggleRow(label: "Pump behaviour", enabled: $viewModel.isPumpBehaviourEnabled, toggleTintColor: .accentColor)
            Divider()
            RoundedCardToggleRow(label: "E2E Protection Supported", enabled: $viewModel.isE2EProtectionSupported, toggleTintColor: .accentColor)
            Divider()
            VStack {
                RoundedCardToggleRow(label: "Authorization Control Required", enabled: $viewModel.isAuthorizationControlEnabled, toggleTintColor: .accentColor)
                RoundedCardValueRow(label: "Pump Key", value: viewModel.oobRandomNumberString)
            }
        }

        RoundedCard(title: "Error Handling") {
            RoundedCardToggleRow(label: "Server Busy", enabled: $viewModel.isServerBusy, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Procedure Already In Progress", enabled: $viewModel.procedureAlreadyInProgress, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Out of Range Schedule", enabled: $viewModel.outOfRangeSchedule, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Ready to Disconnect", enabled: $viewModel.readyToDisconnect, toggleTintColor: .accentColor)
        }
        
        RoundedCard(title: "Controls") {
            triggerAnnunciations
            sendSecureMessage
        }
    }
    
    private var triggerAnnunciations: some View {
        RoundedCard(title: "Annunciations") {
            mockPumpIssueAnnunciation
            Button(action: viewModel.issueAnnunciation) {
                Text("Issue Annunciation")
            }
        }
    }
    
    private var mockPumpIssueAnnunciation: some View {
        MockPumpIssueAnnunciationView(annunciation: $viewModel.annunciationTypeToIssue)
    }

    struct MockPumpIssueAnnunciationView: View {
        @Binding var annunciation: AnnunciationType?
        
        var body: some View {
            HStack {
                Picker("Issue annunciation:", selection: $annunciation) {
                    ForEach(annunciations, id: \.self) { annunciation in
                        Text(pickerValue(for: annunciation)).tag(annunciation)
                    }
                }
            }
        }
        
        private func pickerValue(for annunciation: AnnunciationType?) -> String {
            guard let annunciation = annunciation else {
                return "none"
            }

            return "\(annunciation.description)"
        }
        
        private var annunciations: [AnnunciationType?] {
            [nil] + (AnnunciationType.allCases.sorted {$0.description < $1.description})
        }
    }
    
    private var sendSecureMessage: some View {
        RoundedCard(title: "Secure Messaging") {
            Button(action: viewModel.sendSecureIndication) {
                Text("Send secure indication")
            }
        }
    }
}

struct InsulinDeliveryServerView_Previews: PreviewProvider {
    static var previews: some View {
        InsulinDeliveryServerView(viewModel: InsulinDeliveryServerViewModel())
    }
}
