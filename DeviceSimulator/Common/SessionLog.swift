//
//  SessionLog.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-16.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  The session log shared by pump and CGM mode (HYD-O-001/003/004, TBD-01/02; CGM-DESIGN §Logging). Every
//  message the kits and the GATT server print goes through BluetoothCommonKit's ConsoleOut, so the log makes
//  itself that console's delegate and stamps each message with a timestamp, the active mode and a kind. The
//  view models add what the kits cannot know: tester stimuli and connection events. Lines are JSONL in
//  Application Support, so a run survives relaunches, and the file is exported through the share sheet.

import Foundation
import Observation
import BluetoothCommonKit

/// One line of the session log.
struct SessionLogEntry: Codable, Identifiable, Sendable {
    enum Mode: String, Codable, Sendable { case cgm, pump, acs, app }
    enum Role: String, Codable, Sendable { case server, client, tester }
    enum Kind: String, Codable, Sendable, CaseIterable {
        case connection, read, write, notify, indicate, stimulus, lifecycle, trace, error
    }

    /// Sequence number within the file.
    let id: Int
    /// UTC with milliseconds in the file; host time, see CGM-DESIGN §Session and time.
    let timestamp: Date
    let mode: Mode
    let role: Role
    let kind: Kind
    /// Active glucose source (CGM) or "mock pump"; nil for app-level lines.
    let scenario: String?
    /// What makes the scenario reproducible, e.g. the trace-effects seed.
    let scenarioVersion: String?
    let detail: String
}

@Observable
final class SessionLog: @unchecked Sendable {
    static let shared = SessionLog()
    /// Lines kept in memory for the on-device view; the file holds everything.
    static let recentLimit = 1000

    struct Context: Equatable, Sendable {
        var mode: SessionLogEntry.Mode = .app
        var role: SessionLogEntry.Role = .tester
        var scenario: String? = nil
        var scenarioVersion: String? = nil
    }

    /// Stamped on every entry until changed; the active screen sets it when its server or client starts and
    /// puts it back to the default when it stops.
    var context: Context {
        get { lock.withLock { _context } }
        set { lock.withLock { _context = newValue } }
    }

    /// Newest first.
    private(set) var recent: [SessionLogEntry] = []
    private(set) var entryCount = 0
    let fileURL: URL

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var _context = Context()
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private let writer = DispatchQueue(label: "org.tidepool.hydra.sessionlog")
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("HYDRA", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("session-log.jsonl")

        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SessionLog.iso8601.string(from: date))
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = SessionLog.iso8601.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not ISO 8601: \(text)"))
            }
            return date
        }

        loadExisting()
        ConsoleOut.shared.delegate = self
        log(.lifecycle, "app launched \(Bundle.main.fullVersionString)", mode: .app, role: .tester)
    }

    // MARK: Writing

    /// Appends one line. Safe from any thread: the kits log from timer callbacks and CoreBluetooth queues.
    func log(_ kind: SessionLogEntry.Kind, _ detail: String, mode: SessionLogEntry.Mode? = nil, role: SessionLogEntry.Role? = nil) {
        let entry: SessionLogEntry = lock.withLock {
            defer { nextID += 1 }
            return SessionLogEntry(id: nextID, timestamp: Date(), mode: mode ?? _context.mode, role: role ?? _context.role,
                                   kind: kind, scenario: _context.scenario, scenarioVersion: _context.scenarioVersion, detail: detail)
        }
        writer.async { [self] in append(entry) }
        if Thread.isMainThread {
            record(entry)
        } else {
            DispatchQueue.main.async { self.record(entry) }
        }
    }

    /// Something the tester did.
    func stimulus(_ detail: String) {
        log(.stimulus, detail, role: .tester)
    }

    /// Deletes the file and starts the numbering over.
    func clear() {
        writer.sync { [self] in
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
        lock.withLock { nextID = 1 }
        recent.removeAll()
        entryCount = 0
        log(.lifecycle, "log cleared", mode: .app, role: .tester)
    }

    var fileSizeDescription: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func record(_ entry: SessionLogEntry) {
        recent.insert(entry, at: 0)
        if recent.count > Self.recentLimit {
            recent.removeLast(recent.count - Self.recentLimit)
        }
        entryCount += 1
    }

    /// Writer queue only.
    private func append(_ entry: SessionLogEntry) {
        guard let line = try? encoder.encode(entry) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: line + Data([0x0A]))
    }

    /// Picks up where the last run left off: the tail for the view, the count and the next sequence number.
    private func loadExisting() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        entryCount = lines.count
        recent = lines.suffix(Self.recentLimit).reversed().compactMap { try? decoder.decode(SessionLogEntry.self, from: $0) }
        nextID = (recent.first?.id ?? lines.count) + 1
    }
}

// MARK: - Console capture

extension SessionLog: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        log(Self.kind(of: message), message)
    }

    /// The kits print free text; this sorts it into a kind by the words they use. Anything unrecognised is
    /// a trace line rather than dropped.
    static func kind(of message: String) -> SessionLogEntry.Kind {
        let text = message.lowercased()
        if text.hasPrefix("lifecycle:") { return .lifecycle }
        if text.contains("integrity fault") || text.contains("error") || text.contains("fail") { return .error }
        if text.contains("readytosend") || text.contains("sendnextqueueitem") || text.contains("update_gatt_server") { return .trace }
        if text.contains("subscribe") || text.contains("advertis") || text.contains("connect") || text.contains("powered") || text.hasPrefix("state") { return .connection }
        if text.contains("notification") || text.contains("capturereading") { return .notify }
        if text.contains("indicat") { return .indicate }
        if text.contains("write") { return .write }
        if text.contains("read") { return .read }
        return .trace
    }
}
