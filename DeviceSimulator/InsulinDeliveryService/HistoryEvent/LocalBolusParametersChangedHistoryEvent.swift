//
//  LocalBolusParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit

struct LocalBolusParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> LocalBolusParametersChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let stepValue: Double = 0.5
        let maxAmount: Double = 10
        var eventData = Data(status.rawValue)
        eventData.append(stepValue.sfloat)
        eventData.append(maxAmount.sfloat)
        return LocalBolusParametersChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .localBolusParametersChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data
    
    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var stepValue: Double? {
        Data(eventData[eventData.startIndex.advanced(by: 1)...].to(SFLOAT.self)).sfloatToDouble()
    }
    
    var maxAmount: Double? {
        Data(eventData[eventData.startIndex.advanced(by: 3)...].to(SFLOAT.self)).sfloatToDouble()
    }
}

extension LocalBolusParametersChangedHistoryEvent {
    var description: String {
        "LocalBolusParametersChangedHistoryEvent state: \(String(describing: state)), stepValue: \(String(describing: stepValue)), maxAmount: \(String(describing: maxAmount))"
    }
}
