//
//  IDRecordAccessEnhancement.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-17.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryServiceKit
import BluetoothCommonKit

class IDRecordAccessControlPointCharacteristicEnhancement: IDRecordAccessControlPointCharacteristic {
    override func responseForRequest(_ request: Data) -> Data? {
        var index = 0
        guard let opcode: IDRACPOpcode = responseOpcode(request) else {
            let opcodeValue = request[request.startIndex...].to(IDRACPOpcode.RawValue.self)
            ConsoleOut.shared.logMessage(message: "Opcode is RFU. Complete response: \(request.hexadecimalString)")
            var response = Data(IDRACPOpcode.responseCode.rawValue)
            response.append(IDRACPOperator.nullOperator.rawValue)
            response.append(opcodeValue)
            response.append(IDRACPResponseCode.opcodeNotSupported.rawValue)
            return addE2EProtection(response: response)
        }
        index += 1

        guard let operatorValue = IDRACPOperator(rawValue: request[request.startIndex.advanced(by: index)...].to(IDRACPOperator.RawValue.self)) else {
            ConsoleOut.shared.logMessage(message: "Operator is RFU. Complete response: \(request.hexadecimalString)")
            return createResponseWith(.operatorNotSupported, requestOpcode: opcode)
        }
        index += 1

        ConsoleOut.shared.logMessage(message: "racp response opcode:\(opcode.procedureID)")
        switch opcode {
        case .combinedReport:
            shouldAbort = false
            guard operatorValue != .nullOperator else {
                ConsoleOut.shared.logMessage(message: "Operator Invalid (Null not allowed): \(operatorValue)")
                return createResponseWith(.invalidOperator, requestOpcode: opcode)
            }
            
            guard !isServerBusy else {
                ConsoleOut.shared.logMessage(message: "Server is busy and cannot respond to RACP procedure: \(opcode)")
                return createResponseWith(.procedureNotApplicable, requestOpcode: opcode)
            }
            
            guard !storedHistoryEvents.isEmpty else {
                return createResponseNoRecordsFound(requestOpcode: opcode)
            }
            
            var numberOfRecords = 0
            if operatorValue.includesFilterType {
                guard let filterType = IDRACPFilterType(rawValue: request[request.startIndex.advanced(by: index)...].to(IDRACPFilterType.RawValue.self)) else {
                    ConsoleOut.shared.logMessage(message: "Filter type RFU. Complete response: \(request.hexadecimalString)")
                    return createResponseWith(.operandNotSupported, requestOpcode: opcode)
                }
                index += 1
                
                if operatorValue == .lessThanOrEqualTo {
                    let historyEventsToReport: [PumpHistoryEvent]
                    switch filterType {
                    case .recordNumber:
                        let maxValue = Int(request[request.startIndex.advanced(by: index)...].to(RecordNumber.self))
                        index += 4
                        historyEventsToReport = storedHistoryEvents.filter({ $0.recordNumber <= maxValue })
                    default:
                        // TODO support the other filter types
                        historyEventsToReport = []
                        break
                    }
                    guard !historyEventsToReport.isEmpty else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = historyEventsToReport.count
                    for historyEvent in historyEventsToReport {
                        guard !shouldAbort else { break }
                        _ = indicateHistoryEvent(v2Event(historyEvent))
                    }
                } else if operatorValue == .greaterThanOrEqualTo {
                    let historyEventsToReport: [PumpHistoryEvent]
                    switch filterType {
                    case .recordNumber:
                        let minValue = Int(request[request.startIndex.advanced(by: index)...].to(RecordNumber.self))
                        index += 4
                        guard minValue <= storedHistoryEvents.count else {
                            return createResponseNoRecordsFound(requestOpcode: opcode)
                        }
                        historyEventsToReport = storedHistoryEvents.filter({ $0.recordNumber >= minValue })
                    default:
                        // TODO support the other filter types
                        historyEventsToReport = []
                        break
                    }
                    guard !historyEventsToReport.isEmpty else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = historyEventsToReport.count
                    for historyEvent in historyEventsToReport {
                        guard !shouldAbort else { break }
                        _ = indicateHistoryEvent(v2Event(historyEvent))
                    }
                } else {
                    // inclusive range
                    var historyEventsToReport: [PumpHistoryEvent]
                    switch filterType {
                    case .recordNumber:
                        let minValue = Int(request[request.startIndex.advanced(by: index)...].to(RecordNumber.self))
                        index += 4
                        guard minValue <= storedHistoryEvents.count else {
                            return createResponseNoRecordsFound(requestOpcode: opcode)
                        }
                        historyEventsToReport = storedHistoryEvents.filter({ $0.recordNumber >= minValue })
                        
                        let maxValue = Int(request[request.startIndex.advanced(by: index)...].to(RecordNumber.self))
                        index += 4
                        historyEventsToReport = historyEventsToReport.filter({ $0.recordNumber <= maxValue })
                    default:
                        // TODO support the other filter types
                        historyEventsToReport = []
                        break
                    }
                    guard !historyEventsToReport.isEmpty else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    
                    numberOfRecords = historyEventsToReport.count
                    for historyEvent in historyEventsToReport {
                        guard !shouldAbort else { break }
                        _ = indicateHistoryEvent(v2Event(historyEvent))
                    }
                }
            } else {
                if operatorValue == .allRecords {
                    numberOfRecords = storedHistoryEvents.count
                    for historyEvent in storedHistoryEvents {
                        guard !shouldAbort else { break }
                        _ = indicateHistoryEvent(v2Event(historyEvent))
                    }
                } else if operatorValue == .firstRecord {
                    guard let historyEvent = storedHistoryEvents.first else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = 1
                    _ = indicateHistoryEvent(v2Event(historyEvent))
                } else {
                    guard let historyEvent = storedHistoryEvents.last else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = 1
                    _ = indicateHistoryEvent(v2Event(historyEvent))
                }
            }
            return createCombinedReportResponse(UInt32(numberOfRecords))
        default:
            return super.responseForRequest(request)
        }
    }
    
