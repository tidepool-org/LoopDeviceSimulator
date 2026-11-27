//
//  ClientIdentificationChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-18.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

struct ClientIdentificationChangedHistoryEvent: PumpHistoryEvent {
    /// `identification` is whatever the profile defines (a certificate, say); the size prefix is the v2 field.
    static func createEventData(identification: Data) -> Data {
        var eventData = Data(UInt16(identification.count))
        eventData.append(identification)
        return eventData
    }

    let type: IDHistoryEventType = .clientInformationChanged

    let recordNumber: RecordNumber

    let relativeOffset: TimeInterval

    let eventData: Data

    var dataSize: UInt16 {
        eventData[eventData.startIndex...].to(UInt16.self)
    }

    var data: Data {
        Data(eventData.dropFirst(2))
    }
}

extension ClientIdentificationChangedHistoryEvent {
    var description: String {
        "ClientIdentificationChangedHistoryEvent dataSize: \(dataSize), data: \(data.hexadecimalString), recordNumber: \(recordNumber), relativeOffset: \(relativeOffset)"
    }
}
