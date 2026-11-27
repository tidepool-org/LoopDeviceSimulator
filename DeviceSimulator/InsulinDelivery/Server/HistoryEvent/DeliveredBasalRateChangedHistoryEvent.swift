//
//  DeliveredBasalRateChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit

/// v2 adds a Basal Amount Delivered field (flag bit 1) after the Basal Delivery Context. The kit's event only
/// reads the rates, so the client decodes with this one and the server adds the field on the way out.
struct DeliveredBasalRateChangedHistoryEventEnhancement: PumpHistoryEvent {
    let type: IDHistoryEventType = .deliveredBasalRateChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var flag: DeliveredBasalRateChangedFlag {
        DeliveredBasalRateChangedFlag(rawValue: eventData[eventData.startIndex...].to(DeliveredBasalRateChangedFlag.RawValue.self))
    }

    var oldRate: Double {
        Data(eventData[eventData.startIndex.advanced(by: 1)...].to(SFLOAT.self)).sfloatToDouble()
    }

    var newRate: Double {
        Data(eventData[eventData.startIndex.advanced(by: 3)...].to(SFLOAT.self)).sfloatToDouble()
    }

    var deliveryContext: BasalDeliveryContext? {
        guard flag.contains(.deliveryContentPresent), eventData.count >= 6 else { return nil }
        return BasalDeliveryContext(rawValue: eventData[eventData.startIndex.advanced(by: 5)...].to(BasalDeliveryContext.RawValue.self))
    }

    var amountDelivered: Double? {
        guard flag.contains(.amountDeliveredPresent) else { return nil }
        let index = 5 + (flag.contains(.deliveryContentPresent) ? 1 : 0)
        guard eventData.count >= index + 2 else { return nil }
        return Data(eventData[eventData.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
    }

    static func createEventData(oldRate: Double, newRate: Double, deliveryContext: BasalDeliveryContext?, amountDelivered: Double?) -> Data {
        var flag: DeliveredBasalRateChangedFlag = .allZeros
        var eventData = Data()
        eventData.append(oldRate.sfloat)
        eventData.append(newRate.sfloat)
        if let deliveryContext {
            flag.insert(.deliveryContentPresent)
            eventData.append(deliveryContext.rawValue)
        }
        if let amountDelivered {
            flag.insert(.amountDeliveredPresent)
            eventData.append(amountDelivered.sfloat)
        }
        eventData.insert(flag.rawValue, at: 0)
        return eventData
    }

    /// The kit's v1 event with the amount appended; an event that already carries one is left alone.
    static func addingAmountDelivered(_ amount: Double, to event: PumpHistoryEvent) -> PumpHistoryEvent {
        let v1 = DeliveredBasalRateChangedHistoryEventEnhancement(recordNumber: event.recordNumber, relativeOffset: event.relativeOffset, eventData: event.eventData)
        guard event.type == .deliveredBasalRateChanged, event.eventData.count >= 5, !v1.flag.contains(.amountDeliveredPresent) else { return event }
        let eventData = createEventData(oldRate: v1.oldRate, newRate: v1.newRate, deliveryContext: v1.deliveryContext, amountDelivered: amount)
        return DeliveredBasalRateChangedHistoryEventEnhancement(recordNumber: event.recordNumber, relativeOffset: event.relativeOffset, eventData: eventData)
    }
}

extension DeliveredBasalRateChangedHistoryEventEnhancement {
    var description: String {
        "DeliveredBasalRateChangedHistoryEvent oldRate: \(oldRate), newRate: \(newRate), deliveryContext: \(String(describing: deliveryContext)), amountDelivered: \(String(describing: amountDelivered)), recordNumber: \(recordNumber), relativeOffset: \(relativeOffset), eventData: \(eventData.hexadecimalString)"
    }
}
