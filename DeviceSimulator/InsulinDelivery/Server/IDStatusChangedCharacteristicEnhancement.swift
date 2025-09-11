//
//  IDStatusChangedCharacteristicEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-11.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import CoreBluetooth
import InsulinDeliveryServiceKit
import BluetoothCommonKit
import os.log

//MARK: - Support Server Implementation
public class IDStatusChangedCharacteristicEnhancement: IDStatusChangedCharacteristic {
    public var flagsEnhancement: IDStatusChangedFlagEnhancement = [.activeBasalRateStatusChanged, .totalDailyInsulinStatusChanged]
    
    public override func createData() -> Data {
        var characteristicValue = Data(flagsEnhancement.rawValue)
        if e2eDelegate?.isE2EProtectionSupported ?? false {
            incrementE2ECounter()
            characteristicValue = appendingE2EProtection(characteristicValue)
        }

        ConsoleOut.shared.logMessage(message: "\(#function) ID status changed characteristic value: \(characteristicValue.hexadecimalString)")

        return characteristicValue
    }
    
    public override func triggerIndication(for flags: IDStatusChangedFlag) {
        let enhancedFlags = flags.enhancedFlags
        self.flagsEnhancement.insert(enhancedFlags)
        
        if messageQueue.gattServer.isCharacteristicSubscribed(InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID) == true {
            let valuepair = UUIDValuePair(
                uuid: InsulinDeliveryCharacteristicUUID.statusChanged.cbUUID,
                value: createData()
            )
            ConsoleOut.shared.logMessage(message: "\(#function): \(valuepair.description)")
            messageQueue.addQueueItem(valuepair)
        } else {
            ConsoleOut.shared.logMessage(message: "\(#function): ID status changed characteristic is not configured for indications")
        }
    }
    
    public override func resetFlags(_ flags: IDStatusChangedFlag) {
        let enhancedFlags = flags.enhancedFlags
        self.flags.remove(flags)
        self.flagsEnhancement.remove(enhancedFlags)
        triggerIndication(for: flags)
    }
}

extension IDStatusChangedFlag {
    var enhancedFlags: IDStatusChangedFlagEnhancement {
        var enhancedFlags: IDStatusChangedFlagEnhancement = []
        if self.contains(.totalDailyInsulinStatusChanged) { enhancedFlags.insert(.totalDailyInsulinStatusChanged) }
        if self.contains(.activeBasalRateStatusChanged) { enhancedFlags.insert(.activeBasalRateStatusChanged) }
        if self.contains(.activeBolusStatusChanged) { enhancedFlags.insert(.activeBolusStatusChanged) }
        if self.contains(.historyEventRecordedChanged) { enhancedFlags.insert(.historyEventRecordedChanged) }
        return enhancedFlags
    }
}

//MARK: - Support Client Implementation
public struct IDStatusChangedDataHandlerEnhancement {
    static private let log = OSLog(category: "IDStatusChanged")
    
    public static func handleData(_ data: Data, e2eProtectionSupported: Bool) -> DeviceCommResult<IDStatusChangedFlagEnhancement> {
        guard data.count == (e2eProtectionSupported ? 5 : 2) else {
            log.error("status changed charactersitic is an unexpected size: (expect 5, actual, %d", data.count)
            return .failure(.invalidFormat)
        }

        guard !e2eProtectionSupported || data.isCRCValid else {
            log.error("status changed characteristic CRC is invalid")
            return .failure(.invalidCRC)
        }

        let flags = IDStatusChangedFlagEnhancement(rawValue: data[data.startIndex.advanced(by: 0)...].to(UInt16.self))
        log.debug("%{public}@ %{public}@", #function, String(describing: flags))

        return .success(flags)
    }
}

//MARK: - Option sets
public struct IDStatusChangedFlagEnhancement: OptionSet, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static public let totalDailyInsulinStatusChanged  = IDStatusChangedFlagEnhancement(rawValue: 1 << 0)
    static public let activeBasalRateStatusChanged  = IDStatusChangedFlagEnhancement(rawValue: 1 << 1)
    static public let activeBolusStatusChanged  = IDStatusChangedFlagEnhancement(rawValue: 1 << 2)
    static public let historyEventRecordedChanged  = IDStatusChangedFlagEnhancement(rawValue: 1 << 3)
    static public let allZeros = IDStatusChangedFlagEnhancement([])
    static public let allFlags = IDStatusChangedFlagEnhancement([.totalDailyInsulinStatusChanged, .activeBasalRateStatusChanged, .activeBolusStatusChanged, .historyEventRecordedChanged])
    static public let allCases: [IDStatusChangedFlagEnhancement] = [.totalDailyInsulinStatusChanged, .activeBasalRateStatusChanged, .activeBolusStatusChanged, .historyEventRecordedChanged]

    static let debugDescriptions: [IDStatusChangedFlagEnhancement: String] = {
        var descriptions = [IDStatusChangedFlagEnhancement: String]()
        descriptions[.totalDailyInsulinStatusChanged] = "totalDailyInsulin"
        descriptions[.activeBasalRateStatusChanged] = "activeBasalRate"
        descriptions[.activeBolusStatusChanged] = "activeBolus"
        descriptions[.historyEventRecordedChanged] = "historyEvent"
        return descriptions
    }()

    public var description: String {
        var result = [String]()
        for (key, value) in IDStatusChangedFlagEnhancement.debugDescriptions {
            guard self.contains(key) else {
                continue
            }
            result.append(value)
        }
        return "\(result)"
    }
    
    var originalFlags: IDStatusChangedFlag {
        var originalFlags: IDStatusChangedFlag = []
        if self.contains(.totalDailyInsulinStatusChanged) { originalFlags.insert(.totalDailyInsulinStatusChanged) }
        if self.contains(.activeBasalRateStatusChanged) { originalFlags.insert(.activeBasalRateStatusChanged) }
        if self.contains(.activeBolusStatusChanged) { originalFlags.insert(.activeBolusStatusChanged) }
        if self.contains(.historyEventRecordedChanged) { originalFlags.insert(.historyEventRecordedChanged) }
        return originalFlags
    }
}
