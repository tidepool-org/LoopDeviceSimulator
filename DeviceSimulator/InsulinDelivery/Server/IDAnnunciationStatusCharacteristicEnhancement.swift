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

// A read returns the pump's current annunciation; the server's Annunciations card raises the v2 types.
class IDAnnunciationStatusCharacteristicEnhancement: IDAnnunciationStatusCharacteristic {
    // Bolus Canceled and the TBR types carry the AuxInfo fields v2 makes mandatory; the amounts are stand-ins.
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
        if flags.contains(.presentAnnunciation), let annunciation {
            // The annunciation keeps the ID and status it was raised with; only the AuxInfo is filled in here.
            annunciationData.append(annunciation.identifier)
            annunciationData.append(annunciation.type.rawValue)
            annunciationData.append(annunciation.status.rawValue)
            annunciationData.append(auxData)
        }
        return annunciationData
    }
}

// MARK: - Client: AuxInfo decoding

/// The AuxInfo fields v2 makes mandatory for Bolus Canceled (AuxInfo1–4) and TBR Over / TBR Canceled (AuxInfo1–5).
enum AnnunciationAuxInfo {
    /// A readable breakdown of `auxiliaryData` for the three types with a fixed layout; nil for any other type
    /// or a payload of the wrong size.
    static func describe(type: AnnunciationType, auxiliaryData: Data) -> String? {
        let data = Data(auxiliaryData)   // rebase indices at 0
        switch type {
        case .bolusCanceled:
            guard data.count == 8 else { return nil }
            let bolusID = data[0...].to(UInt16.self)
            let bolusType = BolusType(rawValue: data[2]).map { String(describing: $0) } ?? "0x\(String(data[2], radix: 16))"
            let programmed = Data(data[4...].to(SFLOAT.self)).sfloatToDouble()
            let delivered = Data(data[6...].to(SFLOAT.self)).sfloatToDouble()
            return "bolusID: \(bolusID), bolusType: \(bolusType), programmed: \(programmed) U, delivered: \(delivered) U"
        case .tempBasalOver, .tempBasalCanceled:
            guard data.count == 10 else { return nil }
            let tbrType = TempBasalType(rawValue: data[0]).map { String(describing: $0) } ?? "0x\(String(data[0], radix: 16))"
            let adjustment = Data(data[2...].to(SFLOAT.self)).sfloatToDouble()
            let unit = TempBasalType(rawValue: data[0]) == .relative ? "" : " U/h"
            let durationProgrammed = data[4...].to(UInt16.self)
            let durationEffective = data[6...].to(UInt16.self)
            let delivered = Data(data[8...].to(SFLOAT.self)).sfloatToDouble()
            return "tbrType: \(tbrType), programmedAdjustment: \(adjustment)\(unit), durationProgrammed: \(durationProgrammed) min, durationEffective: \(durationEffective) min, delivered: \(delivered) U"
        default:
            return nil
        }
    }
}

extension AnnunciationType {
    static let automaticStop = AnnunciationType(rawValue: 0x036a)
//    static let batteryAttention = AnnunciationType(rawValue: 0xf096)
//    static let batteryError = AnnunciationType(rawValue: 0xf000)
//    static let pumpNotConfigured = AnnunciationType(rawValue: 0xf033)
//    static let endOfLifetime = AnnunciationType(rawValue: 0xf066)
//    static let endOfPumpLifetime = AnnunciationType(rawValue: 0xf03c)
//    static let endOfReservoirTime = AnnunciationType(rawValue: 0xf05a)
    static let lifetimeWarning = AnnunciationType(rawValue: 0x0395)
//    static let lowDeliveryRate = AnnunciationType(rawValue: 0xf055)
    static let reservoirLevelWarning = AnnunciationType(rawValue: 0x039a)
//    static let stopWarning = AnnunciationType(rawValue: 0xf069)

    /// The kit names its own types; these are the v2 additions, for the server's picker and the client's log.
    var v2Name: String? {
        switch self {
        case .automaticStop: return "automaticStop"
        case .lifetimeWarning: return "lifetimeWarning"
        case .reservoirLevelWarning: return "reservoirLevelWarning"
        default: return nil
        }
    }

    var displayName: String { v2Name ?? description }

    public static var allAnnunciations: [AnnunciationType] {
        [.airPressureOutOfRange,
         .batteryEmpty,
         .batteryFull,
         .batteryLow,
         .batteryMedium,
         .bolusCanceled,
         .dateTimeIssue,
         .infusionSetDetached,
         .infusionSetIncomplete,
         .maxDelivery,
         .mechanicalIssue,
         .occlusionDetected,
         .powerSourceInsufficient,
         .primingIssue,
         .reservoirEmpty,
         .reservoirLow,
         .reservoirIssue,
         .systemIssue,
         .temperatureOutOfRange,
         .tempBasalCanceled,
         .tempBasalOver,
         .automaticStop,
//         .batteryAttention,
//         .batteryError,
//         .pumpNotConfigured,
//         .endOfLifetime,
//         .endOfPumpLifetime,
//         .endOfReservoirTime,
         .lifetimeWarning,
//         .lowDeliveryRate,
         .reservoirLevelWarning]
//         .stopWarning]
    }
}
