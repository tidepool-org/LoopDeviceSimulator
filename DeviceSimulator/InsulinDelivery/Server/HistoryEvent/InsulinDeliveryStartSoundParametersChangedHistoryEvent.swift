//
//  InsulinDeliveryStartSoundParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct InsulinDeliveryStartSoundParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> InsulinDeliveryStartSoundParametersChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let eventData = Data(status.rawValue)
        return InsulinDeliveryStartSoundParametersChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .insulinDeliveryStartSoundParametersChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data
    
    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }
}

extension InsulinDeliveryStartSoundParametersChangedHistoryEvent {
    var description: String {
        "InsulinDeliveryStartSoundParametersChangedHistoryEvent state: \(String(describing: state))"
    }
}
