//
//  FaultInjectingMessageQueueTests.swift
//  DeviceSimulatorTests
//
//  Created by Nathaniel Hamming on 2026-11-11.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import XCTest
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit
import ContinuousGlucoseMonitorServiceKit
@testable import DeviceSimulator

/// The wrapper drops, delays, reorders and replays outbound messages and leaves everything else alone.
final class FaultInjectingMessageQueueTests: XCTestCase {
    private var inner: MessageQueue!
    private var queue: FaultInjectingMessageQueue!
    private var logged: [String] = []

    private let statusChanged = InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID
    private let historyData = InsulinDeliveryCharacteristicUUID.historyData.cbUUID

    override func setUp() {
        inner = MessageQueue(gattService: MockGattServer())
        queue = FaultInjectingMessageQueue(wrapping: inner)
        logged = []
        queue.log = { [weak self] in self?.logged.append($0) }
    }

    private func item(_ uuid: CBUUID, _ byte: UInt8) -> UUIDValuePair {
        UUIDValuePair(uuid: uuid, value: Data([byte]))
    }

    private var sentValues: [UInt8] { inner.queuedItems.compactMap { $0.value.first } }

    func testWithoutAFaultEverythingPassesThrough() {
        queue.addQueueItem(item(statusChanged, 1))
        queue.addQueueItem(item(historyData, 2))
        XCTAssertEqual(sentValues, [1, 2])
        XCTAssertTrue(logged.isEmpty)
    }

    func testDropNextLosesTheCountThenClears() {
        queue.arm(.dropNext(count: 2), on: .any)
        queue.addQueueItem(item(statusChanged, 1))
        queue.addQueueItem(item(statusChanged, 2))
        queue.addQueueItem(item(statusChanged, 3))
        XCTAssertEqual(sentValues, [3])
        XCTAssertEqual(logged.count, 2)
        XCTAssertNil(queue.armed)
    }

    func testTargetFilterLeavesOtherCharacteristicsAlone() {
        queue.arm(.dropNext(count: 1), on: .init(name: "History Data", uuid: historyData))
        queue.addQueueItem(item(statusChanged, 1))   // not the target: sent, fault still armed
        XCTAssertEqual(sentValues, [1])
        XCTAssertNotNil(queue.armed)
        queue.addQueueItem(item(historyData, 2))
        XCTAssertEqual(sentValues, [1])
        XCTAssertNil(queue.armed)
    }

    func testDelayNextHoldsThenReleases() {
        queue.arm(.delayNext(seconds: 0.2), on: .any)
        queue.addQueueItem(item(statusChanged, 1))
        XCTAssertEqual(sentValues, [])
        XCTAssertTrue(queue.hasMessagesInQueue, "a held message still counts as pending")

        let released = expectation(description: "released")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { released.fulfill() }
        wait(for: [released], timeout: 2)
        XCTAssertEqual(sentValues, [1])
        XCTAssertNil(queue.armed)
    }

    func testSwapNextTwoSendsThemInReverseOrder() {
        queue.arm(.swapNextTwo, on: .any)
        queue.addQueueItem(item(statusChanged, 1))
        XCTAssertEqual(sentValues, [])
        XCTAssertEqual(queue.queuedItems.count, 1, "the held message is visible as queued")
        queue.addQueueItem(item(historyData, 2))
        XCTAssertEqual(sentValues, [2, 1])
        XCTAssertNil(queue.armed)
    }

    func testDisarmReleasesAHeldMessage() {
        queue.arm(.swapNextTwo, on: .any)
        queue.addQueueItem(item(statusChanged, 1))
        queue.disarm()
        XCTAssertEqual(sentValues, [1])
        XCTAssertNil(queue.armed)
    }

    func testReplayLastSendsTheLastMessageAgain() {
        queue.addQueueItem(item(statusChanged, 1))
        queue.addQueueItem(item(historyData, 2))
        XCTAssertTrue(queue.replayLast(on: .init(name: "Status Changed", uuid: statusChanged)))
        XCTAssertTrue(queue.replayLast(on: .any))
        XCTAssertEqual(sentValues, [1, 2, 1, 2])
    }

    func testReplayWithNothingSentReportsFalse() {
        XCTAssertFalse(queue.replayLast(on: .any))
        XCTAssertEqual(sentValues, [])
    }

    // MARK: Payload faults

    /// A payload with a valid E2E-CRC trailer, as both services send them.
    private let protectedPayload = Data([0x0F, 0x55, 0x01, 0x02]).appendingCRC()

    private var sentData: [Data] { inner.queuedItems.map(\.value) }

