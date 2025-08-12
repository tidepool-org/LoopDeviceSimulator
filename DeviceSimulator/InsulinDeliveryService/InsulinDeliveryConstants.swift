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

// Service UUID's
struct InsulinDeliveryConstants {
    static let serverName: String = "Tidepool-1-Server"
}

// MARK: - bit flags
extension IDFeatureFlag {
    static let supportedAutomaticStop = IDFeatureFlag(rawValue: 1 << 16)
    static let supportedLocalBolus = IDFeatureFlag(rawValue: 1 << 17)
    static let supportedAcousticSignalSuspension = IDFeatureFlag(rawValue: 1 << 18)
    static let supportedWarningLimitLifetime = IDFeatureFlag(rawValue: 1 << 19)
    static let supportedWarningLimitReservoirLevel = IDFeatureFlag(rawValue: 1 << 20)
    static let supportedAcousticSignalStartInsulinDelivery = IDFeatureFlag(rawValue: 1 << 21)
    static let supportedFeatureExtension = IDFeatureFlag(rawValue: 1 << 31)
    
    static var debugDescription: [IDFeatureFlag:String] = {
        var description = [IDFeatureFlag:String]()
        description[.supportedE2EProtection] = "supportedE2EProtection"
        description[.supportedBasalRate] = "supportedBasalRate"
        description[.supportedTBRAbsolute] = "supportedTBRAbsolute"
        description[.supportedTBRRelative] = "supportedTBRRelative"
        description[.supportedTBRTemplate] = "supportedTBRTemplate"
        description[.supportedBolusFast] = "supportedBolusFast"
        description[.supportedBolusExtended] = "supportedBolusExtended"
        description[.supportedBolusMultiwave] = "supportedBolusMultiwave"
        description[.supportedBolusDelayTime] = "supportedBolusDelayTime"
        description[.supportedBolusTemplate] = "supportedBolusTemplate"
        description[.supportedBolusActivationType] = "supportedBolusActivationType"
        description[.supportedMultipleBond] = "supportedMultipleBond"
        description[.supportedProfileISF] = "supportedProfileISF"
        description[.supportedProfileI2CHO] = "supportedProfileI2CHO"
        description[.supportedProfileTargetGlucoseRange] = "supportedProfileTargetGlucoseRange"
        description[.supportedIOB] = "supportedIOB"
        description[.supportedAutomaticStop] = "supportedAutomaticStop"
        description[.supportedLocalBolus] = "supportedLocalBolus"
        description[.supportedAcousticSignalSuspension] = "supportedAcousticSignalSuspension"
        description[.supportedWarningLimitLifetime] = "supportedWarningLimitLifetime"
        description[.supportedWarningLimitReservoirLevel] = "supportedWarningLimitReservoirLevel"
        description[.supportedAcousticSignalStartInsulinDelivery] = "supportedAcousticSignalStartInsulinDelivery"
        description[.supportedFeatureExtension] = "supportedFeatureExtension"
        return description
    }()
}

extension IDStatusFlag {
    static let reservoirRemainingAmountAccurate  = IDStatusFlag(rawValue: 1 << 1)
    
