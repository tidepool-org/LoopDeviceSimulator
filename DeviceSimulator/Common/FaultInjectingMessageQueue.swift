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

        var description: String {
            switch self {
            case .dropNext(let count): return count == 1 ? "drop next" : "drop next \(count)"
            case .delayNext(let seconds): return "delay next by \(seconds.compactDescription) s"
            case .swapNextTwo: return "swap next two"
            }
        }
    }

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
            }
        }

        let name = Self.name(of: update.uuid)
        switch action {
        case .pass:
            inner.addQueueItem(update)
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
