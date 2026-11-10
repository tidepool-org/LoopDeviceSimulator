//
//  InsulinDeliveryPumpHUDView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-06.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  The pump's landing page, a sibling of the CGM HUD: what the pump is delivering right now, readable across
//  the room, plus the two controls a tester reaches for most often, therapy Stop and Run on the pump itself
//  and the response override for the controller's delivery commands.

import SwiftUI
import InsulinDeliveryServiceKit

struct InsulinDeliveryPumpHUDView: View {
    @Bindable var viewModel: InsulinDeliveryServerViewModel

    /// Room left under the content of both pages for the TabView's page control, so it never covers a control.
    static let pageControlClearance: CGFloat = 28

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: 16) {
            reservoirHeadline
            statusChips
            responseOverrideSetting
            quickActions
            Spacer(minLength: 0)
        }
        .padding([.horizontal, .bottom])
        .padding(.top, 4)
        .padding(.bottom, Self.pageControlClearance)
    }

    // MARK: Reservoir and delivery

    private var reservoirHeadline: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reservoirText)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(reservoirColor)
                    .contentTransition(.numericText())
                Text("U left")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(deliveryText(now: context.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var reservoirText: String {
        viewModel.isPumpPoweredOn ? String(format: "%.1f", viewModel.reservoirRemaining) : "---"
    }

    private var reservoirColor: Color {
        guard viewModel.isPumpPoweredOn else { return .secondary }
        return viewModel.reservoirRemaining <= 25 ? .orange : .primary
    }

    /// Basal and bolus on one line: the temp basal with its remaining time when one runs, else the profile rate.
    private func deliveryText(now: Date) -> String {
        guard viewModel.isPumpPoweredOn else { return "pump powered off" }
        var parts: [String] = []
        if let rate = viewModel.activeBasalRate {
            if viewModel.isTempBasal, let end = viewModel.tempBasalEndDate {
                let minutes = Int(max(0, end.timeIntervalSince(now)) / 60)
                parts.append("Temp basal \(String(format: "%.2f", rate)) U/h, \(minutes) min left")
            } else {
                parts.append("Basal \(String(format: "%.2f", rate)) U/h")
            }
        } else {
            parts.append("No basal")
        }
        if let bolus = viewModel.activeBolusProgress {
            parts.append("Bolus \(String(format: "%.2f", bolus.delivered)) of \(String(format: "%.2f", bolus.programmed)) U")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Status chips

    private var statusChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow {
                chip("Therapy", viewModel.therapyStateString, tint: viewModel.isTherapyRunning ? .green : .gray)
                chip("Pump", viewModel.operationalStateString, tint: .gray)
                chip("Temp Basal", viewModel.isTempBasal ? "active" : "none", tint: viewModel.isTempBasal ? .blue : .gray)
            }
            chipRow {
                chip("Bolus", viewModel.activeBolusProgress == nil ? "none" : "delivering", tint: viewModel.activeBolusProgress == nil ? .gray : .blue)
                chip("Controllers", "\(viewModel.numberOfSubscribedDevices)", tint: viewModel.numberOfSubscribedDevices > 0 ? .blue : .gray)
                chip("Secure", securityChipValue, tint: securityTint)
            }
            chipRow {
                // Tapping flips it: with behaviour off the pump acknowledges delivery commands without checking
                // its state, which is the quick way to drive it from a controller without the set-up steps.
                Button {
                    viewModel.isPumpBehaviourEnabled.toggle()
                } label: {
                    chip("Pump behaviour", viewModel.isPumpBehaviourEnabled ? "on" : "off", tint: viewModel.isPumpBehaviourEnabled ? .green : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isPumpPoweredOn)
                if viewModel.commandResponseOverride != .normal {
                    // Only while an override is active, so a tester cannot forget it is on.
                    chip("Command responses", viewModel.commandResponseOverride.description, tint: .orange)
                }
            }
            if viewModel.isPumpBehaviourEnabled && !viewModel.isTherapyRunning && viewModel.isPumpPoweredOn {
                readinessChecklist
            }
            pumpKeyRow
        }
    }

    // MARK: Readiness

    /// With behaviour on, the pump refuses to run until a controller has done these in order; the checklist
    /// shows how far it has got.
    private var readinessChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To run therapy, the controller must:")
                .font(.caption2)
                .foregroundStyle(.secondary)
            readinessStep("Write a complete 24 h basal profile", done: viewModel.isBasalProfileComplete)
            readinessStep("Prime the reservoir and cannula", done: viewModel.isPumpReady)
            readinessStep("Activate the basal profile", done: viewModel.isBasalProfileActivated)
            readinessStep("Set therapy to Run, or use Run Therapy below", done: viewModel.isTherapyRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func readinessStep(_ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(done ? .secondary : .primary)
        }
    }

    private var securityChipValue: String {
        if viewModel.isSecurityEstablished { return "established" }
        return viewModel.isAuthorizationControlEnabled ? "required" : "off"
    }

    private var securityTint: Color {
        if viewModel.isSecurityEstablished { return .green }
        return viewModel.isAuthorizationControlEnabled ? .orange : .gray
    }

    /// The OOB number a controller must enter for the key exchange, readable like the reservoir.
    private var pumpKeyRow: some View {
        HStack {
            Text("Pump key")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.oobRandomNumberString)
                .font(.footnote.weight(.semibold).monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: Response override

    /// Replaces the pump's answer to every delivery command until set back to Normal.
    private var responseOverrideSetting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Command Response")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("Command Response", selection: $viewModel.commandResponseOverride) {
                ForEach(CommandResponseOverride.allCases, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            (viewModel.commandResponseOverride == .normal ? Color(.secondarySystemGroupedBackground) : Color.orange.opacity(0.15)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    viewModel.setTherapyState(.stop)
                } label: {
                    actionLabel("Stop Therapy")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isPumpPoweredOn || !viewModel.isTherapyRunning)
                Button {
                    viewModel.setTherapyState(.run)
                } label: {
                    actionLabel("Run Therapy")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isPumpPoweredOn || viewModel.isTherapyRunning)
            }
            if let message = viewModel.therapyActionMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            bolusAction
        }
        .frame(maxWidth: .infinity)
    }

    /// A fast bolus entered on the pump, the way a user would at the device; the controller learns of it
    /// through the same status change as any other.
    private var bolusAction: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Units", text: $viewModel.bolusEntry)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 90)
                Text("U")
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.deliverBolusOnPump()
                } label: {
                    actionLabel("Deliver Bolus")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isPumpPoweredOn || !viewModel.isTherapyRunning || viewModel.activeBolusProgress != nil)
            }
            if let message = viewModel.bolusActionMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }
}

struct InsulinDeliveryPumpHUDView_Previews: PreviewProvider {
    static var previews: some View {
        InsulinDeliveryPumpHUDView(viewModel: InsulinDeliveryServerViewModel())
    }
}
