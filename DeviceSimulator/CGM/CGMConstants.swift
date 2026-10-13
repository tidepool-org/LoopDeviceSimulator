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
}