    static var debugDescriptions: [IDStatusFlag: String] {
        var descriptions = [IDStatusFlag: String]()
        descriptions[.reservoirAttached] = "reservoirAttached"
        descriptions[.reservoirRemainingAmountAccurate] = "reservoirRemainingAmountAccurate"
        return descriptions
    }
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

extension IDCommandControlPointOpcode {
    static public let getMaxBasalRateAmount = IDCommandControlPointOpcode(rawValue: 0x14be)
    static public let getMaxBasalRateAmountResponse = IDCommandControlPointOpcode(rawValue: 0x14d7)
    static public let setMaxBasalRateAmount = IDCommandControlPointOpcode(rawValue: 0x14b1)
    static public let getLocalBolusParameters = IDCommandControlPointOpcode(rawValue: 0x14e4)
    static public let getLocalBolusParametersResponse = IDCommandControlPointOpcode(rawValue: 0x14eb)
    static public let setLocalBolusParameters = IDCommandControlPointOpcode(rawValue: 0x14d8)
    static public let getAutomaticStopParameters = IDCommandControlPointOpcode(rawValue: 0x1718)
    static public let getAutomaticStopParametersResponse = IDCommandControlPointOpcode(rawValue: 0x1724)
    static public let setAutomaticStopParameters = IDCommandControlPointOpcode(rawValue: 0x1717)
    static public let resetAutomaticStopTimeout = IDCommandControlPointOpcode(rawValue: 0x172b)
    static public let getAcousticSignalSuspensionParameters = IDCommandControlPointOpcode(rawValue: 0x174d)
    static public let getAcousticSignalSuspensionParametersResponse = IDCommandControlPointOpcode(rawValue: 0x1771)
    static public let setAcousticSignalSuspensionParameters = IDCommandControlPointOpcode(rawValue: 0x1742)
    static public let getLifetimeWarningLimit = IDCommandControlPointOpcode(rawValue: 0x1781)
    static public let getLifetimeWarningLimitResponse = IDCommandControlPointOpcode(rawValue: 0x178e)
    static public let setLifetimeWarningLimit = IDCommandControlPointOpcode(rawValue: 0x177e)
    static public let getReservoirLevelWarningLimit = IDCommandControlPointOpcode(rawValue: 0x17bd)
    static public let getReservoirLevelWarningLimitResponse = IDCommandControlPointOpcode(rawValue: 0x17d4)
    static public let setReservoirLevelWarningLimit = IDCommandControlPointOpcode(rawValue: 0x17b2)
    static public let getInsulinDeliveryStartSoundParameters = IDCommandControlPointOpcode(rawValue: 0x17e7)
    static public let getInsulinDeliveryStartSoundParametersResponse = IDCommandControlPointOpcode(rawValue: 0x17e8)
    static public let setInsulinDeliveryStartSoundParameters = IDCommandControlPointOpcode(rawValue: 0x17d8)
    
    var requestOpcode: IDCommandControlPointOpcode? {
        switch self {
        case .snoozeAnnunciationResponse: return .snoozeAnnunciation
        case .confirmAnnunciationResponse: return .confirmAnnunciation
        case .readBasalRateTemplateResponse: return .readBasalRateTemplate
        case .writeBasalRateTemplateResponse: return .writeBasalRateTemplate
        case .getTempBasalTemplateResponse: return .getTempBasalTemplate
        case .setTempBasalTemplateResponse: return .setTempBasalTemplate
        case .setBolusResponse: return .setBolus
        case .cancelBolusResponse: return .cancelBolus
        case .getAvailableBolusesResponse: return .getAvailableBoluses
        case .getBolusTemplateResponse: return .getBolusTemplate
        case .setBolusTemplateResponse: return .setBolusTemplate
        case .getTemplateStatusAndDetailsResponse: return .getTemplateStatusAndDetails
        case .resetTemplateStatusResponse: return .resetTemplateStatus
        case .activateProfileTemplatesResponse: return .activateProfileTemplates
        case .getActivatedProfileTemplatesResponse: return .getActivatedProfileTemplates
        case .readISFProfileTemplatesResponse: return .readISFProfileTemplates
        case .writeISFProfileTemplateResponse: return .writeISFProfileTemplate
        case .readI2CHOProfileTemplatesResponse: return .readI2CHOProfileTemplates
        case .writeI2CHOProfileTemplateResponse: return .writeI2CHOProfileTemplate
        case .readTargetGlucoseRangeProfileTemplatesResponse: return .readTargetGlucoseRangeProfileTemplates
        case .writeTargetGlucoseRangeProfileTemplateResponse: return .writeTargetGlucoseRangeProfileTemplate
        case .getMaxBolusAmountResponse: return .getMaxBolusAmount
        case .getMaxBasalRateAmountResponse: return .getMaxBasalRateAmount
        case .getLocalBolusParametersResponse: return .getLocalBolusParameters
        case .getAutomaticStopParametersResponse: return .getAutomaticStopParameters
        case .getAcousticSignalSuspensionParametersResponse: return .getAcousticSignalSuspensionParameters
        case .getLifetimeWarningLimitResponse: return .getLifetimeWarningLimit
        case .getReservoirLevelWarningLimitResponse: return .getReservoirLevelWarningLimit
        case .getInsulinDeliveryStartSoundParametersResponse: return .getInsulinDeliveryStartSoundParameters
        default:
            return nil
        }
    }

