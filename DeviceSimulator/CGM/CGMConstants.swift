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
