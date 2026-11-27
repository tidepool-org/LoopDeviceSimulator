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

    /// Whether a bolus was programmed on the pump itself, for the Local Bolus flag in Get Active Bolus Delivery.
    var isLocalBolus: ((BolusID) -> Bool)?

    /// Basal delivered since the current time block or TBR started, for the Basal Amount Delivered field.
    var basalAmountDelivered: (() -> Double)?

    override func onWrite(_ request: Data?) -> CBATTError.Code {
        guard let request = request else {
            return CBATTError.Code.invalidPdu
        }

        var index = 0
        let requestOpcode = IDStatusReaderOpcode(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStatusReaderOpcode.RawValue.self))
        index += 2

        switch requestOpcode {
        case .resetStatus:
            // v2 flags: two octets with the four remaining bits at 0–3; the kit's characteristic keeps the v1 layout.
            let flags = IDStatusChangedFlagEnhancement(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStatusChangedFlagEnhancement.RawValue.self))
            ConsoleOut.shared.logMessage(message: "Opcode resetStatus (opcode: \(String(describing: requestOpcode))), v2 flags: \(flags)")
            statusChangedCharacteristic?.resetFlags(flags.originalFlags)
            sendResponse(createResponseWithSuccess(to: .resetStatus))
            return CBATTError.Code.success
        case .getActiveBolusDelivery:
            let bolusID: BolusID = request[request.startIndex.advanced(by: index)...].to(BolusID.self)
            index += 2
            guard let selectionType = BolusValueSelection(rawValue: request[request.startIndex.advanced(by: index)...].to(BolusValueSelection.RawValue.self)) else {
                sendResponse(createResponse(to: .getActiveBolusDelivery, with: .invalidOperand))
                return CBATTError.Code.success
            }
            ConsoleOut.shared.logMessage(message: "Opcode getActiveBolusDelivery (opcode: \(String(describing: requestOpcode))), bolusID: \(bolusID), selectionType: \(selectionType)")
            sendResponse(flaggingLocalBolus(createResponseToGetActiveBolus(bolusID, selectionType: selectionType), bolusID: bolusID))
            return CBATTError.Code.success
        case .getSelectedStatusInformation:
            ConsoleOut.shared.logMessage(message: "Opcode getSelectedStatusInformation (opcode: \(String(describing: requestOpcode)))")
            let flags = IDSelectedStatusFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDSelectedStatusFlag.RawValue.self))
            // All or nothing: a bit this pump does not answer refuses the whole request.
            guard flags.isSubset(of: .allSupported) else {
                ConsoleOut.shared.logMessage(message: "Selected status flags not supported: \(flags)")
                sendResponse(createResponse(to: .getSelectedStatusInformation, with: .procedureNotApplicable))
                return CBATTError.Code.success
            }
            enhancementDelegate?.requestForSelectedStatus(flags)
            return CBATTError.Code.success
        default:
            return super.onWrite(request)
        }
    }

    /// Sets the Bolus Delivery Source Local Bolus flag (bit 5) on a Get Active Bolus Delivery Response for a
    /// bolus programmed on the pump. The flags octet follows the opcode.
    func flaggingLocalBolus(_ response: Data, bolusID: BolusID) -> Data {
        guard isLocalBolus?(bolusID) == true,
              IDStatusReaderOpcode(rawValue: response[response.startIndex...].to(IDStatusReaderOpcode.RawValue.self)) == .getActiveBolusDeliveryResponse
        else { return response }
        return response.rewritingE2EBody(hasE2E: e2eDelegate?.isE2EProtectionSupported ?? false, hasCounter: true) { body in
            let flagsIndex = body.startIndex.advanced(by: 2)
            body[flagsIndex] |= BolusFlag.deliverySourceLocalBolus.rawValue
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
        
        let amountDelivered = basalAmountDelivered?() ?? 0
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
    static let getSelectedStatusInformation = IDStatusReaderOpcode(rawValue: 0x0505)
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
    static public let allSupported = IDSelectedStatusFlag([.statusChangedIndication, .statusIndication, .annunciationStatusIndication, .getActiveBasalRateDelivery, .getActiveBolusIDs, .getActiveBolusProgrammed, .getActiveBolusDelivered, .getActiveBolusRemaining, .getAvailableBoluses, .getTotalDailyInsulinStatus, .getDeliveredInsulin])

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
