//
//  FaultInjectingMessageQueue.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-11.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Every notification and indication a mock device sends passes through the one message queue the app hands
//  it, so a wrapper around BluetoothCommonKit's queue can drop, delay, reorder or replay messages in either
//  mode without touching the kits. Read responses are synchronous and bypass the queue; they are not covered.

import Foundation
import Observation
import CoreBluetooth
import BluetoothCommonKit
import ContinuousGlucoseMonitorServiceKit
import InsulinDeliveryServiceKit   // InspectableMessagingQueue: the pump's RACP checks for its own pending items

@Observable
final class FaultInjectingMessageQueue: MessagingQueue, InspectableMessagingQueue {

    /// Which messages a fault applies to; `any` matches every characteristic.
    struct Target: Hashable, Identifiable {
        let name: String
        let uuid: CBUUID?

        var id: String { uuid?.uuidString ?? "any" }
        static let any = Target(name: "Any characteristic", uuid: nil)

        func matches(_ uuid: CBUUID) -> Bool { self.uuid == nil || self.uuid == uuid }
    }

    enum Fault: Equatable, CustomStringConvertible {
        /// The next `count` matching messages are not sent.
        case dropNext(count: Int)
        /// The next matching message is sent `seconds` later than it would have been.
        case delayNext(seconds: TimeInterval)
        /// The next matching message waits for the one after it and the two go out in reverse order.
        case swapNextTwo
        /// The next matching message goes out with a bit flipped in its E2E-CRC trailer.
        case corruptCRC
        /// The next matching message goes out without its E2E-CRC trailer.
        case omitCRC
        /// The next matching message goes out `bytes` short: wrong length, and a CRC that no longer matches.
        case truncate(bytes: Int)
        /// The next matching message goes out with byte `index` inverted and, when the payload carries an
        /// E2E-CRC, the CRC recomputed, so the receiver sees an encoding fault rather than an integrity one.
        case corruptField(index: Int)

        var description: String {
            switch self {
            case .dropNext(let count): return count == 1 ? "drop next" : "drop next \(count)"
            case .delayNext(let seconds): return "delay next by \(seconds.compactDescription) s"
            case .swapNextTwo: return "swap next two"
            case .corruptCRC: return "corrupt CRC"
            case .omitCRC: return "omit CRC"
            case .truncate(let bytes): return bytes == 1 ? "truncate by 1 byte" : "truncate by \(bytes) bytes"
            case .corruptField(let index): return "corrupt byte \(index)"
            }
        }
    }

    /// Whether the device is sending with E2E-CRC trailers right now; the host answers from the mock's Feature.
    /// Both services put a 16-bit CRC over everything before it at the end of the payload.
    @ObservationIgnored var hasE2ECRC: () -> Bool = { false }

    /// A message held for a swap goes out on its own if nothing follows it within this time.
    static let swapHoldLimit: TimeInterval = 30

    // What the card shows; kept on the main thread.
    private(set) var armed: Fault? = nil
    private(set) var target: Target = .any
    private(set) var lastInjected: String? = nil

    @ObservationIgnored private let inner: MessageQueue
    @ObservationIgnored private let lock = NSLock()
    // The truth, behind the lock: the kits add messages from timers and CoreBluetooth queues.
    @ObservationIgnored private var pending: Fault? = nil
    @ObservationIgnored private var pendingTarget: Target = .any
    @ObservationIgnored private var heldForSwap: UUIDValuePair? = nil
    @ObservationIgnored private var delayedCount = 0
    @ObservationIgnored private var lastSent: [CBUUID: UUIDValuePair] = [:]
    @ObservationIgnored private var lastSentAny: UUIDValuePair? = nil
    /// Where injections are reported; the session log by default, a test can capture them.
    @ObservationIgnored var log: (String) -> Void = { SessionLog.shared.log(.lifecycle, $0) }

    init(wrapping inner: MessageQueue) {
        self.inner = inner
    }

    // MARK: MessagingQueue

    var gattServer: GATTService! { inner.gattServer }

    var hasMessagesInQueue: Bool {
        lock.withLock { heldForSwap != nil || delayedCount > 0 } || inner.hasMessagesInQueue
    }

