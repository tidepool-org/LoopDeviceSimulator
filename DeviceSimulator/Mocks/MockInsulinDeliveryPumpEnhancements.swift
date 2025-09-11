//
//  MockInsulinDeliveryPumpEnhancements.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-10.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import InsulinDeliveryServiceKit
import BluetoothCommonKit

class MockInsulinDeliveryPumpEnhancement: MockInsulinDeliveryPump {
    public override init(gattServer: GATTService,
                         messageQueue: MessagingQueue,
                         status: MockInsulinDeliveryPumpStatus? = nil)
    {
        super.init(gattServer: gattServer, messageQueue: messageQueue, status: status)
        
        (statusReaderControlPoint as? IDStatusReaderControlPointEnhancement)?.enhancementDelegate = self
    }
    
    override class func createWritableCharacteristic<T: WritableCharacteristic>(of type: T.Type, messageQueue: any MessagingQueue) -> T {
        if type == IDStatusReaderControlPointCharacteristic.self {
            return IDStatusReaderControlPointEnhancement(messageQueue: messageQueue) as! T
        } else {
            return T(messageQueue: messageQueue)
        }
    }
    
    override class func createReadableCharacteristic<T: ReadableCharacteristic>(of type: T.Type, messageQueue: any MessagingQueue) -> T {
        if type == IDStatusChangedCharacteristic.self {
            return IDStatusChangedCharacteristicEnhancement(messageQueue: messageQueue) as! T
        } else if type == IDFeatureCharacteristic.self {
            return IDFeatureCharacteristicEnhancement(messageQueue: messageQueue) as! T
        } else if type == IDAnnunciationStatusCharacteristic.self {
            return IDAnnunciationStatusCharacteristicEnhancement(messageQueue: messageQueue) as! T
        } else {
            return T(messageQueue: messageQueue)
        }
    }
}

extension MockInsulinDeliveryPumpEnhancement: IDStatusReaderControlPointEnhancementDelegate {
    func requestForSelectedStatus(_ flags: IDSelectedStatusFlag) {
        if flags.contains(.statusIndication) {
            statusCharacteristic.triggerIndication()
        }

        if flags.contains(.statusChangedIndication) {
            statusChangedCharacteristic.triggerIndication(for: [])
        }
                
        if flags.contains(.annunciationStatusIndication) {
            annunciationStatusCharacteristic.triggerAnnunciation(for: annunciationStatusCharacteristic.currentAnnunciation)
        }
        
        if flags.contains(.getActiveBasalRateDelivery),
           let statusReaderControlPoint = statusReaderControlPoint as? IDStatusReaderControlPointEnhancement
        {
            let response = statusReaderControlPoint.createResponseToGetActiveBasalRateDelivery()
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getActiveBolusIDs) {
            let response = statusReaderControlPoint.createResponseToGetActiveBolusIDs()
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getActiveBolusProgrammed) {
            let response = statusReaderControlPoint.createResponseToGetActiveBolus(selectionType: .programmed)
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getActiveBolusDelivered) {
            let response = statusReaderControlPoint.createResponseToGetActiveBolus(selectionType: .delivered)
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getActiveBolusRemaining) {
            let response = statusReaderControlPoint.createResponseToGetActiveBolus(selectionType: .remaining)
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getAvailableBoluses) {
            let response = commandControlPoint.createResponseToGetAvailableBoluses()
            commandControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getTotalDailyInsulinStatus) {
            let response = statusReaderControlPoint.createResponseToGetTotalDailyInsulin()
            statusReaderControlPoint.sendResponse(response)
        }
        
        if flags.contains(.getDeliveredInsulin) {
            let response = statusReaderControlPoint.createResponseToGetDeliveredInsulin()
            statusReaderControlPoint.sendResponse(response)
        }
        
        (statusReaderControlPoint as?  IDStatusReaderControlPointEnhancement)?.respondToSelectedStatusSuccess()
    }
}
