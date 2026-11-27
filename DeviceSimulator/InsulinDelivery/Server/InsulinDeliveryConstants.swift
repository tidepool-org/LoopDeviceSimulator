//
//  InsulinDeliveryConstants.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import InsulinDeliveryServiceKit

struct InsulinDeliveryConstants {
    static let serverName: String = "Tidepool-Pump-Simulator"
}

struct AvailableBolusFlag: OptionSet, Hashable, CustomStringConvertible {
    let rawValue: UInt8
    
    static let fast = AvailableBolusFlag(rawValue: 1 << 0)
    static let extended = AvailableBolusFlag(rawValue: 1 << 1)
    static let multiwave  = AvailableBolusFlag(rawValue: 1 << 2)
    static let allZeros = AvailableBolusFlag([])
    
    static var debugDescriptions: [AvailableBolusFlag:String] = {
        var descriptions = [AvailableBolusFlag:String]()
        descriptions[.fast] = "fast"
        descriptions[.extended] = "extended"
        descriptions[.multiwave] = "multiwave"
        return descriptions
    }()
    
    public var description: String {
        var result = [String]()
        for (key, value) in AvailableBolusFlag.debugDescriptions {
            guard self.contains(key) else {
                continue
            }
            result.append(value)
        }
        return "AvailableBolusFlag: \(result)"
    }
}

extension BolusFlag {
    static let deliverySourceLocalBolus = BolusFlag(rawValue: 1 << 5)
    
    static var debugDescriptions: [BolusFlag:String] = {
        var descriptions = [BolusFlag:String]()
        descriptions[.delayTimePresent] = "delayTimePresent"
        descriptions[.templateNumberPresent] = "templateNumberPresent"
        descriptions[.activationTypePresent] = "activationTypePresent"
        descriptions[.deliveryReasonCorrection] = "deliveryReasonCorrection"
        descriptions[.deliveryReasonMeal] = "deliveryReasonMeal"
        descriptions[.deliverySourceLocalBolus] = "deliverySourceLocalBolus"
        return descriptions
    }()
}

extension DeliveredBasalRateChangedFlag {
    static let amountDeliveredPresent = DeliveredBasalRateChangedFlag(rawValue: 1 << 1)
    
    static var debugDescriptions: [DeliveredBasalRateChangedFlag:String] = {
        var descriptions = [DeliveredBasalRateChangedFlag:String]()
        descriptions[.deliveryContentPresent] = "deliveryContentPresent"
        descriptions[.amountDeliveredPresent] = "amountDeliveredPresent"
        return descriptions
    }()
}

// MARK: - enums

extension IDHistoryEventType {
    static public let localBolusParametersChanged = IDHistoryEventType(rawValue: 0x0505)
    static public let automaticStopParametersChanged = IDHistoryEventType(rawValue: 0x050a)
    static public let acousticSignalSuspensionParametersChanged = IDHistoryEventType(rawValue: 0x0536)
    static public let lifetimeWarningLimitChanged = IDHistoryEventType(rawValue: 0x0539)
    static public let reservoirLevelWarningLimitChanged = IDHistoryEventType(rawValue: 0x0550)
    static public let insulinDeliveryStartSoundParametersChanged = IDHistoryEventType(rawValue: 0x055f)
    static public let clientInformationChanged = IDHistoryEventType(rawValue: 0x0563)

    /// The events v2 adds, with the app-local type that decodes each.
    static let v2EventTypes: [(type: IDHistoryEventType, name: String, event: PumpHistoryEvent.Type)] = [
        (.localBolusParametersChanged, "Local Bolus Parameters Changed", LocalBolusParametersChangedHistoryEvent.self),
        (.automaticStopParametersChanged, "Automatic Stop Parameters Changed", AutomaticStopParametersChangedHistoryEvent.self),
        (.acousticSignalSuspensionParametersChanged, "Acoustic Signal Suspension Parameters Changed", AcousticSignalSuspensionParametersChangedHistoryEvent.self),
        (.lifetimeWarningLimitChanged, "Lifetime Warning Limit Changed", LifetimeWarningLimitChangedHistoryEvent.self),
        (.reservoirLevelWarningLimitChanged, "Reservoir Level Warning Limit Changed", ReservoirLevelWarningLimitChangedHistoryEvent.self),
        (.insulinDeliveryStartSoundParametersChanged, "Insulin Delivery Start Sound Parameters Changed", InsulinDeliveryStartSoundParametersChangedHistoryEvent.self),
        (.clientInformationChanged, "ID Client Identification Changed", ClientIdentificationChangedHistoryEvent.self),
    ]
}

enum IDResponseKey: String {
    case amount
    case amountDelivered
    case amountExtended
    case amountFast
    case amountNew
    case amountOld
    case amountProgrammed
    case auxillaryData
    case bolusIDs
    case delayTime
    case deliveryContext
    case duration
    case durationEffective
    case durationProgrammed
    case durationRemaining
    case insulinConcentration
    case limit
    case maxValue
    case numberOfBoluses
    case operationalState
    case rateBasal
    case rateTBR
    case relativeOffset
    case remainingReservoir
    case requestOpcode
    case repeating
    case responseCode
    case responseOpcode
    case recordNumber
    case startTime
    case status
    case stepValue
    case templateNumber
    case templateNumberTBR
    case therapyControlState
}
