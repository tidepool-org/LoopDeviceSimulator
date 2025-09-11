//
//  IDStatusEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-11.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit

public class IDStatusCharacteristicEnhancement: IDStatusCharacteristic {
//    override public func createData() -> Data {
//        flags.insert(.reservoirRemainingAmountAccurate)
//        return super.createData()
//    }
}

extension IDStatusFlag {
    static let reservoirRemainingAmountAccurate  = IDStatusFlag(rawValue: 1 << 1)
        
    static var allCases: [IDStatusFlag] {
        return [.reservoirAttached, .reservoirRemainingAmountAccurate]
    }
}
