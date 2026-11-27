//
//  IDFeatureEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-11.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit
import BluetoothCommonKit
import os.log

/// v2 widens the Flags field to four octets (the kit writes three); which flags are set is the tester's choice
/// on the Pump Feature card.
public class IDFeatureCharacteristicEnhancement: IDFeatureCharacteristic {
    override public func createData() -> Data {
        if e2eDelegate?.isE2EProtectionSupported ?? false {
            incrementE2ECounter()
        }
        var characteristicValue = Data(e2eCounter)
        characteristicValue.append(insulinConcentration.sfloat)
        var flags = flags
        flags.insert([.supportedAutomaticStop, .supportedLocalBolus, .supportedWarningLimitLifetime, .supportedWarningLimitReservoirLevel])
        characteristicValue.append(flags.rawValue)
        if e2eDelegate?.isE2EProtectionSupported ?? false {
            characteristicValue = characteristicValue.appendingCRCPrefix()
        } else {
            characteristicValue.insert(contentsOf: Data(UInt16(0xffff)), at: 0)
        }

        ConsoleOut.shared.logMessage(message: "\(#function) Insulin Delivery Feature characteristic value: \(characteristicValue.hexadecimalString)")

        return characteristicValue
    }
}

public struct IDFeatureDataHandlerEnhancement {
    static private let log = OSLog(category: "IDFeature")

    /// E2E-CRC (2), E2E-Counter (1), Insulin Concentration (2), Flags (4).
    static let expectedLength = 9

    public static func handleData(_ data: Data) -> DeviceCommResult<
        (insulinConcentration: Double,
        flags: IDFeatureFlag)>
    {
        guard data.count == expectedLength else {
            log.error("feature charactersitic is an unexpected size: (expect %d, actual, %d", expectedLength, data.count)
            return .failure(.invalidFormat)
        }
        
        var index = 3
        let insulinConcentration = Data(data[data.startIndex.advanced(by: index)...].to(SFLOAT.self)).sfloatToDouble()
        index += 2
        
        let flag = IDFeatureFlag(rawValue: data[data.startIndex.advanced(by: index)...].to(UInt32.self))
        index += 4
        
        if flag.contains(.supportedE2EProtection),
           !data.isCRCPrefixValid
        {
            return .failure(.invalidCRC)
        }
        
        log.debug("%{public}@ insulin concentration: %{public}f flags: %{public}@", #function, insulinConcentration, String(describing: flag))
        return .success((insulinConcentration, flag))
    }
}

// MARK: - bit flags
extension IDFeatureFlag {
    static let supportedAutomaticStop = IDFeatureFlag(rawValue: 1 << 16)
    static let supportedLocalBolus = IDFeatureFlag(rawValue: 1 << 17)
    static let supportedAcousticSignalSuspension = IDFeatureFlag(rawValue: 1 << 18)
    static let supportedWarningLimitLifetime = IDFeatureFlag(rawValue: 1 << 19)
    static let supportedWarningLimitReservoirLevel = IDFeatureFlag(rawValue: 1 << 20)
    static let supportedAcousticSignalStartInsulinDelivery = IDFeatureFlag(rawValue: 1 << 21)
    static let supportedFeatureExtension = IDFeatureFlag(rawValue: 1 << 23)
    
    static var debugDescription: [IDFeatureFlag:String] = {
        var description = [IDFeatureFlag:String]()
        description[.supportedE2EProtection] = "supportedE2EProtection"
        description[.supportedBasalRate] = "supportedBasalRate"
        description[.supportedTBRAbsolute] = "supportedTBRAbsolute"
        description[.supportedTBRRelative] = "supportedTBRRelative"
        description[.supportedTBRTemplate] = "supportedTBRTemplate"
        description[.supportedBolusFast] = "supportedBolusFast"
        description[.supportedBolusExtended] = "supportedBolusExtended"
        description[.supportedBolusMultiwave] = "supportedBolusMultiwave"
        description[.supportedBolusDelayTime] = "supportedBolusDelayTime"
        description[.supportedBolusTemplate] = "supportedBolusTemplate"
        description[.supportedBolusActivationType] = "supportedBolusActivationType"
        description[.supportedMultipleBond] = "supportedMultipleBond"
        description[.supportedProfileISF] = "supportedProfileISF"
        description[.supportedProfileI2CHO] = "supportedProfileI2CHO"
        description[.supportedProfileTargetGlucoseRange] = "supportedProfileTargetGlucoseRange"
        description[.supportedIOB] = "supportedIOB"
        description[.supportedAutomaticStop] = "supportedAutomaticStop"
        description[.supportedLocalBolus] = "supportedLocalBolus"
        description[.supportedAcousticSignalSuspension] = "supportedAcousticSignalSuspension"
        description[.supportedWarningLimitLifetime] = "supportedWarningLimitLifetime"
        description[.supportedWarningLimitReservoirLevel] = "supportedWarningLimitReservoirLevel"
        description[.supportedAcousticSignalStartInsulinDelivery] = "supportedAcousticSignalStartInsulinDelivery"
        description[.supportedFeatureExtension] = "supportedFeatureExtension"
        return description
    }()

    /// Names every flag, the v2 ones included; the kit's `description` only knows its own sixteen.
    var v2Description: String {
        let names = IDFeatureFlag.debugDescription
            .filter { contains($0.key) }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value)
        return "IDFeatureFlag(rawValue: \(rawValue), 0x\(String(rawValue, radix: 16))) \(names)"
    }
}