    func createCombinedReportResponse(_ numberOfRecords: UInt32) -> Data {
        ConsoleOut.shared.logMessage(message: "\(#function) numberOfRecords: \(numberOfRecords)")
        var response = Data(IDRACPOpcode.combinedReportResponse.rawValue)
        response.append(IDRACPOperator.nullOperator.rawValue)
        response.append(numberOfRecords)
        return addE2EProtection(response: response)
    }

    override func addReferenceTimeHistoryEvent() {
        let offset = TimeInterval(TimeZone.current.secondsFromGMT(for: referenceTime))
        let eventData = ReferenceTimeHistoryEventEnhancement.createEventData(referenceTime, reason: .dateTimeLoss, timeZoneAndDSTOffset: offset)
        createHistoryEvent(for: .referenceTime, eventData: eventData)
    }

    // MARK: v2 events

    /// Records an event of a type the kit does not know. The kit allocates the record number and offset when it
    /// creates an event, so a known placeholder is recorded and then replaced by the v2 event carrying both.
    func recordEnhancedHistoryEvent(type: IDHistoryEventType, eventData: Data) {
        guard let eventType = IDHistoryEventType.v2EventTypes.first(where: { $0.type == type })?.event else {
            createHistoryEvent(for: type, eventData: eventData)
            return
        }
        createHistoryEvent(for: .maxBolusAmountChanged, eventData: MaxBolusAmountChangedHistoryEvent.createEventData(oldAmount: 0, newAmount: 0))
        guard let placeholder = storedHistoryEvents.last, placeholder.type == .maxBolusAmountChanged else { return }
        storedHistoryEvents[storedHistoryEvents.count - 1] = eventType.init(recordNumber: placeholder.recordNumber, relativeOffset: placeholder.relativeOffset, eventData: eventData)
        ConsoleOut.shared.logMessage(message: "recorded v2 history event \(type) as record \(placeholder.recordNumber): \(eventData.hexadecimalString)")
        historyDidChange?()
    }

    /// The kit stores Reference Time and Delivered Basal Rate Changed in their v1 layouts; a Combined Report
    /// sends them in the v2 ones, with the Time Source and TZ/DST Offset, and the Basal Amount Delivered since
    /// the previous basal change.
    func v2Event(_ event: PumpHistoryEvent) -> PumpHistoryEvent {
        switch event.type {
        case .referenceTime:
            return ReferenceTimeHistoryEventEnhancement.convertingFromV1(event, timeSource: .manual)
        case .deliveredBasalRateChanged:
            return DeliveredBasalRateChangedHistoryEventEnhancement.addingAmountDelivered(basalAmountDelivered(before: event), to: event)
        default:
            return event
        }
    }

