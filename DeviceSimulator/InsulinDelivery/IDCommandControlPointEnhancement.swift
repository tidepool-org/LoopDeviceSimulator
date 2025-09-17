//
//  IDCommandControlPointEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-16.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import InsulinDeliveryServiceKit
import BluetoothCommonKit

class IDCommandControlPointEnhancement: IDCommandControlPointCharacteristic {
    
    var maxBasalRate = 10.0
    
    var localBolusState: IDStateFlag = .disabled
    var localBolusStepValue = 0.5
    var maxLocalBolusAmount = 20.0
    
    var automaticStopState: IDStateFlag = .disabled
    var automaticStopTimeout: UInt16 = 0
    var counterStartDate = Date()
    var automaticStopCounter: UInt16 {
        get {
            UInt16(abs(counterStartDate.timeIntervalSinceNow)/60)
        }
        set {
            counterStartDate = Date().addingTimeInterval(-TimeInterval(newValue * 60))
        }
    }
    
    var acousticSignalSuspensionState: IDStateFlag = .disabled
    var acousticSignalSuspensionStartTime: TimeInterval = 0
    var acousticSignalSuspensionDuration: TimeInterval = 0
    var acousticSignalSuspensionRepeatStatus: IDRepeatFlag = .once
    
    var lifetimeWarningState: IDStateFlag = .disabled
    var lifeTimeWarningLimitInDays: UInt16 = 0
    
    var reservoirWarningState: IDStateFlag = .disabled
    var reservoirWarningLimit: Double = 0.0
    
    var insulinDeliveryStartSoundState: IDStateFlag = .disabled
    
