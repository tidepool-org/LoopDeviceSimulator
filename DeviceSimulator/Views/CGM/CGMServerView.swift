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

    /// Two pages: the HUD lands first, the full configuration is one swipe to the right (Nate, 2026-10-15).
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            CGMSensorHUDView(viewModel: viewModel)
                .tag(0)
            cgmServer
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .navigationTitle("CGM Sensor")
        .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewModel.isSensorPoweredOn {
                    viewModel.startServer(serverName: serverName)
                }
            }
            .onDisappear(perform: { viewModel.stopServer() })
    }

    private var cgmServer: some View {
        VStack {
            // No page title: the navigation bar already says CGM Sensor and the HUD is one swipe left.
            RoundedCardScrollView {
                Text("Number of Subscribed Devices: \(viewModel.numberOfSubscribedDevices)")
                measurementCard
                recordsCard
                specificOpsCard
                glucoseSourceCard
                sessionCard
                lifecycleCard
                serverCard
                featureCard
                sensorStatusCard
                errorHandlingCard
            }
            // The page control overlays the bottom of the TabView; keep the last card's controls above it.
            .contentMargins(.bottom, CGMSensorHUDView.pageControlClearance, for: .scrollContent)
        }
    }

    private var measurementCard: some View {
        RoundedCard(title: "Measurements", footer: "The interval is the CGM Communication Interval: readings are taken and notified at this cadence, a collector's Set Communication Interval moves the picker (Fastest = 5 s), and Off keeps measuring at the current cadence but stops notifying, so only RACP serves the collector. Time Offset has one-minute resolution, so 5 s readings share an offset.") {
            RoundedCardValueRow(label: "Last Glucose", value: viewModel.lastGlucoseString)
            RoundedCardValueRow(label: "Measurements This Session", value: "\(viewModel.measurementCount)")
            // Ticks once a second; the sensor's timer fire date is the single source of truth.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RoundedCardValueRow(label: "Next Communication", value: countdown(to: viewModel.nextMeasurementDate, now: context.date))
            }
            Divider()
            LabeledSegmentedPicker("Communication Interval", selection: $viewModel.measurementInterval)
            if let note = viewModel.measurementIntervalNote {
                RoundedCardValueRow(label: "Current", value: note)
            }
            Divider()
            Button(action: viewModel.takeMeasurement) {
                Text("Measure Now")
            }
        }
    }

    private func countdown(to date: Date?, now: Date) -> String {
        date?.countdown(from: now) ?? "session \(viewModel.sessionStateString)"
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
            LabeledSegmentedPicker("Records per Notification", selection: $viewModel.recordsPerNotification)
            Divider()
            LabeledSegmentedPicker("Backfill Span", selection: $viewModel.backfillDuration)
            Button("Backfill from Glucose Source", action: viewModel.backfill)
                .padding(.vertical, 4)
            if let message = viewModel.recordSettingsMessage {
                MessageView(message: message)
            }
        }
    }

    /// What the collector has configured through the CGM Specific Ops Control Point (CGMS §3.7).
    private var specificOpsCard: some View {
        RoundedCard(title: "CGM Specific Ops", footer: "Set by the collector through the CGMCP; the Communication Interval lives in the Measurements card. Levels must be within \(Int(CGMAlertLevels.glucoseRange.lowerBound))–\(Int(CGMAlertLevels.glucoseRange.upperBound)) mg/dL and rates within ±\(Int(CGMAlertLevels.rateRange.upperBound)) mg/dL/min, otherwise the sensor answers Parameter Out of Range. Each reading is compared against the levels and the bits it trips appear in its Sensor Status. Calibration Schedule: Never asks nothing; Once recommends a calibration at session start and requires one after 3 h without it; 10 min and 24 h recommend at session start, require one interval in, then after each calibration recommend ahead of the next due time (20 min, or half a short interval) and require once it passes; Now keeps Calibration Required on. A successful calibration clears the bits and any toggled request.") {
            RoundedCardValueRow(label: "Patient High", value: "\(viewModel.alertLevels.patientHigh.compactDescription) mg/dL")
            RoundedCardValueRow(label: "Patient Low", value: "\(viewModel.alertLevels.patientLow.compactDescription) mg/dL")
            RoundedCardValueRow(label: "Hypo", value: "\(viewModel.alertLevels.hypo.compactDescription) mg/dL")
            RoundedCardValueRow(label: "Hyper", value: "\(viewModel.alertLevels.hyper.compactDescription) mg/dL")
            RoundedCardValueRow(label: "Rate of Decrease", value: "\(viewModel.alertLevels.rateOfDecrease.compactDescription) mg/dL/min")
            RoundedCardValueRow(label: "Rate of Increase", value: "\(viewModel.alertLevels.rateOfIncrease.compactDescription) mg/dL/min")
            RoundedCardValueRow(label: "Alerts Tripped", value: viewModel.alertStatusString)
            Button("Reset Alert Levels", action: viewModel.resetAlertLevels)
                .padding(.vertical, 4)
            Divider()
            RoundedCardValueRow(label: "Calibrations Stored", value: "\(viewModel.calibrationCount)")
            RoundedCardValueRow(label: "Last Calibration", value: viewModel.lastCalibrationString)
            RoundedCardValueRow(label: "Calibration Status", value: viewModel.calibrationStatusString)
            LabeledSegmentedPicker("Calibration Schedule", selection: $viewModel.calibrationSchedule)
            Button("Clear Calibrations", action: viewModel.clearCalibrations)
                .padding(.vertical, 4)
            if let message = viewModel.specificOpsMessage {
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
            RoundedCardValueRow(label: "Condition", value: viewModel.conditionString)
            if viewModel.warmupEndDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RoundedCardValueRow(label: "Warm-up Ends", value: countdown(to: viewModel.warmupEndDate, now: context.date))
                }
            }
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

    /// Warm-up, sensor condition and range (CGM-DESIGN §Lifecycle; TBD-03/05/07, HYD-G-003/006).
    private var lifecycleCard: some View {
        RoundedCard(title: "Sensor Lifecycle", footer: "Warm-up applies to the next session and can be changed while one is in progress. Replace Sensor starts a fresh session with empty records and calibrations and clears any failure. Fail Sensor stops readings and sets Sensor Malfunction until the sensor is replaced; a collector's Start Session answers Procedure Not Completed meanwhile. Temporary Issue keeps readings coming with NaN glucose, zero quality and General Device Fault until resolved. Readings outside the sensor range are reported at the boundary with the Device Can Process bit when the Feature has Sensor Result High-Low Detection. A session also ends by itself when its run time elapses.") {
            LabeledSegmentedPicker("Warm-up", selection: $viewModel.warmupDuration)
            Divider()
            HStack {
                Button("Replace Sensor", action: viewModel.replaceSensor)
                Spacer()
                Button("Fail Sensor", action: viewModel.failSensor)
                    .disabled(viewModel.isFailed)
                Spacer()
                Button(viewModel.isImpaired ? "Resolve Issue" : "Temporary Issue", action: viewModel.toggleTemporaryIssue)
                    .disabled(viewModel.isFailed)
            }
            .padding(.vertical, 4)
            Divider()
            numberRow("Sensor Range Low (mg/dL)", text: $viewModel.sensorRangeLowEntry)
            numberRow("Sensor Range High (mg/dL)", text: $viewModel.sensorRangeHighEntry)
            Button("Apply Range", action: viewModel.applySensorRange)
                .padding(.vertical, 4)
            if let message = viewModel.lifecycleMessage {
                MessageView(message: message)
            }
            Divider()
            Text("Lifecycle Log")
            if viewModel.lifecycleEventStrings.isEmpty {
                Text("No lifecycle events yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.lifecycleEventStrings.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        // Inside a stack so the preview spends the same navigation-bar height as the app.
        NavigationStack {
            CGMServerView(viewModel: runningSession)
        }
    }

    /// A mid-session snapshot so the HUD renders a value, an arrow and a trace instead of placeholders.
    static var runningSession: CGMServerViewModel {
        let viewModel = CGMServerViewModel()
        viewModel.isSensorPoweredOn = false   // otherwise onAppear starts a real sensor and mirrors it over these
        viewModel.isSessionRunning = true
        viewModel.sessionStateString = "running"
        viewModel.condition = .healthy
        viewModel.timeOffsetMinutes = 23
        viewModel.timeOffsetString = "23 min"
        viewModel.lastGlucose = 128
        viewModel.lastTrend = 0.6
        viewModel.recentReadings = stride(from: 0, through: 20, by: 5).enumerated().map { index, offset in
            CGMReadingPoint(id: index, timeOffset: offset, glucose: 112 + Double(offset) * 0.8)
        }
        viewModel.nextMeasurementDate = Date().addingTimeInterval(137)
        return viewModel
    }
}