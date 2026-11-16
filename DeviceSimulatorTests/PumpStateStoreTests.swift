//
//  PumpStateStoreTests.swift
//  DeviceSimulatorTests
//
//  Created by Nathaniel Hamming on 2026-11-16.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import XCTest
@testable import DeviceSimulator

/// The pump's state round-trips through the property list on disk and is dropped on reset.
final class PumpStateStoreTests: XCTestCase {
    private var folder: URL!
    private var store: PumpStateStore!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PumpStateStoreTests.\(UUID().uuidString)", isDirectory: true)
        store = PumpStateStore(folder: folder)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The pump's persisted form: nested dictionaries, dates, data and numbers, as the kit produces them.
    private let state: [String: Any] = [
        "basalDelivered": 2.5,
        "lastDeliveryUpdate": Date(timeIntervalSince1970: 1_800_000_000),
        "basalProfile": Data([0x01, 0x02]),
        "pumpState": ["setupCompleted": true, "totalBasalDelivered": 3.0] as [String: Any],
    ]

    /// Lets the store's background writer finish.
    private func settle() {
        let waited = expectation(description: "writer settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waited.fulfill() }
        wait(for: [waited], timeout: 2)
    }

    func testRoundTrip() throws {
        store.save(state)
        settle()

        let loaded = try XCTUnwrap(PumpStateStore(folder: folder).load())
        XCTAssertEqual(loaded["basalDelivered"] as? Double, 2.5)
        XCTAssertEqual(loaded["lastDeliveryUpdate"] as? Date, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(loaded["basalProfile"] as? Data, Data([0x01, 0x02]))
        XCTAssertEqual((loaded["pumpState"] as? [String: Any])?["setupCompleted"] as? Bool, true)
    }

    /// A new accounting stamp with nothing else changed is not written; a changed total is, stamp included.
    func testOnlyAMovedAccountingStampIsNotWritten() throws {
        store.save(state)
        var stampOnly = state
        stampOnly["lastDeliveryUpdate"] = Date(timeIntervalSince1970: 1_800_000_600)
        store.save(stampOnly)
        settle()
        XCTAssertEqual(try XCTUnwrap(PumpStateStore(folder: folder).load())["lastDeliveryUpdate"] as? Date, Date(timeIntervalSince1970: 1_800_000_000))

        var delivered = stampOnly
        delivered["basalDelivered"] = 2.6
        store.save(delivered)
        settle()
        let loaded = try XCTUnwrap(PumpStateStore(folder: folder).load())
        XCTAssertEqual(loaded["basalDelivered"] as? Double, 2.6)
        XCTAssertEqual(loaded["lastDeliveryUpdate"] as? Date, Date(timeIntervalSince1970: 1_800_000_600))
    }

    func testNothingStoredLoadsNil() {
        XCTAssertNil(store.load())
    }

    func testForgetRemovesTheFile() throws {
        store.save(state)
        store.forget()
        settle()
        XCTAssertNil(PumpStateStore(folder: folder).load())
    }
}
