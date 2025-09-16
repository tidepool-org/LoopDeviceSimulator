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
    var localBolusEnabled: IDStateFlag = .disabled
    var localBolusStepValue = 0.5
    var maxLocalBolusAmount = 20.0
    
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
                localBolusEnabled = .disabled
                return CBATTError.Code.success
            }
            localBolusEnabled = .enabled
            let stepValue = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            localBolusStepValue = stepValue
            print("stepValue: \(localBolusStepValue)")
            index += 2
            let maxBolusAmount = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            maxLocalBolusAmount = maxBolusAmount
            print("maxBolusAmount: \(maxLocalBolusAmount)")
            return CBATTError.Code.success
        case .getLocalBolusParameters:
            var response = Data(IDCommandControlPointOpcode.getLocalBolusParametersResponse.rawValue)
            response.append(Data(localBolusEnabled.rawValue))
            response.append(localBolusStepValue.sfloat)
            response.append(maxLocalBolusAmount.sfloat)
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
        default:
            return super.handleResponse(response)
        }
    }
}
