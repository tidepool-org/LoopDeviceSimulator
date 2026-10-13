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
            Picker("Measurement Interval", selection: $viewModel.measurementInterval) {
                ForEach(MeasurementIntervalOption.allCases, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.segmented)
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
