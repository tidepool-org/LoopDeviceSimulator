//
//  TesterSettingsStoreTests.swift
//  DeviceSimulatorTests
//
//  Created by Nathaniel Hamming on 2026-11-10.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import XCTest
@testable import DeviceSimulator

/// The tester's configuration survives a relaunch and Reset to Defaults clears it.
final class TesterSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: TesterSettingsStore!

    override func setUp() {
        let suite = "TesterSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = TesterSettingsStore(defaults: defaults)
    }

    func testPumpSettingsRoundTrip() {
        var settings = InsulinDeliveryServerViewModel.Settings.defaults
        settings.isPumpBehaviourEnabled = false
        settings.commandResponseOverride = "refuse"
        settings.bolusEntry = "2.5"
        store.save(settings, for: .pumpServer)

        let reloaded = TesterSettingsStore(defaults: defaults).load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer)
        XCTAssertEqual(reloaded, settings)
    }

    func testCGMSettingsRoundTripIncludingTraceAndAlertLevels() {
        var settings = CGMServerViewModel.Settings.defaults
        settings.trace = .sineCurve(base: 110, amplitude: 30, period: 1800)
        settings.alertLevels.patientHigh = 220
        settings.calibrationSchedule = .daily
        settings.sensorRangeHigh = 350
        store.save(settings, for: .cgmServer)

        let reloaded = TesterSettingsStore(defaults: defaults).load(CGMServerViewModel.Settings.self, for: .cgmServer)
        XCTAssertEqual(reloaded, settings)
        XCTAssertEqual(reloaded?.alertLevels.levels.patientHigh, 220)
    }

    func testNothingStoredMeansDefaults() {
        XCTAssertNil(store.load(CGMServerViewModel.Settings.self, for: .cgmServer))
        XCTAssertNil(store.load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer))
    }

    func testUnreadableStoredValueIsTreatedAsDefaults() {
        defaults.set(Data("not json".utf8), forKey: "testerSettings.pumpServer")
        XCTAssertNil(store.load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer))
    }

    func testForgetAllClearsEveryOwnerAndTheServerName() {
        store.save(InsulinDeliveryServerViewModel.Settings.defaults, for: .pumpServer)
        store.save(CGMServerViewModel.Settings.defaults, for: .cgmServer)
        defaults.set("MyPump", forKey: TesterSettingsStore.serverNameKey)

        store.forgetAll()

        XCTAssertNil(store.load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer))
        XCTAssertNil(store.load(CGMServerViewModel.Settings.self, for: .cgmServer))
        XCTAssertNil(defaults.string(forKey: TesterSettingsStore.serverNameKey))
    }

    func testAScenarioNoLongerBundledFallsBackToNoTrace() {
        let stored = CGMServerViewModel.Settings.Trace.scenario(name: "not a bundled scenario")
        XCTAssertNil(stored.trace)
        XCTAssertNotNil(CGMServerViewModel.Settings.Trace.scenario(name: CGMServerViewModel.defaultScenarioName).trace)
    }
}