    override func onWrite(_ request: Data?) -> CBATTError.Code {
        guard let request = request else {
            return CBATTError.Code.invalidPdu
        }
        
        var index = 0
        let requestOpcode = IDCommandControlPointOpcode(rawValue: request[request.startIndex.advanced(by: index)...].to(IDCommandControlPointOpcode.RawValue.self))
        index += 2
        
        switch requestOpcode {
        case .setMaxBasalRateAmount:
            let newMax = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            maxBasalRate = newMax
            respondWithSuccess(to: .setMaxBasalRateAmount)
            return CBATTError.Code.success
        case .getMaxBasalRateAmount:
            var response = Data(IDCommandControlPointOpcode.getMaxBasalRateAmountResponse.rawValue)
            response.append(maxBasalRate.sfloat)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .setLocalBolusParameters:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            index += 1
            guard status == .enabled else {
                respondWithSuccess(to: .setLocalBolusParameters)
                localBolusState = .disabled
                return CBATTError.Code.success
            }
            localBolusState = .enabled
            let stepValue = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            localBolusStepValue = stepValue
            print("stepValue: \(localBolusStepValue)")
            index += 2
            let maxBolusAmount = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            maxLocalBolusAmount = maxBolusAmount
            print("maxBolusAmount: \(maxLocalBolusAmount)")
            respondWithSuccess(to: .setLocalBolusParameters)
            return CBATTError.Code.success
        case .getLocalBolusParameters:
            var response = Data(IDCommandControlPointOpcode.getLocalBolusParametersResponse.rawValue)
            response.append(localBolusState.rawValue)
            guard localBolusState == .enabled else {
                sendResponse(addE2EProtection(response: response))
                return CBATTError.Code.success
            }
            response.append(localBolusStepValue.sfloat)
            response.append(maxLocalBolusAmount.sfloat)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .setAutomaticStopParameters:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            index += 1
            guard status == .enabled else {
                respondWithSuccess(to: .setAutomaticStopParameters)
                automaticStopState = .disabled
                return CBATTError.Code.success
            }
            automaticStopState = .enabled
            let timeout = request[request.startIndex.advanced(by: index)...].to(UInt16.self)
            automaticStopTimeout = timeout
            print("automaticStopTimeout: \(automaticStopTimeout)")
            respondWithSuccess(to: .setAutomaticStopParameters)
            return CBATTError.Code.success
        case .getAutomaticStopParameters:
            var response = Data(IDCommandControlPointOpcode.getAutomaticStopParametersResponse.rawValue)
            response.append(automaticStopState.rawValue)
            guard automaticStopState == .enabled else {
                sendResponse(addE2EProtection(response: response))
                return CBATTError.Code.success
            }
            response.append(automaticStopTimeout)
            response.append(automaticStopCounter)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .resetAutomaticStopTimeout:
            let lastIntereactionInterval = request[request.startIndex.advanced(by: index)...].to(UInt16.self)
            guard lastIntereactionInterval <= automaticStopTimeout else {
                response(to: .resetAutomaticStopTimeout, with: .parameterOutOfRange)
                return CBATTError.Code.success
            }
            
            guard lastIntereactionInterval <= automaticStopCounter else {
                response(to: .resetAutomaticStopTimeout, with: .procedureNotApplicable)
                return CBATTError.Code.success
            }
            
            automaticStopCounter = lastIntereactionInterval
            respondWithSuccess(to: .resetAutomaticStopTimeout)
            return CBATTError.Code.success
        case .setAcousticSignalSuspensionParameters:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            index += 1
            guard status == .enabled else {
                respondWithSuccess(to: .setAcousticSignalSuspensionParameters)
                acousticSignalSuspensionState = .disabled
                return CBATTError.Code.success
            }
            acousticSignalSuspensionState = .enabled
            let startTime = request[request.startIndex.advanced(by: index)...].to(UInt16.self)
            index += 2
            acousticSignalSuspensionStartTime = TimeInterval(startTime*60)
            print("acousticSignalSuspensionStartTime: \(acousticSignalSuspensionStartTime)")
            let duration = request[request.startIndex.advanced(by: index)...].to(UInt16.self)
            index += 2
            acousticSignalSuspensionDuration = TimeInterval(duration*60)
            print("acousticSignalSuspensionDuration: \(acousticSignalSuspensionDuration)")
            let repeatStatus = IDRepeatFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDRepeatFlag.RawValue.self))
            acousticSignalSuspensionRepeatStatus = repeatStatus!
            print("acousticSignalSuspensionRepeatStatus: \(acousticSignalSuspensionRepeatStatus)")
            respondWithSuccess(to: .setAcousticSignalSuspensionParameters)
            return CBATTError.Code.success
        case .getAcousticSignalSuspensionParameters:
            var response = Data(IDCommandControlPointOpcode.getAcousticSignalSuspensionParametersResponse.rawValue)
            response.append(acousticSignalSuspensionState.rawValue)
            guard acousticSignalSuspensionState == .enabled else {
                sendResponse(addE2EProtection(response: response))
                return CBATTError.Code.success
            }
            response.append(UInt16(acousticSignalSuspensionStartTime/60.0))
            response.append(UInt16(acousticSignalSuspensionDuration/60.0))
            response.append(acousticSignalSuspensionRepeatStatus.rawValue)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .setLifetimeWarningLimit:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            index += 1
            guard status == .enabled else {
                respondWithSuccess(to: .setLifetimeWarningLimit)
                lifetimeWarningState = .disabled
                return CBATTError.Code.success
            }
            lifetimeWarningState = .enabled
            let limit = request[request.startIndex.advanced(by: index)...].to(UInt16.self)
            lifeTimeWarningLimitInDays = limit
            print("lifeTimeWarningLimitInDays: \(lifeTimeWarningLimitInDays)")
            respondWithSuccess(to: .setLifetimeWarningLimit)
            return CBATTError.Code.success
        case .getLifetimeWarningLimit:
            var response = Data(IDCommandControlPointOpcode.getLifetimeWarningLimitResponse.rawValue)
            response.append(lifetimeWarningState.rawValue)
            guard lifetimeWarningState == .enabled else {
                sendResponse(addE2EProtection(response: response))
                return CBATTError.Code.success
            }
            response.append(lifeTimeWarningLimitInDays)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .setReservoirLevelWarningLimit:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            index += 1
            guard status == .enabled else {
                reservoirWarningState = .disabled
                respondWithSuccess(to: .setReservoirLevelWarningLimit)
                return CBATTError.Code.success
            }
            reservoirWarningState = .enabled
            let limit = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            reservoirWarningLimit = limit
            print("reservoirWarningLimit: \(reservoirWarningLimit)")
            respondWithSuccess(to: .setReservoirLevelWarningLimit)
            return CBATTError.Code.success
        case .getReservoirLevelWarningLimit:
            var response = Data(IDCommandControlPointOpcode.getReservoirLevelWarningLimitResponse.rawValue)
            response.append(reservoirWarningState.rawValue)
            guard reservoirWarningState == .enabled else {
                sendResponse(addE2EProtection(response: response))
                return CBATTError.Code.success
            }
            response.append(reservoirWarningLimit.sfloat)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        case .setInsulinDeliveryStartSoundParameters:
            let status = IDStateFlag(rawValue: request[request.startIndex.advanced(by: index)...].to(IDStateFlag.RawValue.self))
            print("status: \(String(describing: status))")
            insulinDeliveryStartSoundState = status ?? .disabled
            respondWithSuccess(to: .setInsulinDeliveryStartSoundParameters)
            return CBATTError.Code.success
        case .getInsulinDeliveryStartSoundParameters:
            var response = Data(IDCommandControlPointOpcode.getInsulinDeliveryStartSoundParametersResponse.rawValue)
            response.append(insulinDeliveryStartSoundState.rawValue)
            sendResponse(addE2EProtection(response: response))
            return CBATTError.Code.success
        default:
            return super.onWrite(request)
        }
    }
}

