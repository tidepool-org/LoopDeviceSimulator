//
//  PumpStateStore.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-16.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Keeps the simulated pump's state (reservoir, profile, therapy and operational state, delivery totals)
//  across a power cycle and an app relaunch, the way a real pump keeps its own. One property list in
//  Application Support/HYDRA, written when the state changes, about once a minute while only the accounting
//  stamp moves, and when the server stops. Reset to Defaults drops it.

import Foundation

final class PumpStateStore {
    static let shared = PumpStateStore()

    private let fileURL: URL
    private let writer = DispatchQueue(label: "org.tidepool.hydra.pumpstate", qos: .utility)
    private let lock = NSLock()
    private var lastSaved: NSDictionary?

    init(folder: URL? = nil) {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let directory = folder ?? base.appendingPathComponent("HYDRA", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pump-state.plist")
    }

    /// nil when nothing is stored or the file is not a property list dictionary.
    func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        lock.withLock { lastSaved = value as NSDictionary }
        return value
    }

    /// The pump stamps every accounting run, even when nothing was delivered. The restore reads that stamp as the
    /// moment the pump went off, and while a temp basal runs it is the only value that moves (the temp's units are
    /// counted when it ends), so a stamp-only change is written about once a minute rather than on every tick.
    static let stampKey = "lastDeliveryUpdate"
    static let stampInterval: TimeInterval = 60

    /// Writes when the state differs from the last save or load, when the stamp has moved by `stampInterval`, or
    /// when forced (the server stopping). A state that cannot be serialised is dropped.
    func save(_ state: [String: Any], force: Bool = false) {
        let dictionary = state as NSDictionary
        let unchanged: Bool = lock.withLock {
            guard !force, let lastSaved, Self.stripped(lastSaved).isEqual(Self.stripped(dictionary)) else { return false }
            guard let old = lastSaved[Self.stampKey] as? Date, let new = state[Self.stampKey] as? Date else { return true }
            return new.timeIntervalSince(old) < Self.stampInterval
        }
        guard !unchanged, let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0) else { return }
        lock.withLock { lastSaved = dictionary }
        let url = fileURL
        writer.async { try? data.write(to: url, options: .atomic) }
    }

    private static func stripped(_ dictionary: NSDictionary) -> NSDictionary {
        (dictionary as? [String: Any] ?? [:]).filter { $0.key != stampKey } as NSDictionary
    }

    func forget() {
        lock.withLock { lastSaved = nil }
        let url = fileURL
        writer.async { try? FileManager.default.removeItem(at: url) }
    }
}
