//
//  CGMConstants.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-01.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation
import ContinuousGlucoseMonitorServiceKit

struct CGMConstants {
    static let serverName: String = MockCGMSensor.defaultAdvertisedName
    /// Out-of-band confirmation number the collector uses for the ACS key exchange; matches the mock
    /// sensor's default so the two-device test needs no entry.
    static let oobRandomNumber = "42"
    /// BluetoothCommonKit zero-pads the OOB number to 32 octets with a `1...(32 - count)` range, which
    /// traps when nothing is left to pad, so 31 UTF-8 bytes is the most the key exchange can take.
    static let maxSensorKeyBytes = 31
}

/// CGM Communication Interval values offered on both sides (CGMS §3.7.2.1). The operand is whole minutes,
/// so "5 s" is not expressible; 0xFF asks for the fastest the sensor supports, which the simulator treats as
/// every measurement (5 s when it runs at 5 s). The raw values are the wire bytes.
enum CommunicationIntervalOption: UInt8, CaseIterable, Hashable, CustomStringConvertible {
    case off = 0x00
    case fastest = 0xFF
    case oneMinute = 1
    case fiveMinutes = 5

    var description: String {
        switch self {
        case .off: return "Off"
        case .fastest: return "Fastest (5 s)"
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        }
    }
}
