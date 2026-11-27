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
    
    // Qualified: BluetoothCommonKit's Device Time service declares its own TimeSource.
    var timeSource: InsulinDeliveryServiceKit.TimeSource? {
        InsulinDeliveryServiceKit.TimeSource(rawValue: eventData[eventData.startIndex.advanced(by: 8)...].to(InsulinDeliveryServiceKit.TimeSource.RawValue.self))
    }

    /// TZ/DST Offset: a signed count of 15-minute units from UTC.
    var timeZoneAndDSTOffset: TimeInterval {
        TimeInterval(eventData[eventData.startIndex.advanced(by: 9)...].to(Int8.self)) * ReferenceTimeHistoryEventEnhancement.offsetIncrement
    }

    /// The kit records Reference Time in the v1 layout (Time Zone, DST Offset); this is the same moment in the
    /// v2 layout (Time Source, TZ/DST Offset). Both are ten octets, so the record keeps its size.
    static func convertingFromV1(_ event: PumpHistoryEvent, timeSource: InsulinDeliveryServiceKit.TimeSource) -> PumpHistoryEvent {
        guard event.type == .referenceTime, event.eventData.count == 10 else { return event }
        let data = event.eventData
        // v1: Time Zone in 15-minute units, then a DST Offset code.
        let timeZoneUnits = Int(data[data.startIndex.advanced(by: 8)...].to(Int8.self))
        let dstUnits: Int
        switch DSTOffset(rawValue: data[data.startIndex.advanced(by: 9)...].to(UInt8.self)) {
        case .daylightHalfHour: dstUnits = 2
        case .daylight1Hour: dstUnits = 4
        case .daylight2Hour: dstUnits = 8
        default: dstUnits = 0
        }
        var eventData = Data(data.prefix(8))   // reason and date time are unchanged
        eventData.append(timeSource.rawValue)
        eventData.append(Int8(clamping: timeZoneUnits + dstUnits))
        return ReferenceTimeHistoryEventEnhancement(recordNumber: event.recordNumber, relativeOffset: event.relativeOffset, eventData: eventData)
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
                                       timeSource: InsulinDeliveryServiceKit.TimeSource = .networkTimeProtocol,
                                       timeZoneAndDSTOffset: TimeInterval) -> Data
    {
        var eventData = Data(reason.rawValue)
        eventData.append(referenceTime.gattDateTime(using: .utc))
        eventData.append(timeSource.rawValue)
        eventData.append(Int8(timeZoneAndDSTOffset / offsetIncrement))
        return eventData
    }
}