    static var responseOpcodes: [IDCommandControlPointOpcode] {
        return [
            .responseCode,
            .snoozeAnnunciationResponse,
            .confirmAnnunciationResponse,
            .readBasalRateTemplateResponse,
            .writeBasalRateTemplateResponse,
            .getTempBasalTemplateResponse,
            .setTempBasalTemplateResponse,
            .setBolusResponse,
            .cancelBolusResponse,
            .getAvailableBolusesResponse,
            .getBolusTemplateResponse,
            .setBolusTemplateResponse,
            .getTemplateStatusAndDetailsResponse,
            .resetTemplateStatusResponse,
            .activateProfileTemplatesResponse,
            .getActivatedProfileTemplatesResponse,
            .readISFProfileTemplatesResponse,
            .writeISFProfileTemplateResponse,
            .readI2CHOProfileTemplatesResponse,
            .writeI2CHOProfileTemplateResponse,
            .readTargetGlucoseRangeProfileTemplatesResponse,
            .writeTargetGlucoseRangeProfileTemplateResponse,
            .getMaxBolusAmountResponse,
            .getMaxBasalRateAmountResponse,
            .getLocalBolusParametersResponse,
            .getAutomaticStopParametersResponse,
            .getAcousticSignalSuspensionParametersResponse,
            .getLifetimeWarningLimitResponse,
            .getReservoirLevelWarningLimitResponse,
            .getInsulinDeliveryStartSoundParametersResponse
        ]
    }
    
