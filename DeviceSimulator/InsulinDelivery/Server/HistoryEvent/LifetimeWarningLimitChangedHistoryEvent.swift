//
//  LifetimeWarningLimitChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct LifetimeWarningLimitChangedHistoryEvent: PumpHistoryEvent {
    static func createEventData(state: IDStateFlag, warningLimitInDays: UInt16) -> Data {
        var eventData = Data(state.rawValue)
        eventData.append(warningLimitInDays)
        return eventData
    }

    let type: IDHistoryEventType = .lifetimeWarningLimitChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var warningLimitInDays: UInt16 {
        eventData[eventData.startIndex.advanced(by: 1)...].to(UInt16.self)
    }
}

extension LifetimeWarningLimitChangedHistoryEvent {
    var description: String {
        "LifetimeWarningLimitChangedHistoryEvent state: \(String(describing: state)), warningLimit: \(warningLimitInDays) days, recordNumber: \(recordNumber), relativeOffset: \(relativeOffset)"
    }
}