class IDCommandControlPointDataHandlerEnhancement: IDCommandControlPointDataHandler {
    override func handleResponse(_ response: Data) -> (result: DeviceCommResult<Any?>, completion: Any?) {
        guard e2eDelegate?.isE2EProtectionSupported == false || (e2eDelegate?.isE2EProtectionSupported == true && response.isCRCValid) else {
            return (.failure(.invalidCRC), nil)
        }
        
        guard let opcode: IDCommandControlPointOpcode = responseOpcode(response),
              IDCommandControlPointOpcode.responseOpcodes.contains(opcode)
        else {
            return (.failure(.opcodeUnknown(response.hexadecimalString)), nil)
        }
        
        switch opcode {
        case .getMaxBasalRateAmountResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getMaxBasalRateAmount)
            let maxAmount = Data(response[response.startIndex.advanced(by: 2)...].to(SFLOAT.self)).sfloatToDouble()
            return (.success(maxAmount), completion)
        case .getLocalBolusParametersResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getLocalBolusParameters)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            guard status == .enabled else {
                return (.success(status), completion)
            }
            let stepValue = Data(response[response.startIndex.advanced(by: 3)...].to(SFLOAT.self)).sfloatToDouble()
            let maxBolusAmount = Data(response[response.startIndex.advanced(by: 5)...].to(SFLOAT.self)).sfloatToDouble()
            return (.success(["state": status!, "step value": stepValue, "max bolus amount": maxBolusAmount]), completion)
        case .getAutomaticStopParametersResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getAutomaticStopParameters)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            guard status == .enabled else {
                return (.success(status), completion)
            }
            let timeout = response[response.startIndex.advanced(by: 3)...].to(UInt16.self)
            let counter = response[response.startIndex.advanced(by: 5)...].to(UInt16.self)
            return (.success(["state": status!, "timeout": timeout, "counter": counter]), completion)
        case .getAcousticSignalSuspensionParametersResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getAcousticSignalSuspensionParameters)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            guard status == .enabled else {
                return (.success(status), completion)
            }
            let startTime = response[response.startIndex.advanced(by: 3)...].to(UInt16.self)
            let duration = response[response.startIndex.advanced(by: 5)...].to(UInt16.self)
            let repeatStatus = IDRepeatFlag(rawValue: response[response.startIndex.advanced(by: 7)...].to(IDRepeatFlag.RawValue.self))
            return (.success(["state": status!, "startTime": startTime, "duration": duration, "repeatStatus": repeatStatus ?? "not set"]), completion)
        case .getLifetimeWarningLimitResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getLifetimeWarningLimit)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            guard status == .enabled else {
                return (.success(status), completion)
            }
            let limit = response[response.startIndex.advanced(by: 3)...].to(UInt16.self)
            return (.success(["state": status!, "limit": limit]), completion)
        case .getReservoirLevelWarningLimitResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getReservoirLevelWarningLimit)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            guard status == .enabled else {
                return (.success(status), completion)
            }
            let limit = Data(response[response.startIndex.advanced(by: 3)...].to(SFLOAT.self)).sfloatToDouble()
            return (.success(["state": status!, "limit": limit]), completion)
        case .getInsulinDeliveryStartSoundParametersResponse:
            let completion = completeProcedure(IDCommandControlPointOpcode.getInsulinDeliveryStartSoundParameters)
            let status = IDStateFlag(rawValue: response[response.startIndex.advanced(by: 2)...].to(IDStateFlag.RawValue.self))
            return (.success(["state": status!]), completion)
        default:
            return super.handleResponse(response)
        }
    }
}

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
