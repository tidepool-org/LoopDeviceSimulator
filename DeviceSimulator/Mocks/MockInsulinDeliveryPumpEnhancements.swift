//
//  MockInsulinDeliveryPumpEnhancements.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-10.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit
import BluetoothCommonKit

class MockInsulinDeliveryPumpEnhancement: MockInsulinDeliveryPump {
    /// Boluses programmed on the pump itself, for the Local Bolus flag in Get Active Bolus Delivery.
    private var localBolusIDs: Set<BolusID> = []

    public override init(gattServer: GATTService,
                         messageQueue: MessagingQueue,
                         status: MockInsulinDeliveryPumpStatus? = nil)
    {
        super.init(gattServer: gattServer, messageQueue: messageQueue, status: status)

        if let statusReader = statusReaderControlPoint as? IDStatusReaderControlPointEnhancement {
            statusReader.enhancementDelegate = self
            statusReader.isLocalBolus = { [weak self] bolusID in self?.localBolusIDs.contains(bolusID) ?? false }
            statusReader.basalAmountDelivered = { [weak self] in self?.basalAmountDeliveredInCurrentBlock ?? 0 }
        }
        if let commandControlPoint = commandControlPoint as? IDCommandControlPointEnhancement {
            commandControlPoint.recordHistoryEvent = { [weak self] type, eventData in
                self?.recordV2HistoryEvent(type: type, eventData: eventData)
            }
            commandControlPoint.automaticStopParametersDidChange = { [weak self] in self?.checkAutomaticStop() }
        }
        // The counter is wall-clock time, so the pump looks at it on a cadence rather than on an event.
        automaticStopTimer = Timer.scheduledTimer(withTimeInterval: Self.automaticStopPollInterval, repeats: true) { [weak self] _ in
            self?.checkAutomaticStop()
        }
    }

    deinit {
        automaticStopTimer?.invalidate()
    }

    // MARK: Automatic Stop

    static let automaticStopPollInterval: TimeInterval = 10

    private var automaticStopTimer: Timer?

    /// Logged once per time the counter reaches the timeout while pump behaviour is off, not on every poll.
    private var automaticStopIgnoredReported = false

    /// With pump behaviour on, a counter at the timeout stops therapy and raises the Automatic Stop annunciation,
    /// once per timeout. With it off the pump keeps delivering and only says so, so a tester can watch the
    /// counter pass without the pump reacting.
    func checkAutomaticStop() {
        guard let commandControlPoint = commandControlPoint as? IDCommandControlPointEnhancement else { return }
        guard commandControlPoint.isAutomaticStopDue, !commandControlPoint.hasAutomaticStopFired else {
            automaticStopIgnoredReported = false
            return
        }
        guard isPumpBehaviourEnabled else {
            if !automaticStopIgnoredReported {
                automaticStopIgnoredReported = true
                SessionLog.shared.log(.lifecycle, "automatic stop due (counter \(commandControlPoint.automaticStopCounter) min ≥ timeout \(commandControlPoint.automaticStopTimeout) min); pump behaviour off, therapy continues")
            }
            return
        }
        commandControlPoint.hasAutomaticStopFired = true
        let stopped = setTherapyControlState(.stop)
        issueGeneralAnnunciation(annunciationType: .automaticStop)
        SessionLog.shared.log(.lifecycle, "automatic stop: counter \(commandControlPoint.automaticStopCounter) min ≥ timeout \(commandControlPoint.automaticStopTimeout) min, therapy \(stopped ? "stopped" : "already not running"), Automatic Stop annunciation raised")
        delegate?.mockPumpDidUpdate(self)
    }

    /// Stores a v2 event and tells the controller, as the kit does for its own events.
    func recordV2HistoryEvent(type: IDHistoryEventType, eventData: Data) {
        (recordAccessControlPoint as? IDRecordAccessControlPointCharacteristicEnhancement)?.recordEnhancedHistoryEvent(type: type, eventData: eventData)
        statusChangedCharacteristic.triggerIndication(for: [.historyEventRecordedChanged])
        delegate?.mockPumpDidUpdate(self)
    }

    /// A fast bolus programmed on the pump's own UI.
    func startLocalBolus(_ amount: Double) -> BolusID {
        let bolusID = setBolus(amount, activationType: .manualBolus)
        localBolusIDs.insert(bolusID)
        return bolusID
    }

    /// Basal delivered since the current time block began, or since the TBR began while one runs: the rate over
    /// the time elapsed, which is what the pump's own accounting does between events.
    var basalAmountDeliveredInCurrentBlock: Double {
        let delivery = getActiveBasalDelivery()
        let elapsed: TimeInterval
        let rate: Double
        if let tempBasalRate = delivery.tempBasalRate,
           let programmed = delivery.tempBasalDurationProgrammed,
           let remaining = delivery.tempBasalDurationRemaining
        {
            rate = tempBasalRate
            elapsed = max(0, programmed - remaining)
        } else {
            rate = delivery.rate
            elapsed = timeIntoCurrentBasalBlock
        }
        return (rate * elapsed / 3600 * 100).rounded() / 100
    }

    private var timeIntoCurrentBasalBlock: TimeInterval {
        let now = Date()
        let sinceMidnight = now.timeIntervalSince(Calendar.current.startOfDay(for: now))
        var blockStart: TimeInterval = 0
        for segment in basalProfile {
            if sinceMidnight < blockStart + segment.duration { break }
            blockStart += segment.duration
        }
        return sinceMidnight - blockStart
    }

    override class func createWritableCharacteristic<T: WritableCharacteristic>(of type: T.Type, messageQueue: any MessagingQueue) -> T {
        if type == IDStatusReaderControlPointCharacteristic.self {
            return IDStatusReaderControlPointEnhancement(messageQueue: messageQueue) as! T
        } else if type == IDCommandControlPointCharacteristic.self {
            return IDCommandControlPointEnhancement(messageQueue: messageQueue) as! T
        } else if type == IDRecordAccessControlPointCharacteristic.self {
            return IDRecordAccessControlPointCharacteristicEnhancement(messageQueue: messageQueue) as! T
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
    
    override class func createIndicativeCharacteristic<T: IndicativeCharacertistic>(of type: T.Type, messageQueue: any MessagingQueue) -> T {
        if type == IDHistoryDataCharacteristic.self {
            return IDHistoryDataCharacteristicEnhancement(messageQueue: messageQueue) as! T
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
