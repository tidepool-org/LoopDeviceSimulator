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

    /// Advertised local name, from the root list's Server Name field.
    var serverName: String? = nil

    /// Two pages like the CGM: the HUD lands first, the full configuration is one swipe to the right.
    @State private var page = 0
    /// A sheet rather than a push: pushing would make this view disappear and stop the server.
    @State private var isShowingLog = false

    var body: some View {
        TabView(selection: $page) {
            InsulinDeliveryPumpHUDView(viewModel: viewModel)
                .tag(0)
            insulinDeliveryServer
                .tag(1)
        }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            // The page control sits at the TabView's bottom edge; lift it clear of the test-tool notice bar.
            .padding(.bottom, 20)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingLog = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Session Log")
                }
            }
            .sheet(isPresented: $isShowingLog) {
                NavigationStack {
                    SessionLogView()
                }
            }
            .onAppear(perform: { viewModel.startServer(serverName: serverName) })
            .onDisappear(perform: { viewModel.stopServer() })
    }

    private var insulinDeliveryServer: some View {
        VStack {
            RoundedCardScrollView(title: "Insulin Delivery Server") {
                Text("Number of Subscribed Devices: \(viewModel.numberOfSubscribedDevices)")
                insulinDeliveryServerControls
            }
            // The page control overlays the bottom of the TabView; keep the last card's controls above it.
            .contentMargins(.bottom, InsulinDeliveryPumpHUDView.pageControlClearance, for: .scrollContent)
        }
    }
    
    @ViewBuilder
    private var insulinDeliveryServerControls: some View {
        RoundedCard(title: "Delivery State") {
            RoundedCardValueRow(label: "Therapy State", value: viewModel.therapyStateString)
            RoundedCardValueRow(label: "Operational State", value: viewModel.operationalStateString)
            RoundedCardValueRow(label: "Reservoir Level", value: viewModel.reservoirLevelString)
            RoundedCardValueRow(label: "Basal delivery", value: viewModel.basalDeliveryString)
            RoundedCardValueRow(label: "Is Temp Basal", value: viewModel.isTempBasalString)
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
            VStack {
                RoundedCardToggleRow(label: "Authorization Control Required", enabled: $viewModel.isAuthorizationControlEnabled, toggleTintColor: .accentColor)
                RoundedCardValueRow(label: "Secure Session", value: viewModel.isSecurityEstablished ? "established" : "not established", highlightValue: viewModel.isSecurityEstablished)
                RoundedCardValueRow(label: "Pump Key", value: viewModel.oobRandomNumberString)
                // The session key and nonce sequence survive relaunches and switching to the CGM server.
                Button(action: viewModel.forgetPairing) {
                    Text("Forget Pairing")
                }
            }
        }

        RoundedCard(title: "Error Handling", footer: "Report Reservoir Once makes the next Status carry the typed level instead of the real one, indicated at once to a subscribed controller or served on its next read; the pump's valid range is 0 up to its fill level, so -1 and 999 are both out of range. The level after that is the real one again.") {
            RoundedCardToggleRow(label: "Server Busy", enabled: $viewModel.isServerBusy, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Procedure Already In Progress", enabled: $viewModel.procedureAlreadyInProgress, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Out of Range Schedule", enabled: $viewModel.outOfRangeSchedule, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Ready to Disconnect", enabled: $viewModel.readyToDisconnect, toggleTintColor: .accentColor)
            Divider()
            HStack {
                Text("Out-of-range reservoir")
                Spacer()
                TextField("U", text: $viewModel.outOfRangeReservoirEntry)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("U")
            }
            Button("Report Reservoir Once", action: viewModel.reportOutOfRangeReservoir)
                .disabled(!viewModel.isPumpPoweredOn)
            if let message = viewModel.outOfRangeMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        pumpFeatureCard

        FaultInjectionCard(host: viewModel)

        RoundedCard(title: "Controls") {
            triggerAnnunciations
            sendSecureMessage
        }
    }
    
    /// Every flag the pump's Feature characteristic can advertise. Turning one off presents a pump without that
    /// capability; the Feature is read, not indicated, so a controller sees the change on its next connection.
    private var pumpFeatureCard: some View {
        RoundedCard(title: "Pump Feature", footer: "What the pump advertises in its IDD Features characteristic. The controller reads it once per connection, so reconnect after a change. Turning E2E Protection off also stops the pump adding E2E counters and CRCs. Kept across relaunches.") {
            ForEach(InsulinDeliveryServerViewModel.namedFeatures, id: \.name) { entry in
                RoundedCardToggleRow(
                    label: entry.name,
                    enabled: Binding(
                        get: { viewModel.isFeatureEnabled(entry.flag) },
                        set: { viewModel.setFeature(entry.flag, enabled: $0) }
                    ),
                    toggleTintColor: .accentColor
                )
            }
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
