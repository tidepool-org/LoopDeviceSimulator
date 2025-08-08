//
//  ClientIdentificationChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct ClientIdentificationChangedHistoryEvent: PumpHistoryEvent {
    static func createHistoryEvent(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> ClientIdentificationChangedHistoryEvent {
        let dataSize: UInt16 = 10
        let data = Data(hexadecimalString: "00010203040506070809")!
        var eventData = Data(dataSize)
        eventData.append(data)
        return ClientIdentificationChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }

    let type: IDHistoryEventType = .clientInformationChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data
    
    var dataSize: UInt16 {
        eventData[eventData.startIndex...].to(UInt16.self)
    }

    var data: Data {
        eventData.subdata(in: 2..<eventData.endIndex)
    }
}

extension ClientIdentificationChangedHistoryEvent {
    var description: String {
        "ClientIdentificationChangedHistoryEvent dataSize: \(String(describing: dataSize)), data: \(String(describing: data.hexadecimalString))"
    }
}
