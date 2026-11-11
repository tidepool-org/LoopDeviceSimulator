//
//  TesterSettingsStore.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-10.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Keeps the tester's configuration across relaunches. Each server keeps one Codable snapshot of its
//  settings under its owner key in UserDefaults, diffed so the frequent saves from the mock delegates cost
//  a comparison and no I/O. Pairings and device history have their own stores; Reset to Defaults clears
//  all three.

import Foundation

final class TesterSettingsStore {
    static let shared = TesterSettingsStore()

    /// The advertised-name override entered on the root screen; blank means each server's own default.
    static let serverNameKey = "testerSettings.serverName"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var lastSaved: [SecurityStateStore.Owner: Any] = [:]

    // JSON has no infinity or NaN; a glucose entry can produce either, and a failed encode must not lose the save.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// nil when nothing is stored or the stored shape no longer decodes: an older format means defaults, not a crash.
    func load<T: Decodable & Equatable>(_ type: T.Type, for owner: SecurityStateStore.Owner) -> T? {
        guard let data = defaults.data(forKey: key(owner)),
              let value = try? decoder.decode(T.self, from: data)
        else { return nil }
        lock.withLock { lastSaved[owner] = value }
        return value
    }

    /// Writes only when the value differs from the last save or load; a value that cannot be encoded is not
    /// remembered as saved.
    func save<T: Encodable & Equatable>(_ value: T, for owner: SecurityStateStore.Owner) {
        let unchanged: Bool = lock.withLock {
            if let previous = lastSaved[owner] as? T, previous == value { return true }
            return false
        }
        guard !unchanged, let data = try? encoder.encode(value) else { return }
        lock.withLock { lastSaved[owner] = value }
        defaults.set(data, forKey: key(owner))
    }

    func forget(_ owner: SecurityStateStore.Owner) {
        lock.withLock { lastSaved[owner] = nil }
        defaults.removeObject(forKey: key(owner))
    }

    func forgetServerName() {
        defaults.removeObject(forKey: Self.serverNameKey)
    }

    private func key(_ owner: SecurityStateStore.Owner) -> String {
        "testerSettings.\(owner.rawValue)"
    }
}
