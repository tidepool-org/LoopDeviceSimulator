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
import CoreTransferable
import UniformTypeIdentifiers
import BluetoothCommonKit

/// One line of the session log.
struct SessionLogEntry: Codable, Identifiable, Sendable {
    enum Mode: String, Codable, Sendable { case cgm, pump, acs, app }
    enum Role: String, Codable, Sendable { case server, client, tester }
    enum Kind: String, Codable, Sendable, CaseIterable {
        case connection, read, write, notify, indicate, stimulus, lifecycle, trace, error
    }

    /// Sequence number, increasing across launches until the log is cleared.
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
    /// Lines kept in memory for the on-device view; the file holds everything up to `maxFileBytes`.
    static let recentLimit = 1000
    /// Beyond this the file is rotated to `session-log.previous.jsonl`, so disk use is bounded at twice this.
    static let maxFileBytes: Int64 = 20 * 1024 * 1024
    /// How much of the file is read back at launch: enough for `recentLimit` lines of any realistic length.
    private static let tailReadBytes = 512 * 1024

    struct Context: Equatable, Sendable {
        var mode: SessionLogEntry.Mode = .app
        var role: SessionLogEntry.Role = .tester
        var scenario: String? = nil
        var scenarioVersion: String? = nil
    }

    /// Stamped on every entry until changed; the active screen sets it before its server or client starts
    /// and puts it back to the default after it stops, so the kits' own lines carry the right mode.
    var context: Context {
        get { lock.withLock { _context } }
        set { lock.withLock { _context = newValue } }
    }

    /// Newest first.
    private(set) var recent: [SessionLogEntry] = []
    /// Lines in the current file (the sequence number of the newest line).
    private(set) var entryCount = 0
    /// Bytes in the current file, kept here so the view never has to stat it.
    private(set) var fileSize: Int64 = 0
    let fileURL: URL
    let previousFileURL: URL

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var _context = Context()
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private let writer = DispatchQueue(label: "org.tidepool.hydra.sessionlog")
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private var writtenBytes: Int64 = 0   // writer queue only
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
        previousFileURL = folder.appendingPathComponent("session-log.previous.jsonl")

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

        loadTail()
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
        guard var line = try? encoder.encode(entry) else { return }
        // Explicit byte array: BluetoothCommonKit extends Data with a generic append that would write an
        // 8-octet integer here.
        line.append(contentsOf: [UInt8(0x0A)])
        writer.async { [self] in append(line) }
        let bytes = Int64(line.count)
        if Thread.isMainThread {
            record(entry, bytes: bytes)
        } else {
            DispatchQueue.main.async { self.record(entry, bytes: bytes) }
        }
    }

    /// Something the tester did.
    func stimulus(_ detail: String) {
        log(.stimulus, detail, role: .tester)
    }

    /// Deletes both files and starts the numbering over.
    func clear() {
        writer.sync { [self] in
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: previousFileURL)
            writtenBytes = 0
        }
        lock.withLock { nextID = 1 }
        recent.removeAll()
        entryCount = 0
        fileSize = 0
        log(.lifecycle, "log cleared", mode: .app, role: .tester)
    }

    /// A complete copy of the current file for the share sheet, taken between writes so no line is torn.
    func snapshot() throws -> URL {
        let stamp = Self.iso8601.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("hydra-session-log-\(stamp).jsonl")
        try writer.sync { [self] in
            try? FileManager.default.removeItem(at: destination)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.copyItem(at: fileURL, to: destination)
            } else {
                FileManager.default.createFile(atPath: destination.path, contents: Data())
            }
        }
        return destination
    }

    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Main thread only.
    private func record(_ entry: SessionLogEntry, bytes: Int64) {
        recent.insert(entry, at: 0)
        if recent.count > Self.recentLimit {
            recent.removeLast(recent.count - Self.recentLimit)
        }
        entryCount = entry.id
        fileSize = fileSize + bytes > Self.maxFileBytes ? bytes : fileSize + bytes
    }

    /// Writer queue only.
    private func append(_ line: Data) {
        if handle == nil { openForAppending() }
        if writtenBytes + Int64(line.count) > Self.maxFileBytes { rotate() }
        try? handle?.write(contentsOf: line)
        writtenBytes += Int64(line.count)
    }

    /// Writer queue only. A crash mid-write can leave a partial last line; a newline first keeps the next
    /// entry on its own line so only the fragment is lost.
    private func openForAppending() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let opened = try? FileHandle(forWritingTo: fileURL) else { return }
        handle = opened
        writtenBytes = Int64((try? opened.seekToEnd()) ?? 0)
        if writtenBytes > 0, let reader = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? reader.close() }
            try? reader.seek(toOffset: UInt64(writtenBytes - 1))
            if let last = try? reader.readToEnd(), last != Data([0x0A]) {
                try? opened.write(contentsOf: Data([0x0A]))
                writtenBytes += 1
            }
        }
    }

    /// Writer queue only. The current file becomes the previous one; the sequence numbers keep counting.
    private func rotate() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: previousFileURL)
        try? FileManager.default.moveItem(at: fileURL, to: previousFileURL)
        openForAppending()
    }

    /// Picks up where the last run left off from the tail of the file: the last `recentLimit` decodable lines
    /// for the view, and the next sequence number from the highest id seen. Reads at most `tailReadBytes`, so
    /// launch cost does not grow with the file.
    private func loadTail() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0,
              let reader = try? FileHandle(forReadingFrom: fileURL)
        else { return }
        defer { try? reader.close() }
        fileSize = size
        let offset = max(0, size - Int64(Self.tailReadBytes))
        try? reader.seek(toOffset: UInt64(offset))
        guard let data = try? reader.readToEnd(), !data.isEmpty else { return }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()   // started mid-line
        }
        let entries = lines.suffix(Self.recentLimit).compactMap { try? decoder.decode(SessionLogEntry.self, from: $0) }
        recent = entries.reversed()
        let highestID = entries.map(\.id).max() ?? 0
        entryCount = highestID
        nextID = highestID + 1
    }
}

// MARK: - Console capture

extension SessionLog: ConsoleOutDelegate {
    func displayMessageInConsole(message: String) {
        log(Self.kind(of: message), message)
    }

    /// The kits print free text; this sorts it into a kind by the words they use. Anything unrecognised is
    /// a trace line rather than dropped. Checked against what the kits and the app's controllers print:
    /// the clients report "error nil" on every healthy update, and "already" and "ready" contain "read".
    static func kind(of message: String) -> SessionLogEntry.Kind {
        let text = message.lowercased()
        if text.hasPrefix("lifecycle:") { return .lifecycle }
        let benignError = text.contains("error nil") || text.contains("error: nil") || text.contains("error: optional(nil)")
        if text.contains("integrity fault") || (text.contains("error") && !benignError) || text.contains("fail") { return .error }
        if text.contains("readytosend") || text.contains("sendnextqueueitem") || text.contains("update_gatt_server") { return .trace }
        if text.contains("subscribe") || text.contains("advertis") || text.contains("connect") || text.contains("powered") || text.hasPrefix("state") { return .connection }
        if text.contains("notification") || text.contains("capturereading") { return .notify }
        if text.contains("indicat") { return .indicate }
        if text.contains("write") { return .write }
        let mentionsRead = text.contains("read") && !text.contains("already") && !text.contains("ready") && !text.contains("thread")
        if mentionsRead { return .read }
        return .trace
    }
}

// MARK: - Export

/// What the share sheet receives: a snapshot copied between writes, never the live file.
struct SessionLogExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            SentTransferredFile(try SessionLog.shared.snapshot())
        }
    }
}
