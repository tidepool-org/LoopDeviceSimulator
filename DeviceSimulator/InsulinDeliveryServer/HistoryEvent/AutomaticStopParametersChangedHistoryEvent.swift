//
//  AutomaticStopParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct AutomaticStopParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> AutomaticStopParametersChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let maxTimeout: UInt16 = 1000
        var eventData = Data(status.rawValue)
        eventData.append(maxTimeout)
        return AutomaticStopParametersChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .automaticStopParametersChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }
    
    var maxTimeout: TimeInterval {
        TimeInterval(minutes: Double(eventData[eventData.startIndex.advanced(by: 1)...].to(UInt16.self)))
    }
}

extension AutomaticStopParametersChangedHistoryEvent {
    var description: String {
        "AutomaticStopParametersChangedHistoryEvent state: \(String(describing: state)), maxTimeout: \(maxTimeout)"
    }
}