    /// The previous basal change's rate over the time until this one.
    private func basalAmountDelivered(before event: PumpHistoryEvent) -> Double {
        guard let previous = storedHistoryEvents.last(where: { $0.type == .deliveredBasalRateChanged && $0.recordNumber < event.recordNumber }) else { return 0 }
        let previousRate = DeliveredBasalRateChangedHistoryEventEnhancement(recordNumber: previous.recordNumber, relativeOffset: previous.relativeOffset, eventData: previous.eventData).newRate
        let hours = max(0, event.relativeOffset - previous.relativeOffset) / 3600
        return (previousRate * hours * 100).rounded() / 100
    }
}

class IDRecordAccessControlPointDataHandlerEnhancement: IDRecordAccessControlPointDataHandler {
    override func handleResponse(_ response: Data) -> (result: DeviceCommResult<Any?>, completion: Any?) {
        guard e2eDelegate?.isE2EProtectionSupported == false || (e2eDelegate?.isE2EProtectionSupported == true && response.isCRCValid) else {
            return (.failure(.invalidCRC), nil)
        }

        guard let opcode: IDRACPOpcode = responseOpcode(response) else {
            return (.failure(.opcodeUnknown(response.hexadecimalString)), nil)
        }
        
        switch opcode {
        case .combinedReportResponse:
            let completion = completeProcedure(IDRACPOpcode.combinedReport)
            let numberOfStoredRecords = Int(response[response.startIndex.advanced(by: 2)...].to(UInt32.self))
            return (.success(numberOfStoredRecords), completion)
        default:
            return super.handleResponse(response)
        }
    }
    
    func createGetAllCombinedReportRequest() -> Data {
        createCombinedReportRequest(racpOperator: .allRecords)
    }
    
    func createGetAllCombinedReportRequest(beforeIncludingRecordNumber recordNumber: RecordNumber) -> Data {
        createCombinedReportRequest(racpOperator: .lessThanOrEqualTo, maxRecordNumber: recordNumber)
    }
    
    public func createGetAllCombinedReportRequest(afterIncludingRecordNumber recordNumber: RecordNumber) -> Data {
        createCombinedReportRequest(racpOperator: .greaterThanOrEqualTo, minRecordNumber: recordNumber)
    }
    
    public func createGetAllCombinedReportInclusiveRangeRequest(minRecordNumber: RecordNumber, maxRecordNumber: RecordNumber) -> Data {
        createCombinedReportRequest(racpOperator: .inclusiveRange, minRecordNumber: minRecordNumber, maxRecordNumber: maxRecordNumber)
    }
    
    public func createGetMostCurrentCombinedReportRequest() -> Data {
        createCombinedReportRequest(racpOperator: .lastRecord)
    }
    
    public func createOldestCombinedReportRequest() -> Data {
        createCombinedReportRequest(racpOperator: .firstRecord)
    }
    
    func createCombinedReportRequest(racpOperator: IDRACPOperator, minRecordNumber: RecordNumber? = nil, maxRecordNumber: RecordNumber? = nil) -> Data {
        let min: UInt? = minRecordNumber == nil ? nil : UInt(minRecordNumber!)
        let max: UInt? = maxRecordNumber == nil ? nil : UInt(maxRecordNumber!)
        let operand = operandFor(racpOperator: racpOperator, min: min, max: max, filterType: .recordNumber)
        return buildRequest(.combinedReport, racpOperator: racpOperator, operand: operand)
    }
}

extension IDRACPOpcode {
    static public let combinedReport = IDRACPOpcode(rawValue: 0x33)
    static public let combinedReportResponse = IDRACPOpcode(rawValue: 0x96)

    var requestOpcode: IDRACPOpcode? {
        switch self {
        case .numberOfStoredRecordsResponse: return .reportNumberOfStoredRecords
        case .combinedReportResponse: return .combinedReport
        default:
            return nil
        }
    }
    
    static var responseOpcodes: [IDRACPOpcode] {
        return [
            .responseCode,
            .numberOfStoredRecordsResponse,
            .combinedReportResponse
        ]
    }
    
    private var debugDescription: String {
        switch self {
        case .responseCode: return "responseCode"
        case .combinedReport: return "combinedReport"
        case .deleteStoredRecords: return "deleteStoredRecords"
        case .abortOperation: return "abortOperation"
        case .reportNumberOfStoredRecords: return "reportNumberOfStoredRecords"
        case .numberOfStoredRecordsResponse: return "numberOfStoredRecordsResponse"
        case .combinedReportResponse: return "combinedReportResponse"
        default: return "unknown opcode \(self.rawValue)"
        }
    }
}
