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
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: TesterSettingsStore!

    override func setUp() {
        suite = "TesterSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = TesterSettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
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

    func testForgetClearsOneOwnerAndTheServerNameSeparately() {
        store.save(InsulinDeliveryServerViewModel.Settings.defaults, for: .pumpServer)
        store.save(CGMServerViewModel.Settings.defaults, for: .cgmServer)
        defaults.set("MyPump", forKey: TesterSettingsStore.serverNameKey)

        store.forget(.pumpServer)
        XCTAssertNil(store.load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer))
        XCTAssertNotNil(store.load(CGMServerViewModel.Settings.self, for: .cgmServer))

        store.forgetServerName()
        XCTAssertNil(defaults.string(forKey: TesterSettingsStore.serverNameKey))
    }

    /// Infinity and NaN have no JSON form; the store writes them as strings and reads them back.
    func testNonFiniteValuesStillRoundTrip() {
        var settings = CGMServerViewModel.Settings.defaults
        settings.trace = .constant(mgdl: .infinity)
        settings.clockOffset = .nan
        store.save(settings, for: .cgmServer)

        let reloaded = TesterSettingsStore(defaults: defaults).load(CGMServerViewModel.Settings.self, for: .cgmServer)
        XCTAssertEqual(reloaded?.trace, .constant(mgdl: .infinity))
        XCTAssertTrue(reloaded?.clockOffset.isNaN ?? false)
    }

    /// A save that cannot be written must not be remembered as the stored value.
    func testASaveThatFailsIsNotCachedAsSaved() {
        store.save(InsulinDeliveryServerViewModel.Settings.defaults, for: .pumpServer)
        var changed = InsulinDeliveryServerViewModel.Settings.defaults
        changed.bolusEntry = "3.0"
        store.save(changed, for: .pumpServer)
        XCTAssertEqual(TesterSettingsStore(defaults: defaults).load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer)?.bolusEntry, "3.0")
    }

    /// A blob written by an older build lacks the keys added since; they come back as defaults, the rest survives.
    func testOlderPumpSettingsWithoutNewKeysKeepWhatTheyHad() throws {
        defaults.set(Data(#"{"isPumpBehaviourEnabled":false,"commandResponseOverride":"fail","bolusEntry":"2.5"}"#.utf8), forKey: "testerSettings.pumpServer")
        let loaded = try XCTUnwrap(store.load(InsulinDeliveryServerViewModel.Settings.self, for: .pumpServer))
        XCTAssertFalse(loaded.isPumpBehaviourEnabled)
        XCTAssertEqual(loaded.commandResponseOverride, "fail")
        XCTAssertEqual(loaded.bolusEntry, "2.5")
        XCTAssertEqual(loaded.featureFlags, InsulinDeliveryServerViewModel.defaultFeatureFlags.rawValue)
    }

    func testOlderCGMSettingsWithoutNewKeysKeepWhatTheyHad() throws {
        defaults.set(Data(#"{"requiresEncryption":true,"warmupDuration":300,"sensorRangeHigh":350}"#.utf8), forKey: "testerSettings.cgmServer")
        let loaded = try XCTUnwrap(store.load(CGMServerViewModel.Settings.self, for: .cgmServer))
        XCTAssertTrue(loaded.requiresEncryption)
        XCTAssertEqual(loaded.warmupDuration, 300)
        XCTAssertEqual(loaded.sensorRangeHigh, 350)
        XCTAssertEqual(loaded.commandResponseOverride, CGMServerViewModel.Settings.defaults.commandResponseOverride)
        XCTAssertEqual(loaded.trace, CGMServerViewModel.Settings.defaults.trace)
    }

    func testAScenarioNoLongerBundledFallsBackToNoTrace() {
        let stored = CGMServerViewModel.Settings.Trace.scenario(name: "not a bundled scenario")
        XCTAssertNil(stored.trace)
        XCTAssertNotNil(CGMServerViewModel.Settings.Trace.scenario(name: CGMServerViewModel.defaultScenarioName).trace)
    }
}
