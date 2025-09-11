//
//  IDStatusEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-11.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

extension IDStatusFlag {
    static let reservoirRemainingAmountAccurate  = IDStatusFlag(rawValue: 1 << 1)
        
    static var allCases: [IDStatusFlag] {
        return [.reservoirAttached, .reservoirRemainingAmountAccurate]
    }
}
