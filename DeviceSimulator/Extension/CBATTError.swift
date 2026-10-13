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

    /// CGMS/E2E application error names (0x80–0xFF); Core Bluetooth only describes the core ATT codes.
    var cgmName: String? {
        switch rawValue {
        case 0x80: "Missing CRC"
        case 0x81: "Invalid CRC"
        case 0xfd: "Client Characteristic Configuration Descriptor Improperly Configured"
        case 0xfe: "Procedure Already In Progress"
        case 0xff: "Out of Range"
        default: nil
        }
    }
}

extension Error {
    /// ATT errors as "ATT error 0xFE Procedure Already In Progress"; other errors keep their own text.
    var cgmATTDescription: String {
        let nsError = self as NSError
        guard nsError.domain == CBATTErrorDomain else { return localizedDescription }
        let name = CBATTError.Code(rawValue: nsError.code)?.cgmName ?? localizedDescription
        return "ATT error 0x\(String(format: "%02X", nsError.code)) \(name)"
    }
}
