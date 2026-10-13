//
//  CGMServerView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI
import ContinuousGlucoseMonitorServiceKit

struct CGMServerView: View {
    @Bindable var viewModel: CGMServerViewModel

    /// Advertised local name, from the root list's Server Name field.
    var serverName: String? = nil

    var body: some View {
        cgmServer
            .onAppear {
                if viewModel.isSensorPoweredOn {
                    viewModel.startServer(serverName: serverName)
                }
            }
            .onDisappear(perform: { viewModel.stopServer() })
    }

    private var cgmServer: some View {
        VStack {
            RoundedCardScrollView(title: "CGM Sensor Server") {
                Text("Number of Subscribed Devices: \(viewModel.numberOfSubscribedDevices)")
                measurementCard
                recordsCard
                glucoseSourceCard
                sessionCard
                serverCard
                featureCard
                sensorStatusCard
                errorHandlingCard
            }
        }
    }

    private var measurementCard: some View {
        RoundedCard(title: "Measurements", footer: "Time Offset has one-minute resolution, so 5 s readings share an offset. Readings are notified to a subscribed collector.") {
            RoundedCardValueRow(label: "Last Glucose", value: viewModel.lastGlucoseString)
            RoundedCardValueRow(label: "Measurements This Session", value: "\(viewModel.measurementCount)")
            // Ticks once a second; the sensor's timer fire date is the single source of truth.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RoundedCardValueRow(label: "Next Measurement", value: countdown(to: viewModel.nextMeasurementDate, now: context.date))
            }
            Divider()
            labeledPicker("Measurement Interval", selection: $viewModel.measurementInterval)
            Divider()
            Button(action: viewModel.takeMeasurement) {
                Text("Measure Now")
            }
        }
    }

    private func countdown(to date: Date?, now: Date) -> String {
        guard let date else { return "session \(viewModel.sessionStateString)" }
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return remaining >= 60 ? "in \(remaining / 60) min \(remaining % 60) s" : "in \(remaining) s"
    }

    /// The measurement database behind RACP: every reading of the session, kept while the collector is away.
    private var recordsCard: some View {
        RoundedCard(title: "Stored Records", footer: "Every measurement is stored for RACP reports until the capacity is reached (oldest dropped first); a new session clears the database per CGMS §3.4.5. Backfill pretends the sensor ran unattended for the chosen span: one record per measurement interval from the selected glucose source is stored silently and the session start moves back by that span, so a collector can fetch them through RACP. Records per Notification packs several records into one notification during a report.") {
            RoundedCardValueRow(label: "Stored Records", value: "\(viewModel.storedRecordCount) of \(viewModel.recordCapacityEntry)")
            numberRow("Capacity", text: $viewModel.recordCapacityEntry)
            HStack {
                Button("Apply", action: viewModel.applyRecordSettings)
                Spacer()
                Button("Clear Records", action: viewModel.clearRecords)
            }
            .padding(.vertical, 4)
            labeledPicker("Records per Notification", selection: $viewModel.recordsPerNotification)
            Divider()
            labeledPicker("Backfill Span", selection: $viewModel.backfillDuration)
            Button("Backfill from Glucose Source", action: viewModel.backfill)
                .padding(.vertical, 4)
            if let message = viewModel.recordSettingsMessage {
                MessageView(message: message)
            }
        }
    }

    private var glucoseSourceCard: some View {
        RoundedCard(title: "Glucose Source", footer: "The checked source is active; changes take effect at the next measurement. Traces ship with the CGM kit.") {
            SingleSelectionCheckList<GlucoseSourceOption>(items: viewModel.glucoseSourceOptions, selectedItem: $viewModel.glucoseSource)
            switch viewModel.glucoseSource {
            case .sineWave:
                Divider()
                numberRow("Start value (mg/dL)", text: $viewModel.sineStartEntry)
                numberRow("Amplitude (mg/dL)", text: $viewModel.sineAmplitudeEntry)
                numberRow("Period (minutes)", text: $viewModel.sinePeriodMinutesEntry)
                Button("Apply Parameters", action: viewModel.applyGlucoseSource)
            case .constant:
                Divider()
                numberRow("Value (mg/dL)", text: $viewModel.constantEntry)
                Button("Apply Parameters", action: viewModel.applyGlucoseSource)
            case .scenario:
                if let summary = viewModel.selectedScenarioSummary {
                    MessageView(message: summary)
                }
            }
            if let message = viewModel.glucoseSourceMessage {
                MessageView(message: message)
            }
        }
    }

    /// Segmented pickers hide their title, so the label sits above the control.
    private func labeledPicker<Option: Hashable & CaseIterable & CustomStringConvertible>(_ label: String, selection: Binding<Option>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            Picker(label, selection: selection) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    private func numberRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DismissibleKeyboardTextField(
                text: text,
                placeholder: label,
                font: .preferredFont(forTextStyle: .headline),
                textColor: .blue,
                textAlignment: .right,
                keyboardType: .decimalPad,
                shouldBecomeFirstResponder: false,
                maxLength: 7,
                doneButtonColor: UIColor(Color.accentColor),
                textFieldDidBeginEditing: nil
            )
        }
    }

    private var sessionCard: some View {
        RoundedCard(title: "Session") {
            RoundedCardValueRow(label: "State", value: viewModel.sessionStateString)
            RoundedCardValueRow(label: "Time Offset", value: viewModel.timeOffsetString)
            RoundedCardValueRow(label: "Session Start Time", value: viewModel.sessionStartTimeString)
            RoundedCardValueRow(label: "Sensor Status", value: viewModel.sensorStatusString)
            RoundedCardValueRow(label: "Session Run Time", value: viewModel.sessionRunTimeString)
            Divider()
            HStack {
                Text("Set Run Time (hours)")
                Spacer()
                runTimeEntry
                Button("Apply", action: viewModel.applySessionRunTime)
            }
            Divider()
            HStack {
                Button(action: viewModel.startSession) {
                    Text("Start Session")
                }
                Spacer()
                Button(action: viewModel.stopSession) {
                    Text("Stop Session")
                }
            }
        }
    }

    private var runTimeEntry: some View {
        DismissibleKeyboardTextField(
            text: $viewModel.sessionRunTimeHoursEntry,
            placeholder: "hours",
            font: .preferredFont(forTextStyle: .headline),
            textColor: .blue,
            textAlignment: .right,
            keyboardType: .numberPad,
            shouldBecomeFirstResponder: false,
            maxLength: 5,
            doneButtonColor: UIColor(Color.accentColor),
            textFieldDidBeginEditing: nil
        )
    }

    private var serverCard: some View {
        RoundedCard(title: "Server") {
            Button(action: viewModel.restartServer) {
                Text("Restart Server")
            }
            Divider()
            RoundedCardToggleRow(label: "Power On Sensor", enabled: $viewModel.isSensorPoweredOn, toggleTintColor: .accentColor)
            Divider()
            RoundedCardToggleRow(label: "Require Encrypted Link / Bond (restarts server)", enabled: $viewModel.requiresEncryption, toggleTintColor: .accentColor)
            Divider()
            // ACS: application-layer secure channel, independent of the BLE bond above.
            RoundedCardToggleRow(label: "Authorization Control (ACS) Required", enabled: $viewModel.isAuthorizationControlEnabled, toggleTintColor: .accentColor)
            RoundedCardValueRow(label: "Secure Session", value: viewModel.isSecurityEstablished ? "established" : "not established", highlightValue: viewModel.isSecurityEstablished)
            RoundedCardValueRow(label: "Sensor Key", value: viewModel.oobRandomNumberString)
        }
    }

    private var featureCard: some View {
        RoundedCard(title: "CGM Feature", footer: "Changes are indicated to a subscribed collector.") {
            ForEach(CGMFeatureFlags.named, id: \.name) { entry in
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

    private var sensorStatusCard: some View {
        RoundedCard(title: "Sensor Status Annunciation", footer: "Time Synchronization Required and Session Stopped follow the session state.") {
            ForEach(CGMServerViewModel.manualStatusBits, id: \.name) { entry in
                RoundedCardToggleRow(
                    label: entry.name,
                    enabled: Binding(
                        get: { viewModel.isStatusBitSet(entry.flag) },
                        set: { viewModel.setStatusBit(entry.flag, enabled: $0) }
                    ),
                    toggleTintColor: .accentColor
                )
            }
        }
    }

    private var errorHandlingCard: some View {
        RoundedCard(title: "Error Handling") {
            RoundedCardToggleRow(label: "Procedure Already In Progress", enabled: $viewModel.procedureAlreadyInProgress, toggleTintColor: .accentColor)
            RoundedCardToggleRow(label: "Out of Range Schedule", enabled: $viewModel.outOfRangeSchedule, toggleTintColor: .accentColor)
        }
    }
}

struct CGMServerView_Previews: PreviewProvider {
    static var previews: some View {
        CGMServerView(viewModel: CGMServerViewModel())
    }
}
