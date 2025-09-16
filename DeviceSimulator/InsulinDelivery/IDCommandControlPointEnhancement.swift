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
    
    override func onWrite(_ request: Data?) -> CBATTError.Code {
        guard let request = request else {
            return CBATTError.Code.invalidPdu
        }
        
        var index = 0
        let requestOpcode = IDCommandControlPointOpcode(rawValue: request[request.startIndex.advanced(by: index)...].to(IDCommandControlPointOpcode.RawValue.self))
        index += 2
        
        switch requestOpcode {
        case .getMaxBasalRateAmount:
            var response = Data(IDCommandControlPointOpcode.getMaxBasalRateAmountResponse.rawValue)
            response.append(maxBasalRate.sfloat)
            sendResponse(response)
            return CBATTError.Code.success
        case .setMaxBasalRateAmount:
            let newMax = Data(request[request.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
            maxBasalRate = newMax
            respondWithSuccess(to: .setMaxBasalRateAmount)
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
            let maxAmount = Data(response[response.startIndex.advanced(by: 2)...].to(SFLOAT.self)).sfloatToDouble()
            let completion = completeProcedure(IDCommandControlPointOpcode.getMaxBasalRateAmount)
            return (.success(maxAmount), completion)
        default:
            return super.handleResponse(response)
        }
    }
}
