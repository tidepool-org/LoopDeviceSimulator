//
//  CGMSensorHUDView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-15.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Landing page of the CGM Sensor Server: the glance view a tester reads across the room. The full
//  configuration page sits one swipe to the right. Tidepool Loop remains the high-fidelity display; this
//  only shows what the sensor is doing right now.

import SwiftUI
import Charts
import ContinuousGlucoseMonitorServiceKit

struct CGMSensorHUDView: View {
    @Bindable var viewModel: CGMServerViewModel

    /// Room left under the content of both pages for the TabView's page control, so it never covers a control.
    static let pageControlClearance: CGFloat = 28

    var body: some View {
        // Everything on one screen when it fits (the chart gives up height first); otherwise scroll.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 16) {
            glucoseHeadline
            statusChips
            quickSettings
            sparkline
                .layoutPriority(1)   // sized before the spacer, so it reaches 110 pt whenever there is room
            quickActions
            Spacer(minLength: 0)     // pins everything to the top; a bare VStack would centre it
        }
        // The 88 pt digits carry their own slack above the cap height, so the top inset stays small.
        .padding([.horizontal, .bottom])
        .padding(.top, 4)
        .padding(.bottom, Self.pageControlClearance)
    }

    // MARK: Glucose

    private var glucoseHeadline: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(glucoseText)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(glucoseColor)
                    .contentTransition(.numericText())
                Text("mg/dL")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if let symbol = trendSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(glucoseColor)
                        .padding(.leading, 4)
                }
            }
            if let caption = glucoseCaption {
                Text(caption)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(nextReadingText(now: context.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        // Icon only, in the slack above the digits, so it costs no height and misses the trend arrow.
        .overlay(alignment: .topTrailing) { securityBadge }
    }

    // MARK: Security

    /// Whether a collector holds the session key: closed green lock when it does, whatever the Required toggle
    /// says (the ACS service is always published, the toggle only gates plain access). Otherwise an open lock,
    /// orange when protection is required and nobody has paired, gray when it is not required. Tapping it
    /// flips Required on the sensor, the same toggle as on the configuration page.
    private var securityBadge: some View {
        Button {
            viewModel.isAuthorizationControlEnabled.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: securitySymbol)
                    .font(.title3.weight(.semibold))
                Text(viewModel.isAuthorizationControlEnabled ? "required" : "optional")
                    .font(.caption2)
            }
            .foregroundStyle(securityTint)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(securityTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(securityLabel)
        .accessibilityHint("Toggles whether the sensor requires Authorization Control")
    }

    private var securitySymbol: String {
        viewModel.isSecurityEstablished ? "lock.fill" : "lock.open.fill"
    }

    private var securityTint: Color {
        if viewModel.isSecurityEstablished { return .green }
        return viewModel.isAuthorizationControlEnabled ? .orange : .gray
    }

    private var securityLabel: String {
        if viewModel.isSecurityEstablished { return "Secure session established" }
        return viewModel.isAuthorizationControlEnabled ? "Secure session required, not established" : "Secure session not established"
    }

    private var securityChipValue: String {
        if viewModel.isSecurityEstablished { return "established" }
        return viewModel.isAuthorizationControlEnabled ? "required" : "not established"
    }

    /// Three dashes is Tidepool's placeholder for no reading.
    private var glucoseText: String {
        guard let glucose = viewModel.lastGlucose, glucose.isFinite else { return "---" }
        return glucose.compactDescription
    }

    /// The trend under the value; nothing when there is no reading, since the dash already says so.
    private var glucoseCaption: String? {
        guard let glucose = viewModel.lastGlucose else { return nil }
        guard glucose.isFinite else { return "no value (\(viewModel.conditionString))" }
        if let trend = viewModel.lastTrend, trend.isFinite {
            return "\(trend >= 0 ? "+" : "")\(trend.compactDescription) mg/dL/min"
        }
        return nil
    }

    /// Five-step arrow from the trend in mg/dL/min, the convention CGM displays use.
    private var trendSymbol: String? {
        guard let trend = viewModel.lastTrend, trend.isFinite, viewModel.lastGlucose?.isFinite == true else { return nil }
        switch trend {
        case 3...: return "arrow.up"
        case 1..<3: return "arrow.up.right"
        case -1...1: return "arrow.right"
        case -3 ..< -1: return "arrow.down.right"
        default: return "arrow.down"
        }
    }

    private var glucoseColor: Color {
        guard let glucose = viewModel.lastGlucose, glucose.isFinite else { return .secondary }
        if glucose < viewModel.alertLevels.patientLow { return .red }
        if glucose > viewModel.alertLevels.patientHigh { return .orange }
        return .primary
    }

    /// The cadence never stops; what the next tick carries depends on the sensor's state.
    private func nextReadingText(now: Date) -> String {
        if let end = viewModel.warmupEndDate {
            return "warming up, first reading \(end.countdown(from: now))"
        }
        let next = viewModel.nextMeasurementDate.map { "next communication \($0.countdown(from: now))" } ?? "cadence not running"
        if viewModel.isFailed { return "sensor failed, status only; \(next)" }
        guard viewModel.isSessionRunning else { return "session \(viewModel.sessionStateString), status only; \(next)" }
        return next.replacingOccurrences(of: "communication", with: "reading")
    }

    // MARK: Status

    private var statusChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow {
                chip("Session", viewModel.sessionStateString.isEmpty ? "off" : viewModel.sessionStateString, tint: viewModel.isSessionRunning ? .green : .gray)
                chip("Sensor", viewModel.conditionString.isEmpty ? "—" : viewModel.conditionString, tint: conditionTint)
                chip("Offset", viewModel.timeOffsetString.isEmpty ? "—" : viewModel.timeOffsetString, tint: .gray)
            }
            chipRow {
                chip("Calibration", calibrationChipValue, tint: viewModel.calibrationStatusString == "none" ? .gray : .yellow)
                chip("Collectors", "\(viewModel.numberOfSubscribedDevices)", tint: viewModel.numberOfSubscribedDevices > 0 ? .blue : .gray)
                chip("Secure", securityChipValue, tint: securityTint)
            }
            // Hidden until an alert bit is set, then a full-width red chip so it cannot be missed.
            if !alertBitNames.isEmpty {
                chip(alertBitNames.count == 1 ? "Alert" : "Alerts", alertBitNames.joined(separator: ", "), tint: .red)
            }
            sensorKeyRow
        }
    }

    /// The OOB number a collector must enter for the key exchange, readable across the room like the glucose.
    private var sensorKeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Sensor key")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(viewModel.oobRandomNumberString.isEmpty ? "---" : viewModel.oobRandomNumberString)
                .font(.footnote.weight(.semibold))
                .monospaced()
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// Status bits the chips do not already show: alert levels, range, battery, time sync and the like.
    private static let bitsShownAsChips: Set<String> = [
        "Session Stopped", "Sensor Malfunction", "General Device Fault", "Calibration Recommended", "Calibration Required",
    ]

    private var alertBitNames: [String] {
        viewModel.activeStatusBitNames.filter { !Self.bitsShownAsChips.contains($0) }
    }

    /// "Calibration Recommended" wrapped to two lines under a chip already labelled Calibration.
    private var calibrationChipValue: String {
        viewModel.calibrationStatusString.replacingOccurrences(of: "Calibration ", with: "").lowercased()
    }

    private var conditionTint: Color {
        if viewModel.isFailed { return .red }
        if viewModel.isImpaired { return .orange }
        return viewModel.conditionString.isEmpty ? .gray : .green
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
    }

    private func chip(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Quick settings

    /// The two settings a tester changes most, as plain menus. Picking Sine Wave or Constant here uses the
    /// values currently entered on the configuration page (defaults until edited there).
    private var quickSettings: some View {
        HStack(spacing: 10) {
            settingMenu("Communication Interval") {
                Picker("Communication Interval", selection: $viewModel.measurementInterval) {
                    ForEach(MeasurementIntervalOption.allCases, id: \.self) { option in
                        Text(option.description).tag(option)
                    }
                }
            }
            settingMenu("Glucose Source") {
                Picker("Glucose Source", selection: $viewModel.glucoseSource) {
                    ForEach(viewModel.glucoseSourceOptions, id: \.self) { option in
                        Text(option.description).tag(option)
                    }
                }
            }
        }
    }

    private func settingMenu<Content: View>(_ label: String, @ViewBuilder picker: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            picker()
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Sparkline

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 60 minutes")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Always a fixed hour of session time: anchored at 0–60 min until the session is an hour old,
            // then sliding with the Time Offset. A sparse chart reads as "early", not as a glitch.
            Chart(viewModel.recentReadings.filter { $0.glucose.isFinite }) { point in
                LineMark(x: .value("Offset", point.timeOffset), y: .value("mg/dL", point.glucose))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Offset", point.timeOffset), y: .value("mg/dL", point.glucose))
                    .symbolSize(18)
            }
            .chartXScale(domain: chartWindow)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("minutes since session start", alignment: .trailing)
            .chartYAxisLabel("mg/dL")
            // ViewThatFits judges the ideal size, so the ideal is the compact 70 pt; once the one-screen
            // layout is chosen the chart grows to 110 pt when there is room.
            .frame(minHeight: 70, idealHeight: 70, maxHeight: 110)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chartWindow: ClosedRange<Int> {
        let end = max(viewModel.timeOffsetMinutes, CGMServerViewModel.chartWindowMinutes)
        return (end - CGMServerViewModel.chartWindowMinutes)...end
    }

    // MARK: Actions

    /// Session control on the first row, fault injection on the second (Nate, 2026-10-15). Replacing a
    /// failed sensor stays on the configuration page.
    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.isSessionRunning ? viewModel.stopSession() : viewModel.startSession()
                } label: {
                    actionLabel(viewModel.isSessionRunning ? "Stop Session" : "Start Session")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isFailed && !viewModel.isSessionRunning)
                Button(action: viewModel.takeMeasurement) { actionLabel("Measure Now") }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isSessionRunning || viewModel.isFailed)
            }
            HStack(spacing: 10) {
                Button(role: .destructive, action: viewModel.failSensor) { actionLabel("Fail Sensor") }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isFailed)
                Button(action: viewModel.toggleTemporaryIssue) {
                    actionLabel(viewModel.isImpaired ? "Resolve Issue" : "Temporary Issue")
                }
                .buttonStyle(.bordered)
                .tint(viewModel.isImpaired ? .green : .orange)
                .disabled(viewModel.isFailed)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One line each, shrinking a little rather than wrapping, so the three buttons share the row evenly.
    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }
}
