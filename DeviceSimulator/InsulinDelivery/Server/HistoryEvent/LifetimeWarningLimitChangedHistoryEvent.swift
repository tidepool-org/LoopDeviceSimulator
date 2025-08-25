//
//  LifetimeWarningLimitChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct LifetimeWarningLimitChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> LifetimeWarningLimitChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let warningLimit: UInt16 = 10
        var eventData = Data(status.rawValue)
        eventData.append(warningLimit)
        return LifetimeWarningLimitChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .lifetimeWarningLimitChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data
    
    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var warningLimit: TimeInterval {
        TimeInterval(days: Double(eventData[eventData.startIndex.advanced(by: 1)...].to(UInt16.self)))
    }
}

extension LifetimeWarningLimitChangedHistoryEvent {
    var description: String {
        "LifetimeWarningLimitChangedHistoryEvent state: \(String(describing: state)), warningLimit: \(String(describing: warningLimit.days))"
    }
}
