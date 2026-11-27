//
//  IDSv2Wire.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-27.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

// IDS v2 inserts Max Basal Rate and Local Bolus into the Command Control Point opcode table, so every opcode
// from Set TBR Adjustment onward moves to the next Hamming code. The kit keeps the v1 values, so the simulator
// speaks v1 internally and rewrites opcodes at the edges: the client when it writes and receives, the server in
// the control point's write handler and in the queue its responses leave through. New procedures whose v2 value
// is an old v1 value get a private internal value (0xA + the wire value) so the two spaces never overlap.
extension IDCommandControlPointOpcode {
    /// Internal value → v2 wire value. Anything not listed is the same on the wire.
    static let v2WireValues: [UInt16: UInt16] = [
        // new procedures whose v2 value collides with a v1 value
        setMaxBasalRateAmount.rawValue: 0x0fff,
        getMaxBasalRateAmount.rawValue: 0x1111,
        getMaxBasalRateAmountResponse.rawValue: 0x111e,
        setLocalBolusParameters.rawValue: 0x1248,
        getLocalBolusParameters.rawValue: 0x1274,
        getLocalBolusParametersResponse.rawValue: 0x127b,
        // v1 procedures shifted by the insertions
        setTempBasalAdjustment.rawValue: 0x1122,
        cancelTempBasalAdjustment.rawValue: 0x112d,
        getTempBasalTemplate.rawValue: 0x1144,
        getTempBasalTemplateResponse.rawValue: 0x114b,
        setTempBasalTemplate.rawValue: 0x1177,
        setTempBasalTemplateResponse.rawValue: 0x1178,
        setBolus.rawValue: 0x1187,
        setBolusResponse.rawValue: 0x1188,
        cancelBolus.rawValue: 0x11b4,
        cancelBolusResponse.rawValue: 0x11bb,
        getAvailableBoluses.rawValue: 0x11d2,
        getAvailableBolusesResponse.rawValue: 0x11dd,
        getBolusTemplate.rawValue: 0x11e1,
        getBolusTemplateResponse.rawValue: 0x11ee,
        setBolusTemplate.rawValue: 0x1212,
        setBolusTemplateResponse.rawValue: 0x121d,
        getMaxBolusAmount.rawValue: 0x1221,
        getMaxBolusAmountResponse.rawValue: 0x122e,
        setMaxBolusAmount.rawValue: 0x1247,
        getTemplateStatusAndDetails.rawValue: 0x1284,
        getTemplateStatusAndDetailsResponse.rawValue: 0x128b,
        resetTemplateStatus.rawValue: 0x12b7,
        resetTemplateStatusResponse.rawValue: 0x12b8,
        activateProfileTemplates.rawValue: 0x12d1,
        activateProfileTemplatesResponse.rawValue: 0x12de,
        getActivatedProfileTemplates.rawValue: 0x12e2,
        getActivatedProfileTemplatesResponse.rawValue: 0x12ed,
        startPriming.rawValue: 0x1414,
        stopPriming.rawValue: 0x141b,
        setInitialResevoirFillLevel.rawValue: 0x1427,
        resetResevoirInsulinOperationTime.rawValue: 0x1428,
        readISFProfileTemplates.rawValue: 0x1441,
        readISFProfileTemplatesResponse.rawValue: 0x144e,
        writeISFProfileTemplate.rawValue: 0x1472,
        writeISFProfileTemplateResponse.rawValue: 0x147d,
        readI2CHOProfileTemplates.rawValue: 0x1482,
        readI2CHOProfileTemplatesResponse.rawValue: 0x148d,
        writeI2CHOProfileTemplate.rawValue: 0x14b1,
        writeI2CHOProfileTemplateResponse.rawValue: 0x14be,
        readTargetGlucoseRangeProfileTemplates.rawValue: 0x14d7,
        readTargetGlucoseRangeProfileTemplatesResponse.rawValue: 0x14d8,
        writeTargetGlucoseRangeProfileTemplate.rawValue: 0x14e4,
        writeTargetGlucoseRangeProfileTemplateResponse.rawValue: 0x14eb,
    ]

    static let v2InternalValues: [UInt16: UInt16] = Dictionary(uniqueKeysWithValues: v2WireValues.map { ($1, $0) })

    var v2WireValue: UInt16 { Self.v2WireValues[rawValue] ?? rawValue }

