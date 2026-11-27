//
//  IDSv2WireTests.swift
//  DeviceSimulatorTests
//
//  Created by Nathaniel Hamming on 2026-11-27.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import XCTest
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit
@testable import DeviceSimulator

/// The simulator keeps the kit's v1 Command Control Point opcodes inside and puts the IDS v2 values on the wire.
final class IDSv2WireTests: XCTestCase {

    // MARK: Opcode table

    func testEveryListedOpcodeRoundTripsThroughTheWire() {
        for (internalValue, wireValue) in IDCommandControlPointOpcode.v2WireValues {
            let opcode = IDCommandControlPointOpcode(rawValue: internalValue)
            XCTAssertEqual(opcode.v2WireValue, wireValue)
            XCTAssertEqual(IDCommandControlPointOpcode(v2WireValue: wireValue), opcode)
        }
    }

    func testWireValuesAreUnique() {
        let wireValues = Array(IDCommandControlPointOpcode.v2WireValues.values)
        XCTAssertEqual(Set(wireValues).count, wireValues.count)
    }

    func testNewProceduresTakeTheirV2Values() {
        XCTAssertEqual(IDCommandControlPointOpcode.setMaxBasalRateAmount.v2WireValue, 0x0fff)
        XCTAssertEqual(IDCommandControlPointOpcode.getMaxBasalRateAmount.v2WireValue, 0x1111)
        XCTAssertEqual(IDCommandControlPointOpcode.getMaxBasalRateAmountResponse.v2WireValue, 0x111e)
        XCTAssertEqual(IDCommandControlPointOpcode.setLocalBolusParameters.v2WireValue, 0x1248)
        XCTAssertEqual(IDCommandControlPointOpcode.getLocalBolusParameters.v2WireValue, 0x1274)
        XCTAssertEqual(IDCommandControlPointOpcode.getLocalBolusParametersResponse.v2WireValue, 0x127b)
        XCTAssertEqual(IDCommandControlPointOpcode.setAutomaticStopParameters.v2WireValue, 0x1717)
        XCTAssertEqual(IDCommandControlPointOpcode.resetAutomaticStopTimeout.v2WireValue, 0x172b)
        XCTAssertEqual(IDCommandControlPointOpcode.setInsulinDeliveryStartSoundParameters.v2WireValue, 0x17db)
        XCTAssertEqual(IDCommandControlPointOpcode.getInsulinDeliveryStartSoundParametersResponse.v2WireValue, 0x17e8)
    }

    func testShiftedProceduresMoveAndEarlierOnesStay() {
        XCTAssertEqual(IDCommandControlPointOpcode.setTempBasalAdjustment.v2WireValue, 0x1122)
        XCTAssertEqual(IDCommandControlPointOpcode.setBolus.v2WireValue, 0x1187)
        XCTAssertEqual(IDCommandControlPointOpcode.setMaxBolusAmount.v2WireValue, 0x1247)
        XCTAssertEqual(IDCommandControlPointOpcode.getTemplateStatusAndDetailsResponse.v2WireValue, 0x128b)
        XCTAssertEqual(IDCommandControlPointOpcode.writeTargetGlucoseRangeProfileTemplateResponse.v2WireValue, 0x14eb)
        XCTAssertEqual(IDCommandControlPointOpcode.responseCode.v2WireValue, 0x0f55)
        XCTAssertEqual(IDCommandControlPointOpcode.writeBasalRateTemplateResponse.v2WireValue, 0x0ff0)
        // A v2 value that is also a v1 value resolves to the v2 meaning.
        XCTAssertEqual(IDCommandControlPointOpcode(v2WireValue: 0x0fff), .setMaxBasalRateAmount)
        XCTAssertEqual(IDCommandControlPointOpcode(v2WireValue: 0x1248), .setLocalBolusParameters)
    }

    // MARK: Requests

    func testRequestTranslationRewritesOnlyTheOpcode() {
        var request = Data(IDCommandControlPointOpcode.setBolus.rawValue)
        request.append(contentsOf: [0x01, 0x02, 0x03])
        let wire = IDSv2Wire.commandRequestToWire(request)
        XCTAssertEqual(Data(wire.prefix(2)), Data(UInt16(0x1187)))
        XCTAssertEqual(Data(wire.dropFirst(2)), Data(request.dropFirst(2)))
        XCTAssertEqual(IDSv2Wire.commandRequestFromWire(wire, hasE2E: false), request)
    }

