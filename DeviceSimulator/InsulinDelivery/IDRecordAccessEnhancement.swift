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
                        _ = indicateHistoryEvent(historyEvent)
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
                        _ = indicateHistoryEvent(historyEvent)
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
                        _ = indicateHistoryEvent(historyEvent)
                    }
                }
            } else {
                if operatorValue == .allRecords {
                    numberOfRecords = storedHistoryEvents.count
                    for historyEvent in storedHistoryEvents {
                        guard !shouldAbort else { break }
                        _ = indicateHistoryEvent(historyEvent)
                    }
                } else if operatorValue == .firstRecord {
                    guard let historyEvent = storedHistoryEvents.first else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = 1
                    _ = indicateHistoryEvent(historyEvent)
                } else {
                    guard let historyEvent = storedHistoryEvents.last else {
                        return createResponseNoRecordsFound(requestOpcode: opcode)
                    }
                    numberOfRecords = 1
                    _ = indicateHistoryEvent(historyEvent)
                }
            }
            return createCombinedReportResponse(UInt32(numberOfRecords))
        default:
            return super.responseForRequest(request)
        }
    }
    
    func createCombinedReportResponse(_ numberOfRecords: UInt32) -> Data {
        var response = Data(IDRACPOpcode.combinedReportResponse.rawValue)
        response.append(IDRACPOperator.nullOperator.rawValue)
        response.append(numberOfRecords)
        return response
    }
    
    override func addReferenceTimeHistoryEvent() {
        let eventData = ReferenceTimeHistoryEventEnhancement.createEventData(referenceTime, reason: .dateTimeLoss, timeZoneAndDSTOffset: .minutes(60))
        createHistoryEvent(for: .referenceTime, eventData: eventData)
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
