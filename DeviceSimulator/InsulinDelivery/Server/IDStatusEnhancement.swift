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
