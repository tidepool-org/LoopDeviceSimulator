//
//  InsulinDeliveryStartSoundParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct InsulinDeliveryStartSoundParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createEventData(state: IDStateFlag) -> Data {
        Data(state.rawValue)
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
        "InsulinDeliveryStartSoundParametersChangedHistoryEvent state: \(String(describing: state)), recordNumber: \(recordNumber), relativeOffset: \(relativeOffset)"
    }
}
