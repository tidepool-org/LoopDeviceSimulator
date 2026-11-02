//
//  SecurityStateStore.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-02.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation
import Security
import CoreBluetooth
import BluetoothCommonKit

/// What a simulated ACS peer needs to resume its secure channel after a relaunch (HYDRA-9): the security
/// manager configuration (OOB number, key IDs, IV fixed fields and the nonce sequence number), the derived
/// session key and, for a client, the resource handles it learned during the key exchange.
struct SecurityState: Equatable {
    var configuration: SecurityManager.Configuration
    var sharedKeyData: Data?
    /// Servers publish their own map and leave this empty.
    var uuidToHandleMap: [CBUUID: ResourceHandle] = [:]

    var isSecurityEstablished: Bool { sharedKeyData != nil }
}

/// Keeps each peer's ACS pairing across relaunches and across switching between the pump and the CGM
/// server, so Loop can come back to either without a new key exchange. One entry per owner: the
/// configuration, handle map and the Authorization Control gate live in UserDefaults, the session key in
/// the keychain. Saves are diffed against the last stored state because the peers report every nonce step.
final class SecurityStateStore {
    enum Owner: String {
        case pumpServer
        case cgmServer
        case authorizationControlClient
        case cgmClient
    }

    static let shared = SecurityStateStore()

    private let defaults: UserDefaults
    private let keychainService: String
    private let lock = NSLock()
    private var lastSaved: [Owner: SecurityState] = [:]

    init(defaults: UserDefaults = .standard, keychainService: String = "org.tidepool.DeviceSimulator.acs") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    // MARK: - Pairing

    /// nil when nothing was stored. A key without the OOB number it was confirmed with is dropped, the same
    /// rule `SecurityManager(configuration:)` applies on the client side.
    func load(_ owner: Owner) -> SecurityState? {
        lock.withLock {
            guard let raw = defaults.dictionary(forKey: configurationKey(owner)),
                  let configuration = SecurityManager.Configuration(rawValue: raw)
            else { return nil }
            var sharedKeyData = readKey(owner)
            if configuration.oobRandomNumber.isEmpty {
                sharedKeyData = nil
            }
            let rawHandleMap = defaults.dictionary(forKey: handleMapKey(owner)) as? [String: ResourceHandle] ?? [:]
            let uuidToHandleMap = Dictionary(uniqueKeysWithValues: rawHandleMap.map { (CBUUID(string: $0.key), $0.value) })
            let state = SecurityState(configuration: configuration, sharedKeyData: sharedKeyData, uuidToHandleMap: uuidToHandleMap)
            lastSaved[owner] = state
            return state
        }
    }

    func save(_ state: SecurityState, for owner: Owner) {
        var state = state
        // An empty key is no key.
        if state.sharedKeyData?.isEmpty == true {
            state.sharedKeyData = nil
        }
        lock.withLock {
            let previous = lastSaved[owner]
            guard previous != state else { return }
            if previous?.configuration != state.configuration {
                defaults.set(state.configuration.rawValue, forKey: configurationKey(owner))
            }
            if previous?.uuidToHandleMap != state.uuidToHandleMap {
                let rawHandleMap = Dictionary(uniqueKeysWithValues: state.uuidToHandleMap.map { ($0.key.uuidString, $0.value) })
                defaults.set(rawHandleMap, forKey: handleMapKey(owner))
            }
            if previous == nil || previous?.sharedKeyData != state.sharedKeyData {
                writeKey(state.sharedKeyData, for: owner)
            }
            lastSaved[owner] = state
        }
    }

    /// Drops the key, the configuration and the handle map so the next key exchange starts fresh. The
    /// Authorization Control gate is a tester setting and stays.
    func forget(_ owner: Owner) {
        lock.withLock {
            defaults.removeObject(forKey: configurationKey(owner))
            defaults.removeObject(forKey: handleMapKey(owner))
            writeKey(nil, for: owner)
            lastSaved[owner] = nil
        }
    }

    // MARK: - Authorization Control gate (servers)

    func isAuthorizationControlEnabled(for owner: Owner) -> Bool {
        defaults.bool(forKey: authorizationControlKey(owner))
    }

    func setAuthorizationControlEnabled(_ enabled: Bool, for owner: Owner) {
        defaults.set(enabled, forKey: authorizationControlKey(owner))
    }

    // MARK: - Keys

    private func configurationKey(_ owner: Owner) -> String {
        "securityState.\(owner.rawValue).configuration"
    }

    private func handleMapKey(_ owner: Owner) -> String {
        "securityState.\(owner.rawValue).handleMap"
    }

    private func authorizationControlKey(_ owner: Owner) -> String {
        "securityState.\(owner.rawValue).authorizationControlEnabled"
    }

    private func keychainQuery(for owner: Owner) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: owner.rawValue]
    }

    private func readKey(_ owner: Owner) -> Data? {
        var query = keychainQuery(for: owner)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                SessionLog.shared.log(.error, "\(owner.rawValue) session key could not be read from the keychain (\(status))")
            }
            return nil
        }
        return result as? Data
    }

    /// nil removes the entry.
    private func writeKey(_ key: Data?, for owner: Owner) {
        let query = keychainQuery(for: owner)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            SessionLog.shared.log(.error, "\(owner.rawValue) session key could not be removed from the keychain (\(deleteStatus))")
        }
        guard let key else { return }
        var attributes = query
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            SessionLog.shared.log(.error, "\(owner.rawValue) session key could not be stored in the keychain (\(status))")
        }
    }
}