    func testCorruptCRCFlipsTheTrailerOnly() throws {
        queue.hasE2ECRC = { true }
        queue.arm(.corruptCRC, on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: protectedPayload))
        let sent = try XCTUnwrap(sentData.first)
        XCTAssertEqual(sent.count, protectedPayload.count)
        XCTAssertEqual(sent.dropLast(2), protectedPayload.dropLast(2))
        XCTAssertFalse(sent.isCRCValid)
        XCTAssertNil(queue.armed)
    }

    func testOmitCRCDropsTheTrailer() {
        queue.hasE2ECRC = { true }
        queue.arm(.omitCRC, on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: protectedPayload))
        XCTAssertEqual(sentData.first, protectedPayload.dropLast(2))
    }

    func testCRCFaultsSendIntactWhenTheDeviceHasNoCRC() {
        queue.hasE2ECRC = { false }
        queue.arm(.corruptCRC, on: .any)
        let plain = Data([0x0F, 0x55])
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: plain))
        XCTAssertEqual(sentData.first, plain)
        XCTAssertNil(queue.armed)
        XCTAssertTrue(logged.last?.contains("sent intact") ?? false)
    }

    func testTruncateShortensThePayload() {
        queue.arm(.truncate(bytes: 3), on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: protectedPayload))
        XCTAssertEqual(sentData.first, protectedPayload.dropLast(3))
    }

    func testCorruptFieldInvertsTheByteAndRecomputesTheCRC() throws {
        queue.hasE2ECRC = { true }
        queue.arm(.corruptField(index: 1), on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: protectedPayload))
        let sent = try XCTUnwrap(sentData.first)
        XCTAssertEqual(sent.count, protectedPayload.count)
        XCTAssertEqual(sent[sent.startIndex + 1], 0x55 ^ 0xFF)
        XCTAssertEqual(sent[sent.startIndex], 0x0F)
        XCTAssertTrue(sent.isCRCValid, "only the field is wrong; the integrity check must still pass")
    }

    func testCorruptFieldWithoutACRCLeavesTheLengthAlone() {
        queue.hasE2ECRC = { false }
        queue.arm(.corruptField(index: 0), on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: Data([0x0F, 0x55])))
        XCTAssertEqual(sentData.first, Data([0xF0, 0x55]))
    }

    func testCorruptFieldBeyondTheContentSendsIntact() {
        queue.hasE2ECRC = { true }
        queue.arm(.corruptField(index: 4), on: .any)   // bytes 4 and 5 are the CRC, not content
        queue.addQueueItem(UUIDValuePair(uuid: statusChanged, value: protectedPayload))
        XCTAssertEqual(sentData.first, protectedPayload)
    }

    func testEmptyingTheQueueCancelsADelayedRelease() {
        queue.arm(.delayNext(seconds: 0.2), on: .any)
        queue.addQueueItem(item(statusChanged, 1))
        queue.emptyQueue()   // an RACP Abort or a stop
        XCTAssertFalse(queue.hasMessagesInQueue)

        let waited = expectation(description: "waited past the delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waited.fulfill() }
        wait(for: [waited], timeout: 2)
        XCTAssertEqual(sentValues, [], "the aborted message must not surface later")
        XCTAssertFalse(queue.hasMessagesInQueue)
    }

    func testCGMRACPAndSecureDataOutCarryNoCRC() {
        let cgmRACP = CGMCharacteristicUUID.recordAccessControlPoint.cbUUID
        XCTAssertFalse(FaultInjectingMessageQueue.carriesCRC(cgmRACP, deviceHasCRC: true))
        XCTAssertFalse(FaultInjectingMessageQueue.carriesCRC(ACCharacteristicUUID.dataOutIndicate.cbUUID, deviceHasCRC: true))
        XCTAssertTrue(FaultInjectingMessageQueue.carriesCRC(CGMCharacteristicUUID.measurement.cbUUID, deviceHasCRC: true))
        XCTAssertTrue(FaultInjectingMessageQueue.carriesCRC(InsulinDeliveryCharacteristicUUID.recordAccessControlPoint.cbUUID, deviceHasCRC: true))

        queue.hasE2ECRC = { true }
        queue.arm(.corruptCRC, on: .any)
        let response = Data([0x06, 0x00, 0x01, 0x01])
        queue.addQueueItem(UUIDValuePair(uuid: cgmRACP, value: response))
        XCTAssertEqual(sentData.first, response, "no CRC to corrupt on the CGM RACP; sent intact")
    }

    /// Two CGM records, each with its own CRC: the field fault touches the first and leaves the second valid.
    func testCorruptFieldOnAMultiRecordMeasurementKeepsTheOtherRecordsIntact() throws {
        func record(glucose: UInt8) -> Data {
            var body = Data([0x00, 0x00, glucose, 0x00, 0x05, 0x00])   // size placeholder, flags, glucose SFLOAT, time offset
            body[0] = UInt8(body.count + 2)
            return body.appendingCRC()
        }
        let first = record(glucose: 0x64), second = record(glucose: 0x6E)
        queue.hasE2ECRC = { true }
        queue.arm(.corruptField(index: 2), on: .any)
        queue.addQueueItem(UUIDValuePair(uuid: CGMCharacteristicUUID.measurement.cbUUID, value: first + second))

        let sent = try XCTUnwrap(sentData.first)
        XCTAssertEqual(sent.count, first.count + second.count)
        let sentFirst = sent.prefix(first.count), sentSecond = sent.suffix(second.count)
        XCTAssertEqual(sentFirst[sentFirst.startIndex + 2], 0x64 ^ 0xFF)
        XCTAssertTrue(Data(sentFirst).isCRCValid, "the first record's CRC was recomputed")
        XCTAssertEqual(Data(sentSecond), second, "the second record is untouched")
    }

    func testNamesComeFromTheOwningService() {
        XCTAssertEqual(FaultInjectingMessageQueue.name(of: statusChanged), InsulinDeliveryCharacteristicUUID.statusChanged.name)
        XCTAssertEqual(FaultInjectingMessageQueue.name(of: CBUUID(string: "2AA7")), CGMCharacteristicUUID.measurement.name)
        XCTAssertEqual(FaultInjectingMessageQueue.name(of: CBUUID(string: "FFFF")), "FFFF")
    }
}