    func testRequestCRCIsRecomputedAroundTheNewOpcode() {
        var request = Data(IDCommandControlPointOpcode.setBolus.rawValue)
        request.append(contentsOf: [0x01, 0x02, 0x03])
        request = request.appendingCRC()
        let wire = IDSv2Wire.translateCommand(request, hasE2E: true, isResponse: false, toWire: true)
        XCTAssertEqual(Data(wire.prefix(2)), Data(UInt16(0x1187)))
        XCTAssertTrue(wire.isCRCValid)
        XCTAssertEqual(IDSv2Wire.commandRequestFromWire(wire, hasE2E: true), request)
    }

    // MARK: Responses

    func testResponseCodeEchoesTheRequestOpcodeInV2() {
        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.setBolus.rawValue)
        response.append(UInt8(0x0f))   // success
        response.append(UInt8(7))      // E2E counter
        response = response.appendingCRC()
        let wire = IDSv2Wire.translateCommand(response, hasE2E: true, isResponse: true, toWire: true)
        XCTAssertEqual(Data(wire.prefix(2)), Data(UInt16(0x0f55)))
        XCTAssertEqual(Data(wire[2..<4]), Data(UInt16(0x1187)))
        XCTAssertEqual(wire[4], 0x0f)
        XCTAssertEqual(wire[5], 7)
        XCTAssertTrue(wire.isCRCValid)
        XCTAssertEqual(IDSv2Wire.commandResponseFromWire(wire, hasE2E: true), response)
    }

    func testSpecificResponseOpcodeIsTranslated() {
        var response = Data(IDCommandControlPointOpcode.setBolusResponse.rawValue)
        response.append(UInt16(3))   // bolus ID
        let wire = IDSv2Wire.translateCommand(response, hasE2E: false, isResponse: true, toWire: true)
        XCTAssertEqual(Data(wire.prefix(2)), Data(UInt16(0x1188)))
        XCTAssertEqual(Data(wire.dropFirst(2)), Data(UInt16(3)))
    }

    func testQueueTranslatesCommandTrafficOnly() {
        let inner = MessageQueue(gattService: MockGattServer())
        let queue = IDSv2WireMessageQueue(wrapping: inner)

        var response = Data(IDCommandControlPointOpcode.setBolusResponse.rawValue)
        response.append(UInt16(3))
        queue.addQueueItem(UUIDValuePair(uuid: InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID, value: response))
        XCTAssertEqual(Data(inner.queuedItems.last!.value.prefix(2)), Data(UInt16(0x1188)))

        var commandData = Data(IDCommandControlPointOpcode.getTemplateStatusAndDetailsResponse.rawValue)
        commandData.append(UInt8(1))
        queue.addQueueItem(UUIDValuePair(uuid: InsulinDeliveryCharacteristicUUID.commandData.cbUUID, value: commandData))
        XCTAssertEqual(Data(inner.queuedItems.last!.value.prefix(2)), Data(UInt16(0x128b)))

        let statusChanged = Data([0x05, 0x00])
        queue.addQueueItem(UUIDValuePair(uuid: InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID, value: statusChanged))
        XCTAssertEqual(inner.queuedItems.last!.value, statusChanged)
    }

    // MARK: Other v2 layouts

    func testFeatureCharacteristicIsNineOctetsWithFourFlagOctets() {
        let characteristic = IDFeatureCharacteristicEnhancement(messageQueue: MessageQueue(gattService: MockGattServer()))
        characteristic.flags = [.supportedBasalRate, .supportedLocalBolus, .supportedAcousticSignalStartInsulinDelivery]
        let data = characteristic.createData()
        XCTAssertEqual(data.count, IDFeatureDataHandlerEnhancement.expectedLength)
        switch IDFeatureDataHandlerEnhancement.handleData(data) {
        case .success(let features):
            // The server may add flags of its own on top of the tester's; what was set must come back.
            XCTAssertTrue(features.flags.isSuperset(of: characteristic.flags), "\(features.flags.v2Description)")
            XCTAssertTrue(features.flags.contains(.supportedAcousticSignalStartInsulinDelivery))
            XCTAssertEqual(features.insulinConcentration, 100)
        case .failure(let error):
            XCTFail("feature characteristic did not parse: \(error)")
        }
    }

    func testResetStatusFlagsMapOntoTheKitLayout() {
        let v2: IDStatusChangedFlagEnhancement = [.totalDailyInsulinStatusChanged, .historyEventRecordedChanged]
        XCTAssertEqual(v2.rawValue, 0b1001)
        XCTAssertEqual(v2.originalFlags, [.totalDailyInsulinStatusChanged, .historyEventRecordedChanged])
        XCTAssertEqual(IDStatusChangedFlag.historyEventRecordedChanged.enhancedFlags, .historyEventRecordedChanged)
    }

    func testReferenceTimeConvertsToTimeSourceAndCombinedOffset() {
        // v1: reason, 7 octets of date time, time zone -5 h in 15-minute units, DST +1 h.
        var v1 = Data([0x33])
        v1.append(contentsOf: [0xe9, 0x07, 0x0b, 0x1b, 0x0c, 0x00, 0x00])
        v1.append(Int8(-20))
        v1.append(UInt8(4))
        let event = ReferenceTimeHistoryEvent(recordNumber: 9, relativeOffset: 60, eventData: v1)
        let v2 = ReferenceTimeHistoryEventEnhancement.convertingFromV1(event, timeSource: .manual)
        XCTAssertEqual(v2.eventData.count, 10)
        XCTAssertEqual(Data(v2.eventData.prefix(8)), Data(v1.prefix(8)))
        XCTAssertEqual(v2.eventData[8], InsulinDeliveryServiceKit.TimeSource.manual.rawValue)
        XCTAssertEqual(Int8(bitPattern: v2.eventData[9]), -16)
        XCTAssertEqual(v2.recordNumber, 9)
        XCTAssertEqual((v2 as? ReferenceTimeHistoryEventEnhancement)?.timeZoneAndDSTOffset, .hours(-4))
    }

    func testAnnunciationAuxInfoRoundTripsFromServerToClient() {
        let characteristic = IDAnnunciationStatusCharacteristicEnhancement(messageQueue: MessageQueue(gattService: MockGattServer()))
        for (type, expected) in [
            (AnnunciationType.bolusCanceled, "bolusID: 1, bolusType: fast, programmed: 4.0 U, delivered: 2.0 U"),
            (.tempBasalOver, "tbrType: absolute, programmedAdjustment: 2.0 U/h, durationProgrammed: 60 min, durationEffective: 60 min, delivered: 2.0 U"),
            (.tempBasalCanceled, "tbrType: absolute, programmedAdjustment: 2.0 U/h, durationProgrammed: 60 min, durationEffective: 30 min, delivered: 1.0 U"),
        ] {
            let annunciation = characteristic.generateAnnunciation(for: type)
            let data = characteristic.createData(for: annunciation)
            guard case .success(let parsed?) = IDAnnunciationStatusDataHandler.handleData(data, e2eProtectionSupported: false) else {
                return XCTFail("\(type) did not parse: \(data.hexadecimalString)")
            }
            XCTAssertEqual(parsed.type, type)
            XCTAssertEqual(parsed.identifier, annunciation?.identifier)
            XCTAssertEqual(AnnunciationAuxInfo.describe(type: parsed.type, auxiliaryData: parsed.auxiliaryData), expected, "\(type): \(parsed.auxiliaryData.hexadecimalString)")
        }
        // Types without a v2 AuxInfo layout are left to the raw hex.
        XCTAssertNil(AnnunciationAuxInfo.describe(type: .automaticStop, auxiliaryData: Data()))
    }

    func testDeliveredBasalRateChangedGainsTheAmountDelivered() {
        var v1 = Data([0x01])   // context present
        v1.append(1.0.sfloat)
        v1.append(2.0.sfloat)
        v1.append(BasalDeliveryContext.aidController.rawValue)
        let event = DeliveredBasalRateChangedHistoryEvent(recordNumber: 4, relativeOffset: 30, eventData: v1)
        let v2 = DeliveredBasalRateChangedHistoryEventEnhancement.addingAmountDelivered(0.75, to: event)
        guard let enhanced = v2 as? DeliveredBasalRateChangedHistoryEventEnhancement else { return XCTFail("not the v2 event") }
        XCTAssertEqual(enhanced.flag, [.deliveryContentPresent, .amountDeliveredPresent])
        XCTAssertEqual(enhanced.oldRate, 1.0)
        XCTAssertEqual(enhanced.newRate, 2.0)
        XCTAssertEqual(enhanced.deliveryContext, .aidController)
        XCTAssertEqual(enhanced.amountDelivered, 0.75)
        XCTAssertEqual(enhanced.eventData.count, 8)
        // Already v2: left alone.
        XCTAssertEqual(DeliveredBasalRateChangedHistoryEventEnhancement.addingAmountDelivered(9, to: enhanced).eventData, enhanced.eventData)
    }
}
