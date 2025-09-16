//
//  IDStatusReaderControlPointEnhancementDelegate.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import InsulinDeliveryServiceKit
import BluetoothCommonKit

public protocol IDStatusReaderControlPointEnhancementDelegate: AnyObject {
    func requestForSelectedStatus(_ flags: IDSelectedStatusFlag)
}

class IDStatusReaderControlPointEnhancement: IDStatusReaderControlPointCharacteristic {
    weak var enhancementDelegate: IDStatusReaderControlPointEnhancementDelegate?
    
    override func onWrite(_ request: Data?) -> CBATTError.Code {
        guard let request = request else {
            return CBATTError.Code.invalidPdu
        }

        var index = 0
        let requestOpcode = IDStatusReaderOpcode(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStatusReaderOpcode.RawValue.self))
        index += 2
        
        switch requestOpcode {
        case .getSelectedStatusInformation:
            ConsoleOut.shared.logMessage(message: "Opcode getSelectedStatusInformation (opcode: \(String(describing: requestOpcode)))")
            let flags = IDSelectedStatusFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDSelectedStatusFlag.RawValue.self))
            enhancementDelegate?.requestForSelectedStatus(flags)
            return CBATTError.Code.success
        default:
            return super.onWrite(request)
        }
    }
    
    override func createResponseToGetActiveBasalRateDelivery(profileNumber: UInt8,
                                                             rate: Double,
                                                             tempBasalType: TempBasalType?,
                                                             tempBasalRate: Double?,
                                                             tempBasalDurationProgrammed: TimeInterval?,
                                                             tempBasalDurationRemaining: TimeInterval?,
                                                             tempBasalTemplateNumber: UInt8?,
                                                             basalDeliveryContext: BasalDeliveryContext?) -> Data
    {
        let opcode = IDStatusReaderOpcode.getActiveBasalRateDeliveryResponse
        var response = Data(opcode.rawValue)
        response.append(profileNumber)
        response.append(rate.sfloat)
        
        var flags: ActiveBasalRateFlag = .allZeros
        if let tempBasalType,
           let tempBasalRate,
           let tempBasalDurationProgrammed,
           let tempBasalDurationRemaining
        {
            flags.insert(.tbrPresent)
            response.append(tempBasalType.rawValue)
            response.append(tempBasalRate.sfloat)
            response.append(UInt16(tempBasalDurationProgrammed.minutes))
            response.append(UInt16(tempBasalDurationRemaining.minutes))
        }
        
        if let tempBasalTemplateNumber {
            flags.insert(.tbrTemplateNumberPresent)
            response.append(tempBasalTemplateNumber)
        }
        
        if let basalDeliveryContext {
            flags.insert(.deliveryContextPresent)
            response.append(basalDeliveryContext.rawValue)
        }
        
        let amountDelivered: Double = 1.0
        flags.insert(.amountDeliveredPresent)
        response.append(amountDelivered.sfloat)
        
        response.insert(flags.rawValue, at: 2)
        return addE2EProtection(response: response)
    }
    
    func respondToSelectedStatusSuccess() {
        respondWithSuccess(to: .getSelectedStatusInformation)
    }
}

public extension IDStatusReaderOpcode {
    static let getSelectedStatusInformation = IDStatusReaderOpcode(rawValue: 0x0c03)
}

public extension ActiveBasalRateFlag {
    static let amountDeliveredPresent = ActiveBasalRateFlag(rawValue: 1 << 3)
}

public struct IDSelectedStatusFlag: OptionSet, Hashable, CustomStringConvertible {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static public let statusChangedIndication = IDSelectedStatusFlag(rawValue: 1 << 0)
    static public let statusIndication = IDSelectedStatusFlag(rawValue: 1 << 1)
    static public let annunciationStatusIndication = IDSelectedStatusFlag(rawValue: 1 << 2)
    static public let getActiveBasalRateDelivery = IDSelectedStatusFlag(rawValue: 1 << 3)
    static public let getActiveBolusIDs = IDSelectedStatusFlag(rawValue: 1 << 4)
    static public let getActiveBolusProgrammed = IDSelectedStatusFlag(rawValue: 1 << 5)
    static public let getActiveBolusDelivered = IDSelectedStatusFlag(rawValue: 1 << 6)
    static public let getActiveBolusRemaining = IDSelectedStatusFlag(rawValue: 1 << 7)
    static public let getAvailableBoluses = IDSelectedStatusFlag(rawValue: 1 << 8)
    static public let getTotalDailyInsulinStatus = IDSelectedStatusFlag(rawValue: 1 << 9)
    static public let getDeliveredInsulin = IDSelectedStatusFlag(rawValue: 1 << 10)
    static public let allZeros = IDSelectedStatusFlag([])

    static let debugDescription: [IDSelectedStatusFlag:String] = {
        var description = [IDSelectedStatusFlag:String]()
        description[.statusChangedIndication] = "statusChangedIndication"
        description[.statusIndication] = "statusIndication"
        description[.annunciationStatusIndication] = "annunciationStatusIndication"
        description[.getActiveBasalRateDelivery] = "getActiveBasalRateDelivery"
        description[.getActiveBolusIDs] = "getActiveBolusIDs"
        description[.getActiveBolusProgrammed] = "getActiveBolusProgrammed"
        description[.getActiveBolusDelivered] = "getActiveBolusDelivered"
        description[.getActiveBolusRemaining] = "getActiveBolusRemaining"
        description[.getAvailableBoluses] = "getAvailableBoluses"
        description[.getTotalDailyInsulinStatus] = "getTotalDailyInsulinStatus"
        description[.getDeliveredInsulin] = "getDeliveredInsulin"
        return description
    }()

    public var description: String {
        var result = [String]()
        for key in IDSelectedStatusFlag.debugDescription.keys {
            guard self.contains(key),
                  let description = IDSelectedStatusFlag.debugDescription[key]
            else { continue }
            result.append(description)
        }
        return "IDSelectedStatusFlag(rawValue: \(self.rawValue)) \(result)"
    }
}
