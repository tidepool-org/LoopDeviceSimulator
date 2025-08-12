//
//  AcousticSignalSuspensionParametersChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct AcousticSignalSuspensionParametersChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> AcousticSignalSuspensionParametersChangedHistoryEvent {
        let status = IDStateFlag.enabled
        let startTime: UInt16 = 480
        let duration: UInt16 = 1320
        let repeatStatus: IDRepeatFlag = .repeating
        var eventData = Data(status.rawValue)
        eventData.append(startTime)
        eventData.append(duration)
        eventData.append(repeatStatus.rawValue)
        return AcousticSignalSuspensionParametersChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
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
        "AcousticSignalSuspensionParametersChangedHistoryEvent state: \(String(describing: state)), startTime: \(String(describing: startTime.minutes)), duration: \(String(describing: duration.minutes)), repeatStatus: \(String(describing: repeatStatus))"
    }
}
