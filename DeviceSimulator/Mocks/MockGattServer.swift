//
//  MockGattServer.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit

struct MockGattServer: GATTService {
    var observers: GATTServiceObservers?
    
    var delegate: GATTServiceDelegate?
    
    let preWriteConstrain: ([CallbackCharacteristic]) -> CBATTError.Code = { _ in return CBATTError.Code.success }

    func preWriteConstrain(_ preWriteConstrain: @escaping ([CallbackCharacteristic]) -> CBATTError.Code) { }

    func addCharacteristic(_ callbackCharacteristic: CallbackCharacteristic) { }

    func createService(_ serviceUUID: CBUUID, primary: Bool, withCharacteristics characteristics: [CallbackCharacteristic]) { }

    func addService() { }

    func update(_ data: Data?, forUUID: CBUUID, onSubscribedCentrals: [CBCentral]?) { }

    func startAdvertising(advertisementDataHandler: @escaping () -> [String: Any]?) { }

    func isE2EProtectionEnabled() -> Bool {
        false
    }

    func enableE2EProtection(_ enable: Bool) { }

    func isCharacteristicSubscribed(_ forUUID: CBUUID) -> Bool? {
        false
    }

    func readyToSend() { }
}
