//
//  ReferenceTimeHistoryEventEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-23.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit
import BluetoothCommonKit

public struct ReferenceTimeHistoryEventEnhancement: PumpHistoryEvent {
    public let type: IDHistoryEventType = .referenceTime

    public let recordNumber: RecordNumber

    public let relativeOffset: TimeInterval

    public let eventData: Data
    
    public static let offsetIncrement: TimeInterval = .minutes(15)

    public init(recordNumber: RecordNumber, relativeOffset: TimeInterval, eventData: Data) {
        self.recordNumber = recordNumber
        self.relativeOffset = relativeOffset
        self.eventData = eventData
    }
    
    var recordingReason: RecordingReason {
        guard let recordingReason = RecordingReason(rawValue: eventData[eventData.startIndex...].to(RecordingReason.RawValue.self))
        else {
            return .undetermined
        }
        return recordingReason
    }

    func date(using timeZone: TimeZone) -> Date? {
        Date(gattDateTime: eventData[eventData.startIndex.advanced(by: 1)...7], timeZone: timeZone)
    }
    
    var date: Date? {
        // This date is always reported with UTC time zone
        Date(gattDateTime: eventData[eventData.startIndex.advanced(by: 1)...7], timeZone: .utc)
    }
    
    var timeSource: TimeSource? {
        TimeSource(rawValue: eventData[eventData.startIndex.advanced(by: 8)...].to(TimeSource.RawValue.self))
   }

    var timeZoneAndDSTOffset: TimeInterval {
        // the units are 15-minute incrementsNateH
        TimeInterval.minutes(Int(eventData[eventData.startIndex.advanced(by: 9)...].to(UInt8.self))) * ReferenceTimeHistoryEventEnhancement.offsetIncrement
    }
}

extension ReferenceTimeHistoryEventEnhancement {
    public var description: String {
        "ReferenceTimeHistoryEvent date: \(String(describing: date)), timeSource: \(String(describing: timeSource)), timeZoneAndDSTOffset: \(String(describing: timeZoneAndDSTOffset)), recordingReason: \(recordingReason), recordNumber: \(recordNumber), relativeOffset: \(relativeOffset), eventData: \(eventData.hexadecimalString)"
    }
}

extension ReferenceTimeHistoryEventEnhancement {
    static public func createEventData(_ referenceTime: Date,
                                       reason: RecordingReason,
                                       timeSource: TimeSource = .networkTimeProtocol,
                                       timeZoneAndDSTOffset: TimeInterval) -> Data
    {
        var eventData = Data(reason.rawValue)
        eventData.append(referenceTime.gattDateTime(using: .utc))
        eventData.append(timeSource.rawValue)
        eventData.append(UInt8((timeZoneAndDSTOffset/offsetIncrement)))
        return eventData
    }
}
