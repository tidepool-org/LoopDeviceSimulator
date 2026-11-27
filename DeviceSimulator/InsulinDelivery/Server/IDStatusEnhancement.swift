//
//  IDStatusEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-11.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit

/// v2 adds the Reservoir Remaining Amount Accurate flag (bit 1). The mock pump meters its reservoir exactly, so
/// the flag is on by default; a level the tester forces for one report is not the pump's real level, so that one
/// value goes out without it.
class IDStatusCharacteristicEnhancement: IDStatusCharacteristic {
    required init(messageQueue: MessagingQueue) {
        super.init(messageQueue: messageQueue)
        flags.insert(.reservoirRemainingAmountAccurate)
    }

    override func createData() -> Data {
        guard let pump = delegate as? MockInsulinDeliveryPump,
              pump.pendingReservoirLevelOverride != nil,
              flags.contains(.reservoirRemainingAmountAccurate)
        else { return super.createData() }
        flags.remove(.reservoirRemainingAmountAccurate)
        defer { flags.insert(.reservoirRemainingAmountAccurate) }
        return super.createData()
    }
}

extension IDStatusFlag {
    static let reservoirRemainingAmountAccurate  = IDStatusFlag(rawValue: 1 << 1)

    /// Every flag the Status characteristic can carry, in bit order, for the server's Status Flags card.
    static let namedFlags: [(name: String, flag: IDStatusFlag)] = [
        ("Reservoir Attached", .reservoirAttached),
        ("Reservoir Remaining Amount Accurate", .reservoirRemainingAmountAccurate),
    ]

    /// Names both flags; the kit's `description` only knows Reservoir Attached.
    var v2Description: String {
        let names = IDStatusFlag.namedFlags.filter { contains($0.flag) }.map(\.name)
        return "IDStatusFlag(rawValue: \(rawValue)) \(names)"
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