    var queuedItems: [UUIDValuePair] {
        let held: [UUIDValuePair] = lock.withLock { heldForSwap.map { [$0] } ?? [] }
        return inner.queuedItems + held
    }

    private enum Action {
        case pass
        case drop(remaining: Int)
        case delay(TimeInterval)
        case hold
        case swap(with: UUIDValuePair)
        /// Send a changed payload, with what changed.
        case mutate(Data, String)
        /// The fault did not apply to this payload; send it intact and say why.
        case intact(String)
    }

    func addQueueItem(_ update: UUIDValuePair) {
        let action: Action = lock.withLock {
            lastSent[update.uuid] = update
            lastSentAny = update
            guard let fault = pending, pendingTarget.matches(update.uuid) else { return .pass }
            switch fault {
            case .dropNext(let count):
                let remaining = count - 1
                pending = remaining > 0 ? .dropNext(count: remaining) : nil
                return .drop(remaining: remaining)
            case .delayNext(let seconds):
                pending = nil
                delayedCount += 1
                return .delay(seconds)
            case .swapNextTwo:
                if let first = heldForSwap {
                    heldForSwap = nil
                    pending = nil
                    return .swap(with: first)
                }
                heldForSwap = update
                return .hold
            case .corruptCRC, .omitCRC, .truncate, .corruptField:
                pending = nil
                return Self.payloadAction(fault, on: update.value, hasCRC: hasE2ECRC())
            }
        }

        let name = Self.name(of: update.uuid)
        switch action {
        case .pass:
            inner.addQueueItem(update)
        case .mutate(let data, let change):
            inner.addQueueItem(UUIDValuePair(uuid: update.uuid, value: data, onSubscribedCentrals: update.onSubscribedCentrals))
            note("\(change) on \(name): \(update.value.hexadecimalString) → \(data.hexadecimalString)")
        case .intact(let reason):
            inner.addQueueItem(update)
            note("\(reason); \(name) sent intact")
        case .drop(let remaining):
            note("dropped \(name) \(update.value.hexadecimalString)" + (remaining > 0 ? ", \(remaining) more to drop" : ""))
        case .delay(let seconds):
            note("holding \(name) \(update.value.hexadecimalString) for \(seconds.compactDescription) s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
                lock.withLock { delayedCount -= 1 }
                inner.addQueueItem(update)
                note("released \(name) after \(seconds.compactDescription) s")
            }
        case .hold:
            note("holding \(name) \(update.value.hexadecimalString) until the next message, to send them out of order")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.swapHoldLimit) { [self] in
                let stillHeld: UUIDValuePair? = lock.withLock {
                    guard let held = heldForSwap, held.uuid == update.uuid, held.value == update.value else { return nil }
                    heldForSwap = nil
                    pending = nil
                    return held
                }
                guard let stillHeld else { return }
                inner.addQueueItem(stillHeld)
                note("released \(name) after \(Self.swapHoldLimit.compactDescription) s with nothing to swap with")
            }
        case .swap(let first):
            inner.addQueueItem(update)
            inner.addQueueItem(first)
            note("sent \(name) before \(Self.name(of: first.uuid)) (out of order)")
        }
        publish()
    }

    func emptyQueue() {
        lock.withLock {
            heldForSwap = nil
            delayedCount = 0
        }
        inner.emptyQueue()
        publish()
    }

    // MARK: Tester controls

    func arm(_ fault: Fault, on target: Target) {
        lock.withLock {
            pending = fault
            pendingTarget = target
        }
        publish()
    }

    /// Clears the fault; a message held for a swap goes out at once.
    func disarm() {
        let held: UUIDValuePair? = lock.withLock {
            pending = nil
            defer { heldForSwap = nil }
            return heldForSwap
        }
        if let held {
            inner.addQueueItem(held)
            note("released \(Self.name(of: held.uuid)) on disarm")
        }
        publish()
    }

    /// Sends the last message that went out on `target` again; false when nothing has been sent there yet.
    @discardableResult
    func replayLast(on target: Target) -> Bool {
        let item: UUIDValuePair? = lock.withLock {
            if let uuid = target.uuid { return lastSent[uuid] }
            return lastSentAny
        }
        guard let item else { return false }
        inner.addQueueItem(item)
        note("replayed \(Self.name(of: item.uuid)) \(item.value.hexadecimalString)")
        publish()
        return true
    }

    // MARK: Payload faults

    private static func payloadAction(_ fault: Fault, on payload: Data, hasCRC: Bool) -> Action {
        switch fault {
        case .corruptCRC:
            guard hasCRC else { return .intact("no CRC to corrupt") }
            guard let data = corruptingCRC(payload) else { return .intact("payload too short to corrupt") }
            return .mutate(data, "corrupted CRC")
        case .omitCRC:
            guard hasCRC else { return .intact("no CRC to omit") }
            guard let data = omittingCRC(payload) else { return .intact("payload too short to omit the CRC") }
            return .mutate(data, "omitted CRC")
        case .truncate(let bytes):
            guard let data = truncating(payload, by: bytes) else { return .intact("payload too short to truncate by \(bytes)") }
            return .mutate(data, "truncated by \(bytes)")
        case .corruptField(let index):
            guard let data = corruptingField(payload, at: index, hasCRC: hasCRC) else { return .intact("payload has no byte \(index) to corrupt") }
            return .mutate(data, "corrupted byte \(index)" + (hasCRC ? ", CRC recomputed" : ""))
        default:
            return .pass
        }
    }

    /// Flips the low bit of the last CRC byte; nil when there is no room for a CRC.
    static func corruptingCRC(_ payload: Data) -> Data? {
        guard payload.count >= 2 else { return nil }
        var data = payload
        data[data.index(before: data.endIndex)] ^= 0x01
        return data
    }

    /// Drops the two CRC bytes; nil when nothing would be left.
    static func omittingCRC(_ payload: Data) -> Data? {
        guard payload.count > 2 else { return nil }
        return payload.dropLast(2)
    }

    /// Drops `bytes` from the end; nil when nothing would be left.
    static func truncating(_ payload: Data, by bytes: Int) -> Data? {
        guard bytes > 0, payload.count > bytes else { return nil }
        return payload.dropLast(bytes)
    }

    /// Inverts byte `index` of the content (the part before any CRC) and recomputes the CRC when there is one,
    /// so only the field is wrong; nil when the content has no such byte.
    static func corruptingField(_ payload: Data, at index: Int, hasCRC: Bool) -> Data? {
        var content = hasCRC ? Data(payload.dropLast(2)) : payload
        guard index >= 0, index < content.count, !(hasCRC && payload.count < 2) else { return nil }
        content[content.startIndex.advanced(by: index)] ^= 0xFF
        return hasCRC ? content.appendingCRC() : content
    }

    // MARK: Reporting

    private func note(_ detail: String) {
        log("fault injection: \(detail)")
        onMain { self.lastInjected = detail }
    }

    private func publish() {
        let (fault, target): (Fault?, Target) = lock.withLock { (pending, pendingTarget) }
        onMain {
            self.armed = fault
            self.target = target
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// The characteristic's name from whichever service owns it, else the bare UUID.
    static func name(of uuid: CBUUID) -> String {
        let raw = uuid.uuidString.lowercased()
        if let id = InsulinDeliveryCharacteristicUUID(rawValue: raw) { return id.name }
        if let cgm = CGMCharacteristicUUID(rawValue: raw) { return cgm.name }
        if let acs = ACCharacteristicUUID(rawValue: raw) { return "acs.\(acs)" }
        return uuid.uuidString
    }
}

/// A server view model that owns a fault-injecting queue while its server runs.
protocol FaultInjectionHost: AnyObject, Observable {
    var faultQueue: FaultInjectingMessageQueue? { get }
    var faultMessage: String? { get }
    static var faultTargets: [FaultInjectingMessageQueue.Target] { get }
    func armFault(_ fault: FaultInjectingMessageQueue.Fault, on target: FaultInjectingMessageQueue.Target)
    func disarmFault()
    func replayLastMessage(on target: FaultInjectingMessageQueue.Target)
}