    var debugDescription: String {
        switch self {
        case .responseCode: return "responseCode"
        case .setTherapyControlState: return "setTherapyControlState"
        case .setFlightMode: return "setFlightMode"
        case .snoozeAnnunciation: return "snoozeAnnunciation"
        case .snoozeAnnunciationResponse: return "snoozeAnnunciationResponse"
        case .confirmAnnunciation: return "confirmAnnunciation"
        case .confirmAnnunciationResponse: return "confirmAnnunciationResponse"
        case .readBasalRateTemplate: return "readBasalRateTemplate"
        case .readBasalRateTemplateResponse: return "readBasalRateTemplateResponse"
        case .writeBasalRateTemplate: return "writeBasalRateTemplate"
        case .writeBasalRateTemplateResponse: return "writeBasalRateTemplateResponse"
        case .setTempBasalAdjustment: return "setTempBasalAdjustment"
        case .cancelTempBasalAdjustment: return "cancelTempBasalAdjustment"
        case .getTempBasalTemplate: return "getTempBasalTemplate"
        case .getTempBasalTemplateResponse: return "getTempBasalTemplateResponse"
        case .setTempBasalTemplate: return "setTempBasalTemplate"
        case .setTempBasalTemplateResponse: return "setTempBasalTemplateResponse"
        case .setBolus: return "setBolus"
        case .setBolusResponse: return "setBolusResponse"
        case .cancelBolus: return "cancelBolus"
        case .cancelBolusResponse: return "cancelBolusResponse"
        case .getAvailableBoluses: return "getAvailableBoluses"
        case .getAvailableBolusesResponse: return "getAvailableBolusesResponse"
        case .getBolusTemplate: return "getBolusTemplate"
        case .getBolusTemplateResponse: return "getBolusTemplateResponse"
        case .setBolusTemplate: return "setBolusTemplate"
        case .setBolusTemplateResponse: return "setBolusTemplateResponse"
        case .getTemplateStatusAndDetails: return "getTemplateStatusAndDetails"
        case .getTemplateStatusAndDetailsResponse: return "getTemplateStatusAndDetailsResponse"
        case .resetTemplateStatus: return "resetTemplateStatus"
        case .resetTemplateStatusResponse: return "resetTemplateStatusResponse"
        case .activateProfileTemplates: return "activateProfileTemplates"
        case .activateProfileTemplatesResponse: return "activateProfileTemplatesResponse"
        case .getActivatedProfileTemplates: return "getActivatedProfileTemplates"
        case .getActivatedProfileTemplatesResponse: return "getActivatedProfileTemplatesResponse"
        case .startPriming: return "startPriming"
        case .stopPriming: return "stopPriming"
        case .setInitialResevoirFillLevel: return "setInitialResevoirFillLevel"
        case .resetResevoirInsulinOperationTime: return "resetResevoirInsulinOperationTime"
        case .readISFProfileTemplates: return "readISFProfileTemplates"
        case .readISFProfileTemplatesResponse: return "readISFProfileTemplatesResponse"
        case .writeISFProfileTemplate: return "writeISFProfileTemplate"
        case .writeISFProfileTemplateResponse: return "writeISFProfileTemplateResponse"
        case .readI2CHOProfileTemplates: return "readI2CHOProfileTemplates"
        case .readI2CHOProfileTemplatesResponse: return "readI2CHOProfileTemplatesResponse"
        case .writeI2CHOProfileTemplate: return "writeI2CHOProfileTemplate"
        case .writeI2CHOProfileTemplateResponse: return "writeI2CHOProfileTemplateResponse"
        case .readTargetGlucoseRangeProfileTemplates: return "readTargetGlucoseRangeProfileTemplates"
        case .readTargetGlucoseRangeProfileTemplatesResponse: return "readTargetGlucoseRangeProfileTemplatesResponse"
        case .writeTargetGlucoseRangeProfileTemplate: return "writeTargetGlucoseRangeProfileTemplate"
        case .writeTargetGlucoseRangeProfileTemplateResponse: return "writeTargetGlucoseRangeProfileTemplateResponse"
        case .getMaxBolusAmount: return "getMaxBolusAmount"
        case .getMaxBolusAmountResponse: return "getMaxBolusAmountResponse"
        case .setMaxBolusAmount: return "setMaxBolusAmount"
        case .getMaxBasalRateAmount: return "getMaxBasalRateAmount"
        case .getMaxBasalRateAmountResponse: return "getMaxBasalRateAmountResponse"
        case .setMaxBasalRateAmount: return "setMaxBasalRateAmount"
        case .getLocalBolusParameters: return "getLocalBolusParameters"
        case .getLocalBolusParametersResponse: return "getLocalBolusParametersResponse"
        case .setLocalBolusParameters: return "setLocalBolusParameters"
        case .getAutomaticStopParameters: return "getAutomaticStopParameters"
        case .getAutomaticStopParametersResponse: return "getAutomaticStopParametersResponse"
        case .setAutomaticStopParameters: return "setAutomaticStopParameters"
        case .resetAutomaticStopTimeout: return "resetAutomaticStopTimeout"
        case .getAcousticSignalSuspensionParameters: return "getAcousticSignalSuspensionParameters"
        case .getAcousticSignalSuspensionParametersResponse: return "getAcousticSignalSuspensionParametersResponse"
        case .setAcousticSignalSuspensionParameters: return "setAcousticSignalSuspensionParameters"
        case .getLifetimeWarningLimit: return "getLifetimeWarningLimit"
        case .getLifetimeWarningLimitResponse: return "getLifetimeWarningLimitResponse"
        case .setLifetimeWarningLimit: return "setLifetimeWarningLimit"
        case .getReservoirLevelWarningLimit: return "getReservoirLevelWarningLimit"
        case .getReservoirLevelWarningLimitResponse: return "getReservoirLevelWarningLimitResponse"
        case .setReservoirLevelWarningLimit: return "setReservoirLevelWarningLimit"
        case .getInsulinDeliveryStartSoundParameters: return "getInsulinDeliveryStartSoundParameters"
        case .getInsulinDeliveryStartSoundParametersResponse: return "getInsulinDeliveryStartSoundParametersResponse"
        case .setInsulinDeliveryStartSoundParameters: return "setInsulinDeliveryStartSoundParameters"
        default: return "unknown opocode \(self)"
        }
    }
}

enum IDStateFlag: UInt8 {
    case enabled = 0x0f
    case disabled = 0x33
    
    public var description: String {
        switch self {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        }
    }
}

enum IDRepeatFlag: UInt8 {
    case once = 0x0f
    case repeating = 0x33
    
    public var description: String {
        switch self {
        case .once: return "once"
        case .repeating: return "repeating"
        }
    }
}

extension IDHistoryEventType {
    static public let localBolusParametersChanged = IDHistoryEventType(rawValue: 0xc000)
    static public let automaticStopParametersChanged = IDHistoryEventType(rawValue: 0xc003)
    static public let acousticSignalSuspensionParametersChanged = IDHistoryEventType(rawValue: 0xc00c)
    static public let lifetimeWarningLimitChanged = IDHistoryEventType(rawValue: 0xc00f)
    static public let reservoirLevelWarningLimitChanged = IDHistoryEventType(rawValue: 0xc030)
    static public let insulinDeliveryStartSoundParametersChanged = IDHistoryEventType(rawValue: 0xc033)
    static public let clientInformationChanged = IDHistoryEventType(rawValue: 0xc03c)
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
