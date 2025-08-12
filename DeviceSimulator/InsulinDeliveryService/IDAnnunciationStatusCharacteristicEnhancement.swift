//
//  IDAnnunciationStatusCharacteristicEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit

class IDAnnunciationStatusCharacteristicEnhancement: IDAnnunciationStatusCharacteristic {
    override func onRead() -> (CBATTError.Code, Data) {
        ConsoleOut.shared.logMessage(message: "\(#function): reading annunciation status characteristic")
        let type: AnnunciationType = e2eCounter%6 == 0 ? .automaticStop : e2eCounter%3 == 1 ? .lifetimeWarning : e2eCounter%3 == 2 ? .reservoirLevelWarning : .undetermined
        if type == .undetermined {
            return super.onRead()
        } else {
            let annunciation = generateAnnunciation(for: type)
            return (CBATTError.Code.success, self.createData(for: annunciation))
        }
    }
    
    override func annunciationData(for annunciation: Annunciation? = nil) -> Data {
        var annunciationData: Data
        var auxData: Data = Data()
        let flags: AnnunciationStatusFlag
        switch annunciation?.type {
        case .bolusCanceled:
            flags = [.presentAnnunciation, .presentAuxInfo1, .presentAuxInfo2, .presentAuxInfo3, .presentAuxInfo4]
            let bolusID: UInt16 = 1
            let bolusType: BolusType = .fast
            let padding: UInt8 = 0
            let amountProgrammed: Double = 4.0
            let amountDelivered: Double = 2.0
            
            auxData.append(bolusID)
            auxData.append(bolusType.rawValue)
            auxData.append(padding)
            auxData.append(amountProgrammed.sfloat)
            auxData.append(amountDelivered.sfloat)
        case .tempBasalCanceled, .tempBasalOver:
            flags = [.presentAnnunciation, .presentAuxInfo1, .presentAuxInfo2, .presentAuxInfo3, .presentAuxInfo4, .presentAuxInfo5]
            annunciationID += 1
            let tbrType: TempBasalType = .absolute
            let padding: UInt8 = 0
            let amountProgrammed: Double = 2.0
            let durationProgrammed: UInt16 = 60
            let amountDelivered: Double = annunciation?.type == .tempBasalOver ? amountProgrammed : 1.0
            let durationDelivered: UInt16 = annunciation?.type == .tempBasalOver ? durationProgrammed : 30
            
            auxData.append(tbrType.rawValue)
            auxData.append(padding)
            auxData.append(amountProgrammed.sfloat)
            auxData.append(durationProgrammed)
            auxData.append(durationDelivered)
            auxData.append(amountDelivered.sfloat)
        case .none:
            flags = .allZeros
        case .some(_):
            return super.annunciationData(for: annunciation)
        }
                
        annunciationData = Data(flags.rawValue)
        if flags.contains(.presentAnnunciation) {
            annunciationID += 1
            annunciationData.append(annunciationID)
            if let type = annunciation?.type {
                annunciationData.append(type.rawValue)
            }
            annunciationData.append(AnnunciationStatus.pending.rawValue)
            annunciationData.append(auxData)
        }
        return annunciationData
    }
}

extension AnnunciationType {
    static let automaticStop = AnnunciationType(rawValue: 0x0369)
    static let batteryAttention = AnnunciationType(rawValue: 0xf096)
    static let batteryError = AnnunciationType(rawValue: 0xf000)
    static let pumpNotConfigured = AnnunciationType(rawValue: 0xf033)
    static let endOfLifetime = AnnunciationType(rawValue: 0xf066)
    static let endOfPumpLifetime = AnnunciationType(rawValue: 0xf03c)
    static let endOfReservoirTime = AnnunciationType(rawValue: 0xf05a)
    static let lifetimeWarning = AnnunciationType(rawValue: 0x036a)
    static let lowDeliveryRate = AnnunciationType(rawValue: 0xf055)
    static let reservoirLevelWarning = AnnunciationType(rawValue: 0x036c)
    static let stopWarning = AnnunciationType(rawValue: 0xf069)
}
