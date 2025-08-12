//
//  MockMessageQueue.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit

struct MockMessageQueue: MessagingQueue {
    var gattServer: GATTService! = MockGattServer()

    var segmentCounter: UInt8 = 0

    var hasMessagesInQueue: Bool { false }

    func addQueueItem(_ update: UUIDValuePair) { }

    func emptyQueue() { }
}
