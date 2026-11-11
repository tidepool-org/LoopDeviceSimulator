//
//  FaultInjectionCard.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-11.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI

/// Tester controls for the fault-injecting message queue, shared by the pump and CGM configuration pages.
struct FaultInjectionCard<Host: FaultInjectionHost>: View {
    let host: Host

    @State private var target: FaultInjectingMessageQueue.Target = .any
    @State private var dropCount = 1
    @State private var delayEntry = "15"
    @State private var truncateBytes = 1
    @State private var fieldIndex = 1

    var body: some View {
        RoundedCard(title: "Fault Injection", footer: "Acts on the next notification or indication the device sends on the chosen characteristic, then clears. Drop loses the message without disconnecting. Delay holds it for the given time, which may exceed the controller's command timeout. Swap holds the next message until the one after it and sends them in reverse order. Replay sends the last message that went out again. Corrupt CRC flips a bit in the E2E-CRC trailer and Omit CRC removes it; both send the message intact when the device is not using E2E-CRC. Truncate cuts bytes off the end, so the length is wrong. Corrupt Byte inverts one byte of the content and recomputes the CRC, so only that field is malformed; byte 0 is the op code or flags, byte 1 the first operand. Read responses are not affected.") {
            Picker("Characteristic", selection: $target) {
                ForEach(Host.faultTargets) { option in
                    Text(option.name).tag(option)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Stepper("Drop next \(dropCount)", value: $dropCount, in: 1...20)
                Button("Arm") { host.armFault(.dropNext(count: dropCount), on: target) }
                    .buttonStyle(.bordered)
            }

            HStack {
                Text("Delay next by")
                TextField("seconds", text: $delayEntry)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("s")
                Spacer()
                Button("Arm") {
                    guard let seconds = Double(delayEntry.trimmingCharacters(in: .whitespaces)), seconds > 0, seconds.isFinite else { return }
                    host.armFault(.delayNext(seconds: seconds), on: target)
                }
                .buttonStyle(.bordered)
                .disabled(Double(delayEntry.trimmingCharacters(in: .whitespaces)).map { $0 <= 0 || !$0.isFinite } ?? true)
            }

            HStack {
                Button("Swap Next Two") { host.armFault(.swapNextTwo, on: target) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Replay Last") { host.replayLastMessage(on: target) }
                    .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Button("Corrupt CRC") { host.armFault(.corruptCRC, on: target) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Omit CRC") { host.armFault(.omitCRC, on: target) }
                    .buttonStyle(.bordered)
            }

            HStack {
                Stepper("Truncate by \(truncateBytes)", value: $truncateBytes, in: 1...10)
                Button("Arm") { host.armFault(.truncate(bytes: truncateBytes), on: target) }
                    .buttonStyle(.bordered)
            }

            HStack {
                Stepper("Corrupt byte \(fieldIndex)", value: $fieldIndex, in: 0...30)
                Button("Arm") { host.armFault(.corruptField(index: fieldIndex), on: target) }
                    .buttonStyle(.bordered)
            }

            RoundedCardValueRow(label: "Armed", value: armedDescription, highlightValue: host.faultQueue?.armed != nil, highlightColor: .orange)
            if host.faultQueue?.armed != nil {
                Button("Disarm", role: .destructive) { host.disarmFault() }
                    .buttonStyle(.bordered)
            }
            RoundedCardValueRow(label: "Last Injected", value: host.faultQueue?.lastInjected ?? "none")
            if let message = host.faultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(host.faultQueue == nil)
    }

    private var armedDescription: String {
        guard let queue = host.faultQueue, let fault = queue.armed else { return "none" }
        return "\(fault) on \(queue.target.name.lowercased())"
    }
}