    init(v2WireValue: UInt16) {
        self.init(rawValue: Self.v2InternalValues[v2WireValue] ?? v2WireValue)
    }
}

extension Data {
    /// Edits a message in place and redoes its E2E trailer: a request ends in a CRC, a response in a counter
    /// and a CRC. The counter is kept, the CRC recomputed over the edited bytes.
    func rewritingE2EBody(hasE2E: Bool, hasCounter: Bool, _ edit: (inout Data) -> Void) -> Data {
        let trailerLength = hasE2E ? (hasCounter ? 3 : 2) : 0
        guard count >= trailerLength else { return self }
        var body = Data(dropLast(trailerLength))
        let trailer = Data(suffix(trailerLength))
        edit(&body)
        guard hasE2E else { return body }
        if hasCounter { body.append(trailer[trailer.startIndex]) }
        return body.appendingCRC()
    }
}

enum IDSv2Wire {
    /// Rewrites the opcode in the first two octets and, after a Response Code, the echoed request opcode.
    static func translateCommand(_ data: Data, hasE2E: Bool, isResponse: Bool, toWire: Bool) -> Data {
        guard data.count >= 2 + (hasE2E ? (isResponse ? 3 : 2) : 0) else { return data }
        let map: (UInt16) -> UInt16 = toWire
            ? { IDCommandControlPointOpcode(rawValue: $0).v2WireValue }
            : { IDCommandControlPointOpcode(v2WireValue: $0).rawValue }
        return data.rewritingE2EBody(hasE2E: hasE2E, hasCounter: isResponse) { body in
            rewrite(&body, at: 0, with: map)
            if isResponse,
               body.count >= 4,
               IDCommandControlPointOpcode(rawValue: body[body.startIndex...].to(UInt16.self)) == .responseCode
            {
                rewrite(&body, at: 2, with: map)
            }
        }
    }

    private static func rewrite(_ data: inout Data, at offset: Int, with map: (UInt16) -> UInt16) {
        let index = data.startIndex.advanced(by: offset)
        let value = data[index...].to(UInt16.self)
        data.replaceSubrange(index..<index.advanced(by: 2), with: Data(map(value)))
    }

    /// The server's view of a request the controller wrote.
    static func commandRequestFromWire(_ request: Data, hasE2E: Bool) -> Data {
        translateCommand(request, hasE2E: hasE2E, isResponse: false, toWire: false)
    }

    /// What the controller writes for a request the kit built.
    static func commandRequestToWire(_ request: Data) -> Data {
        translateCommand(request, hasE2E: false, isResponse: false, toWire: true)
    }

    /// The controller's view of a response or Command Data notification the pump sent.
    static func commandResponseFromWire(_ response: Data, hasE2E: Bool) -> Data {
        translateCommand(response, hasE2E: hasE2E, isResponse: true, toWire: false)
    }
}

/// Sits between the pump and the queue that reaches the radio, so every Command Control Point response and
/// Command Data notification leaves with v2 opcodes. Wrap the fault-injecting queue with this one, so faults
/// still land on the bytes that go out.
final class IDSv2WireMessageQueue: MessagingQueue, InspectableMessagingQueue {
    private let inner: any InspectableMessagingQueue
    var hasE2ECRC: () -> Bool = { false }

    init(wrapping inner: any InspectableMessagingQueue) {
        self.inner = inner
    }

    var gattServer: GATTService! { inner.gattServer }
    var hasMessagesInQueue: Bool { inner.hasMessagesInQueue }
    var queuedItems: [UUIDValuePair] { inner.queuedItems }

    func emptyQueue() {
        inner.emptyQueue()
    }

    func addQueueItem(_ update: UUIDValuePair) {
        let translated = [InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID, InsulinDeliveryCharacteristicUUID.commandData.cbUUID]
        guard translated.contains(update.uuid) else {
            inner.addQueueItem(update)
            return
        }
        let wire = IDSv2Wire.translateCommand(update.value, hasE2E: hasE2ECRC(), isResponse: true, toWire: true)
        if wire != update.value {
            ConsoleOut.shared.logMessage(message: "IDS v2 opcode on the wire: \(wire.hexadecimalString) (internal \(update.value.hexadecimalString))")
        }
        inner.addQueueItem(UUIDValuePair(uuid: update.uuid, value: wire, onSubscribedCentrals: update.onSubscribedCentrals))
    }
}
