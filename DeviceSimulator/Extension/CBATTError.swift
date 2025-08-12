//
//  CBATTError.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import CoreBluetooth

extension CBATTError.Code {
    static var imporperlyConfigured: CBATTError.Code {
        CBATTError.Code(rawValue: 0xfd)!
    }

    static var procedureAlreadyInProgress: CBATTError.Code {
        CBATTError.Code(rawValue: 0xfe)!
    }

    static var outOfRange: CBATTError.Code {
        CBATTError.Code(rawValue: 0xff)!
    }

    static var commandNotSupported: CBATTError.Code {
        CBATTError.Code(rawValue: 0x81)!
    }
    
    static var incorrectTimeFormat: CBATTError.Code {
        CBATTError.Code(rawValue: 0x81)!
    }
}
