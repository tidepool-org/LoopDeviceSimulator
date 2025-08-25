//
//  ReservoirLevelWarningLimitChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct ReservoirLevelWarningLimitChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> ReservoirLevelWarningLimitChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let warningLimit: Double = 70
        var eventData = Data(status.rawValue)
        eventData.append(warningLimit.sfloat)
        return ReservoirLevelWarningLimitChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .reservoirLevelWarningLimitChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data
    
    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var warningLimit: Double? {
        Data(eventData[eventData.startIndex.advanced(by: 1)...].to(UInt16.self)).sfloatToDouble()
    }
}

extension ReservoirLevelWarningLimitChangedHistoryEvent {
    var description: String {
        "ReservoirLevelWarningLimitChangedHistoryEvent state: \(String(describing: state)), warningLimit: \(String(describing: warningLimit))"
    }
}
