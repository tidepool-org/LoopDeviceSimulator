//
//  AcousticSignalSuspensionParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct AcousticSignalSuspensionParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createEventData(state: IDStateFlag, startTime: TimeInterval, duration: TimeInterval, repeatStatus: IDRepeatFlag) -> Data {
        var eventData = Data(state.rawValue)
        eventData.append(UInt16(startTime.minutes))
        eventData.append(UInt16(duration.minutes))
        eventData.append(repeatStatus.rawValue)
        return eventData
    }

    let type: IDHistoryEventType = .acousticSignalSuspensionParametersChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var state: IDStateFlag? {
        IDStateFlag(rawValue: eventData[eventData.startIndex...].to(IDStateFlag.RawValue.self))
    }

    var startTime: TimeInterval {
        TimeInterval(minutes: Double(eventData[eventData.startIndex.advanced(by: 1)...].to(UInt16.self)))
    }

    var duration: TimeInterval {
        TimeInterval(minutes: Double(eventData[eventData.startIndex.advanced(by: 3)...].to(UInt16.self)))
    }

    var repeatStatus: IDRepeatFlag? {
        IDRepeatFlag(rawValue: eventData[eventData.startIndex.advanced(by: 5)...].to(IDRepeatFlag.RawValue.self))
    }
}

extension AcousticSignalSuspensionParametersChangedHistoryEvent {
    var description: String {
        "AcousticSignalSuspensionParametersChangedHistoryEvent state: \(String(describing: state)), startTime: \(startTime.minutes) min, duration: \(duration.minutes) min, repeatStatus: \(String(describing: repeatStatus)), recordNumber: \(recordNumber), relativeOffset: \(relativeOffset)"
    }
}
