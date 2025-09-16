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

public class IDFeatureCharacteristicEnhancement: IDFeatureCharacteristic {
    override public func createData() -> Data {
        flags.insert([.supportedAutomaticStop, .supportedWarningLimitLifetime, .supportedWarningLimitReservoirLevel, .supportedAcousticSignalStartInsulinDelivery])
        return super.createData()
    }
}

public struct IDFeatureDataHandlerEnhancement {
    static private let log = OSLog(category: "IDFeature")
    
    public static func handleData(_ data: Data) -> DeviceCommResult<
        (insulinConcentration: Double,
        flags: IDFeatureFlag)>
    {
        guard data.count == 8 else {
            log.error("feature charactersitic is an unexpected size: (expect 8, actual, %d", data.count)
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
    static let supportedFeatureExtension = IDFeatureFlag(rawValue: 1 << 31)
    
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
}
