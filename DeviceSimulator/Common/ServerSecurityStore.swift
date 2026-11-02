//
//  ServerSecurityStore.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-02.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation
import Security
import BluetoothCommonKit

/// What a simulated server needs to answer Loop over the ACS secure channel after a relaunch (HYDRA-9): the
/// security manager configuration (OOB number, key IDs, IV fixed fields and the nonce sequence number) and
/// the derived session key.
struct ServerSecurityState: Equatable {
    var configuration: SecurityManager.Configuration
    var sharedKeyData: Data?

    var isSecurityEstablished: Bool { sharedKeyData != nil }
}

/// Keeps each server's ACS pairing across relaunches and across switching between the pump and the CGM
/// server, so Loop can come back to either without a new key exchange. One entry per device: the
/// configuration and the Authorization Control gate live in UserDefaults, the session key in the keychain.
/// Saves are diffed against the last stored state because the mocks report every nonce step.
final class ServerSecurityStore {
    enum Device: String {
        case pump
        case cgm
    }

    static let shared = ServerSecurityStore()

    private let defaults: UserDefaults
    private let keychainService: String
    private let lock = NSLock()
    private var lastSaved: [Device: ServerSecurityState] = [:]

    init(defaults: UserDefaults = .standard, keychainService: String = "org.tidepool.DeviceSimulator.acs") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    // MARK: - Pairing

    /// nil when nothing was stored. A key without the OOB number it was confirmed with is dropped, the same
    /// rule `SecurityManager(configuration:)` applies on the client side.
    func load(_ device: Device) -> ServerSecurityState? {
        lock.withLock {
            guard let raw = defaults.dictionary(forKey: configurationKey(device)),
                  let configuration = SecurityManager.Configuration(rawValue: raw)
            else { return nil }
            var sharedKeyData = readKey(device)
            if configuration.oobRandomNumber.isEmpty {
                sharedKeyData = nil
            }
            let state = ServerSecurityState(configuration: configuration, sharedKeyData: sharedKeyData)
            lastSaved[device] = state
            return state
        }
    }

    func save(_ state: ServerSecurityState, for device: Device) {
        var state = state
        // An empty key is no key.
        if state.sharedKeyData?.isEmpty == true {
            state.sharedKeyData = nil
        }
        lock.withLock {
            let previous = lastSaved[device]
            guard previous != state else { return }
            if previous?.configuration != state.configuration {
                defaults.set(state.configuration.rawValue, forKey: configurationKey(device))
            }
            if previous == nil || previous?.sharedKeyData != state.sharedKeyData {
                writeKey(state.sharedKeyData, for: device)
            }
            lastSaved[device] = state
        }
    }

    /// Drops the key and the configuration so the next collector starts a fresh key exchange. The
    /// Authorization Control gate is a tester setting and stays.
    func forget(_ device: Device) {
        lock.withLock {
            defaults.removeObject(forKey: configurationKey(device))
            writeKey(nil, for: device)
            lastSaved[device] = nil
        }
    }

    // MARK: - Authorization Control gate

    func isAuthorizationControlEnabled(for device: Device) -> Bool {
        defaults.bool(forKey: authorizationControlKey(device))
    }

    func setAuthorizationControlEnabled(_ enabled: Bool, for device: Device) {
        defaults.set(enabled, forKey: authorizationControlKey(device))
    }

    // MARK: - Keys

    private func configurationKey(_ device: Device) -> String {
        "serverSecurity.\(device.rawValue).configuration"
    }

    private func authorizationControlKey(_ device: Device) -> String {
        "serverSecurity.\(device.rawValue).authorizationControlEnabled"
    }

    private func keychainQuery(for device: Device) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: device.rawValue]
    }

    private func readKey(_ device: Device) -> Data? {
        var query = keychainQuery(for: device)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                SessionLog.shared.log(.error, "\(device.rawValue) session key could not be read from the keychain (\(status))")
            }
            return nil
        }
        return result as? Data
    }

    /// nil removes the entry.
    private func writeKey(_ key: Data?, for device: Device) {
        let query = keychainQuery(for: device)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            SessionLog.shared.log(.error, "\(device.rawValue) session key could not be removed from the keychain (\(deleteStatus))")
        }
        guard let key else { return }
        var attributes = query
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            SessionLog.shared.log(.error, "\(device.rawValue) session key could not be stored in the keychain (\(status))")
        }
    }
}
