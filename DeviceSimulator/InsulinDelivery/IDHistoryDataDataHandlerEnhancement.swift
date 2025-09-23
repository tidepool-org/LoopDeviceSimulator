//
//  IDHistoryDataDataHandlerEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

class IDHistoryDataCharacteristicEnhancement: IDHistoryDataCharacteristic {
    override func sendHistoryEvent(_ historyEvent: any PumpHistoryEvent) {
        let response = historyEvent.dataEnhancement
        indicateResponse(response)
    }
}

extension PumpHistoryEvent {
    var dataEnhancement: Data {
        // both recordNumber and relativeOffset are UInt24
        let recordNumberData = Data(recordNumber).subdata(in: 0..<3)
        let relativeOffsetData = Data(UInt32(relativeOffset.seconds)).subdata(in: 0..<3)
        
        var data = Data(type.rawValue)
        data.append(recordNumberData)
        data.append(relativeOffsetData)
        data.append(eventData)
        return data
    }
}

class IDHistoryDataDataHandlerEnhancement: IDHistoryDataHandler {
    override class func createPumpHistoryEvent(type: IDHistoryEventType, recordNumber: RecordNumber, relativeOffet: TimeInterval, eventData: Data) -> (any PumpHistoryEvent)? {
        guard type != .referenceTime else {
            return ReferenceTimeHistoryEventEnhancement(recordNumber: recordNumber, relativeOffset: relativeOffet, eventData: eventData)
        }
        return PumpHistoryEventFactory.createPumpHistoryEvent(type: type, recordNumber: recordNumber, relativeOffet: relativeOffet, eventData: eventData)
    }
    
    class override func recordNumber(forResponse response: Data) -> RecordNumber {
        // record number is UInt24, but placed it in a UInt32
        let recordNumber = response[response.startIndex.advanced(by: 2)...].to(RecordNumber.self)
        return RecordNumber(recordNumber & 0x00ffffff)
    }
    
    class override func relativeOffset(forResponse response: Data) -> TimeInterval {
        // relative offset is UInt24 with units of seconds
        let relativeOffset = response[response.startIndex.advanced(by: 5)...].to(UInt32.self)
        return TimeInterval.seconds(Int(relativeOffset & 0x00ffffff))
    }
}
