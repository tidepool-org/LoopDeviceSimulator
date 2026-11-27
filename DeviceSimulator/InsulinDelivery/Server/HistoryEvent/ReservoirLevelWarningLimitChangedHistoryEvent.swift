//
//  ReservoirLevelWarningLimitChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit

struct ReservoirLevelWarningLimitChangedHistoryEvent: PumpHistoryEvent {
    static func createEventData(state: IDStateFlag, warningLimit: Double) -> Data {
        var eventData = Data(state.rawValue)
        eventData.append(warningLimit.sfloat)
        return eventData
    }

    let type: IDHistoryEventType = .reservoirLevelWarningLimitChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var warningLimit: Double? {
        Data(eventData[eventData.startIndex.advanced(by: 1)...].to(SFLOAT.self)).sfloatToDouble()
    }
}

extension ReservoirLevelWarningLimitChangedHistoryEvent {
    var description: String {
        "ReservoirLevelWarningLimitChangedHistoryEvent state: \(String(describing: state)), warningLimit: \(String(describing: warningLimit)) IU, recordNumber: \(recordNumber), relativeOffset: \(relativeOffset)"
    }
}
