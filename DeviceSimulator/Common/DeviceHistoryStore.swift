//
//  DeviceHistoryStore.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-03.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Keeps each simulated device's history across relaunches and reboots for as long as its pairing does:
//  the pump's history events and the CGM's measurement database. One JSON file per owner in
//  Application Support/HYDRA, next to the session log; `forget` drops it together with the pairing.

import Foundation

final class DeviceHistoryStore {
    static let shared = DeviceHistoryStore()

    private let folder: URL
    private let writer = DispatchQueue(label: "org.tidepool.hydra.history", qos: .utility)
    private let lock = NSLock()
    /// What was last written per owner: the mock delegates fire on every nonce step, so a save is usually
    /// one comparison and no I/O.
    private var lastSaved: [SecurityStateStore.Owner: Any] = [:]

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Failed CGM readings are NaN glucose; JSON has no NaN.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }()

    init(folder: URL? = nil) {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.folder = folder ?? base.appendingPathComponent("HYDRA", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    func fileURL(for owner: SecurityStateStore.Owner) -> URL {
        folder.appendingPathComponent("history.\(owner.rawValue).json")
    }

    /// nil when nothing is stored or the file no longer decodes: an older format is dropped, not a crash.
    func load<T: Decodable & Equatable>(_ type: T.Type, for owner: SecurityStateStore.Owner) -> T? {
        guard let data = try? Data(contentsOf: fileURL(for: owner)),
              let value = try? decoder.decode(T.self, from: data)
        else { return nil }
        lock.withLock { lastSaved[owner] = value }
        return value
    }

    /// Writes only when the value differs from the last save or load.
    func save<T: Encodable & Equatable>(_ value: T, for owner: SecurityStateStore.Owner) {
        let unchanged: Bool = lock.withLock {
            if let previous = lastSaved[owner] as? T, previous == value { return true }
            lastSaved[owner] = value
            return false
        }
        guard !unchanged, let data = try? encoder.encode(value) else { return }
        let url = fileURL(for: owner)
        writer.async { try? data.write(to: url, options: .atomic) }
    }

    /// Drops the stored history; the next save starts a fresh file.
    func forget(_ owner: SecurityStateStore.Owner) {
        lock.withLock { lastSaved[owner] = nil }
        let url = fileURL(for: owner)
        writer.async { try? FileManager.default.removeItem(at: url) }
    }
}
