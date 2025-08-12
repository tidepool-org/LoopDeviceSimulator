//
//  DeliveredBasalRateChangedHistoryEvent.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import BluetoothCommonKit
import InsulinDeliveryServiceKit

extension DeliveredBasalRateChangedHistoryEvent {
    static func createHistoryEventEnhanced(recordNumber: RecordNumber, relativeOffset: TimeInterval) -> DeliveredBasalRateChangedHistoryEvent {
        let flag: DeliveredBasalRateChangedFlag = [.deliveryContentPresent, .amountDeliveredPresent]
        let oldRate = 2
        let newRate = 1
        let deliveryContext = BasalDeliveryContext.aidController
        let deliveredAmount = 0.5
        var eventData = Data(flag.rawValue)
        eventData.append(oldRate.sfloat)
        eventData.append(newRate.sfloat)
        eventData.append(deliveryContext.rawValue)
        eventData.append(deliveredAmount.sfloat)
        return DeliveredBasalRateChangedHistoryEvent(
            recordNumber: recordNumber,
            relativeOffset: relativeOffset,
            eventData: eventData
        )
    }
}
