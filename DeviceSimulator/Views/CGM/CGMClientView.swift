//
//  CGMClientView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI
import ContinuousGlucoseMonitorServiceKit

struct CGMClientView: View {
    @ObservedObject var viewModel: CGMClientViewModel

    var body: some View {
        Group {
            if viewModel.isPeripheralConnected {
                RoundedCardScrollView(title: "CGM Collector Client") {
                    connectionCard
                    configurationCard
                    authorizationCard
                    lastMeasurementCard
                    readCard
                    sessionCard
                    specificOpsCard
                    racpCard
                    ConsoleView(title: "Console", output: viewModel.consoleMessages)
                }
            } else {
                DeviceListView(
                    title: "Discovered CGM Sensors",
                    prompt: "Select a CGM Service peripheral to connect",
                    devices: viewModel.deviceList,
                    onRefresh: viewModel.refreshList,
                    onSelect: viewModel.connectToDevice
                )
            }
        }
        .onAppear(perform: { viewModel.startClient() })
        .onDisappear(perform: { viewModel.stopClient() })
    }

    private var connectionCard: some View {
        RoundedCard {
            // Disconnect forgets the sensor and goes back to scanning; stopClient is for leaving the screen.
            Button(action: viewModel.disconnect) {
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
    }

    private var configurationCard: some View {
        RoundedCard(title: "Configure Notifications/Indications") {
            Toggle("CGM Measurement (notify)", isOn: $viewModel.measurementNotificationsEnabled)
            Toggle("CGM Feature (indicate)", isOn: $viewModel.featureIndicationsEnabled)
            Toggle("Record Access Control Point (indicate)", isOn: $viewModel.racpIndicationsEnabled)
            Toggle("CGM Specific Ops Control Point (indicate)", isOn: $viewModel.cgmcpIndicationsEnabled)
            if let message = viewModel.configureMessage {
                MessageView(message: message)
            }
        }
    }

    /// ACS: run the key exchange, then route CGM traffic through AC Data In / Out. Needed whenever the
    /// sensor's Authorization Control toggle is on; harmless otherwise.
    private var authorizationCard: some View {
        RoundedCard(title: "Authorization Control (ACS)", footer: "With Authorization Control on, the sensor answers Insufficient Authorization on the plain CGM characteristics until the key exchange completes. Measurements then arrive encrypted on AC Data Out. The sensor key must match the one shown on the sensor (default \(CGMConstants.oobRandomNumber)); a different key makes the confirmation fail.") {
            RoundedCardValueRow(label: "Secure Session", value: viewModel.isSecurityEstablished ? "established" : "not established", highlightValue: viewModel.isSecurityEstablished)
            textRow("Sensor Key", text: $viewModel.sensorKeyEntry)
            Toggle("Use Secure Channel", isOn: $viewModel.usesSecureChannel)
                .disabled(!viewModel.isSecurityEstablished)
            Divider()
            HStack {
                Button("Establish Secure Session", action: viewModel.establishSecureSession)
                Spacer()
                Button("Invalidate Key", action: viewModel.invalidateKey)
                    .disabled(!viewModel.isSecurityEstablished)
            }
            .padding(.vertical, 4)
            if let message = viewModel.authorizationMessage {
                MessageView(message: message)
            }
        }
    }

    /// The most recent notified CGM Measurement, field by field, so a tester can watch readings arrive.
    private var lastMeasurementCard: some View {
        RoundedCard(title: "Last Measurement") {
            if viewModel.lastMeasurement == nil {
                MessageView(message: "No measurement notified yet. Enable CGM Measurement (notify) above and start a session on the sensor.")
            } else {
                RoundedCardValueRow(label: "Glucose", value: viewModel.lastGlucoseString, highlightValue: true)
                RoundedCardValueRow(label: "Trend", value: viewModel.lastTrendString)
                RoundedCardValueRow(label: "Quality", value: viewModel.lastQualityString)
                RoundedCardValueRow(label: "Time Offset", value: viewModel.lastTimeOffsetString)
                RoundedCardValueRow(label: "Sensor Status", value: viewModel.lastSensorStatusString)
                RoundedCardValueRow(label: "Received", value: viewModel.lastReceivedString)
                RoundedCardValueRow(label: "Records Received", value: "\(viewModel.measurementCount)")
                RoundedCardValueRow(label: "Unique Records", value: "\(viewModel.uniqueRecordCount)")
                RoundedCardValueRow(label: "Duplicates Skipped", value: "\(viewModel.duplicateCount)")
                if let message = viewModel.measurementMessage {
                    Divider()
                    MessageView(message: message)
                }
            }
        }
    }

    private var readCard: some View {
        RoundedCard(title: "Read Characteristics") {
            actionRow("Read CGM Feature", action: viewModel.readFeature, message: viewModel.featureMessage)
            Divider()
            actionRow("Read CGM Status", action: viewModel.readStatus, message: viewModel.statusMessage)
            Divider()
            actionRow("Read CGM Session Run Time", action: viewModel.readSessionRunTime, message: viewModel.sessionRunTimeMessage)
            Divider()
            actionRow("Read Device Information", action: viewModel.readDeviceInformation, message: viewModel.deviceInformationMessage)
            Divider()
            actionRow("Read Battery Level", action: viewModel.readBatteryLevel, message: viewModel.batteryMessage)
        }
    }

    private var sessionCard: some View {
        RoundedCard(title: "CGM Session Start Time") {
            actionRow("Read Session Start Time", action: viewModel.readSessionStartTime, message: viewModel.readSessionStartTimeMessage)
            Divider()
            actionRow("Write Session Start Time (now)", action: viewModel.writeSessionStartTime, message: viewModel.writeSessionStartTimeMessage)
        }
    }

    /// Every CGMCP request op code (CGMS Table 3.6) with the operand entries the selected one needs.
    private var specificOpsCard: some View {
        RoundedCard(title: "CGM Specific Ops Control Point", footer: "Enable the CGMCP indication first. The sensor implements Start/Stop Session; other op codes answer Op Code Not Supported until their phase lands.") {
            Picker("Op Code", selection: $viewModel.selectedSpecificOp) {
                ForEach(CGMSpecificOpsOpcode.requests, id: \.self) { opcode in
                    Text(opcode.name).tag(opcode)
                }
            }
            specificOpsOperandRows
            Button(action: viewModel.sendSelectedSpecificOp) {
                Text("Send \(viewModel.selectedSpecificOp.name)")
            }
            .padding(.vertical, 4)
            Divider()
            HStack {
                Button("Start Session", action: viewModel.startSession)
                Spacer()
                Button("Stop Session", action: viewModel.stopSession)
            }
            .padding(.vertical, 4)
            if let message = viewModel.cgmcpMessage {
                MessageView(message: message)
            }
        }
    }

    @ViewBuilder
    private var specificOpsOperandRows: some View {
        switch viewModel.specificOpsOperand {
        case .none:
            EmptyView()
        case .communicationIntervalMinutes:
            LabeledSegmentedPicker("Communication Interval (Off = no periodic notifications, Fastest = every measurement)", selection: $viewModel.communicationInterval)
        case .calibrationRecordNumber:
            numberRow("Record Number (65535 = last)", text: $viewModel.calibrationRecordNumberEntry)
        case .calibrationRecord:
            numberRow("Glucose (mg/dL)", text: $viewModel.calibrationGlucoseEntry)
        case .glucoseLevel:
            numberRow("Level (mg/dL)", text: $viewModel.alertLevelEntry)
        case .rateLevel:
            numberRow("Level (mg/dL/min)", text: $viewModel.alertLevelEntry)
        }
    }

    /// RACP op codes and operators (CGMS Tables 3.3–3.5); only the Time Offset filter is legal in CGMS.
    private var racpCard: some View {
        RoundedCard(title: "Record Access Control Point", footer: "Enable the RACP indication and the CGM Measurement notification first. Reported records arrive as measurement notifications before the Response Code; Backfill asks for everything after the last measurement seen. A record already received on this connection, live or in an earlier report, is counted as a duplicate and skipped.") {
            Button("Backfill Since Last Measurement", action: viewModel.backfillSinceLastMeasurement)
                .padding(.vertical, 4)
            RoundedCardValueRow(label: "Last Report", value: viewModel.reportedRecordsSummary)
            Divider()
            Picker("Op Code", selection: $viewModel.racpOpcode) {
                ForEach(CGMRACPOpcode.requests, id: \.self) { opcode in
                    Text(opcode.name).tag(opcode)
                }
            }
            if viewModel.racpOpcode != .abortOperation {
                Picker("Operator", selection: $viewModel.racpOperator) {
                    ForEach(CGMRACPOperator.requests, id: \.self) { racpOperator in
                        Text(racpOperator.name).tag(racpOperator)
                    }
                }
                if viewModel.racpNeedsMinimum {
                    numberRow("Minimum Time Offset (min)", text: $viewModel.racpMinimumEntry)
                }
                if viewModel.racpNeedsMaximum {
                    numberRow("Maximum Time Offset (min)", text: $viewModel.racpMaximumEntry)
                }
            }
            Button(action: viewModel.sendRACPRequest) {
                Text("Send \(viewModel.racpOpcode.name)")
            }
            .padding(.vertical, 4)
            if let message = viewModel.racpMessage {
                MessageView(message: message)
            }
        }
    }

    private func numberRow(_ label: String, text: Binding<String>) -> some View {
        entryRow(label, text: text, keyboardType: .decimalPad, maxLength: 7)
    }

    private func textRow(_ label: String, text: Binding<String>) -> some View {
        entryRow(label, text: text, keyboardType: .default, maxLength: 32)
    }

    private func entryRow(_ label: String, text: Binding<String>, keyboardType: UIKeyboardType, maxLength: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            DismissibleKeyboardTextField(
                text: text,
                placeholder: label,
                font: .preferredFont(forTextStyle: .headline),
                textColor: .blue,
                textAlignment: .right,
                keyboardType: keyboardType,
                shouldBecomeFirstResponder: false,
                maxLength: maxLength,
                doneButtonColor: UIColor(Color.accentColor),
                textFieldDidBeginEditing: nil
            )
        }
    }

    private func actionRow(_ title: String, action: @escaping () -> Void, message: String?) -> some View {
        VStack {
            Button(action: action) {
                Text(title)
            }
            .padding(.vertical, 4)
            if let message {
                MessageView(message: message)
            }
        }
    }
}

struct CGMClientView_Previews: PreviewProvider {
    static var previews: some View {
        CGMClientView(viewModel: CGMClientViewModel())
    }
}
