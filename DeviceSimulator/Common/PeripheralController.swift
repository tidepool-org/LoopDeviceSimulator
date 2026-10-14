//
//  PeripheralController.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-07.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  Shared CBCentralManager lifecycle for the in-app test clients: scan for one service, connect, discover
//  characteristics, and rescan after a disconnect or a failed connection. Subclasses handle values.
//  The Insulin Delivery and Authorization Control clients can adopt this once their logic is folded in.

import Foundation
import CoreBluetooth

protocol PeripheralControllerDelegate: AnyObject {
    func peripheralDiscovered(sender: PeripheralController, peripheralID: UUID, peripheralName: String, advertisingName: String, serviceData: [CBUUID: Data]?, rssi: NSNumber)
    func connectedToPeripheral(sender: PeripheralController)
    func didDisconnectFromPeripheral(sender: PeripheralController)
    func characteristicIndicationMessage(_ cbUUID: CBUUID, message: String)
}

class PeripheralController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    weak var delegate: PeripheralControllerDelegate?

    /// Advertised service the scan filters on.
    let scanServiceUUIDs: [CBUUID]

    /// Services discovered after connecting.
    let discoveredServiceUUIDs: [CBUUID]

    private(set) var peripheralArray: [CBPeripheral] = []
    private(set) var centralManager: CBCentralManager!
    private(set) var connectedPeripheral: CBPeripheral?

    /// Set by `stop()`; the automatic rescans after power-on and link loss are skipped while true.
    private var isStopped = false

    init(scanServiceUUIDs: [CBUUID], discoveredServiceUUIDs: [CBUUID]) {
        self.scanServiceUUIDs = scanServiceUUIDs
        self.discoveredServiceUUIDs = discoveredServiceUUIDs
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Commands

    func scanForPeripherals() {
        isStopped = false
        centralManager.stopScan()
        peripheralArray.removeAll()
        centralManager.scanForPeripherals(withServices: scanServiceUUIDs)
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    /// Stops scanning, drops any connection and silences the delegate. The asynchronous disconnect callback
    /// that follows must not turn the radio back on, so rescans stay off until `scanForPeripherals()`.
    func stop() {
        isStopped = true
        delegate = nil
        centralManager.stopScan()
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
    }

    func disconnectFromPeripheral() {
        guard let connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(connectedPeripheral)
    }

    func connectToPeripheralWithUUID(uuid: UUID) {
        guard let peripheral = peripheralArray.first(where: { $0.identifier == uuid }) else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral)
    }

    // MARK: - Subclass hooks

    /// Called after services and their characteristics for `service` are known.
    func peripheralDidDiscoverCharacteristics(_ characteristics: [CBCharacteristic], for service: CBService, on peripheral: CBPeripheral) { }

    /// Called when the link is gone, before the delegate hears about it. Clear per-connection state here.
    func peripheralDidDisconnect() { }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("central.state is \(central.state.rawValue)")
        if central.state == .poweredOn {
            if !isStopped {
                central.scanForPeripherals(withServices: scanServiceUUIDs)
            }
            return
        }
        // Bluetooth went away (off, resetting, unauthorized): only report a disconnect if there was a link.
        guard connectedPeripheral != nil else { return }
        handleLinkLost()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print(peripheral, " AD data: ", advertisementData)
        // A Mac (or any peripheral) may advertise the service without a name the system has cached yet;
        // dropping it would hide a perfectly connectable sensor. Fall back to the advertised or a placeholder name.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name ?? advertisedName ?? "Unnamed \(peripheral.identifier.uuidString.prefix(8))"
        delegate?.peripheralDiscovered(
            sender: self,
            peripheralID: peripheral.identifier,
            peripheralName: peripheralName,
            advertisingName: advertisedName ?? "unknown",
            serviceData: advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
            rssi: RSSI
        )
        peripheralArray.append(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "unknown")")
        peripheral.discoverServices(discoveredServiceUUIDs)
        delegate?.connectedToPeripheral(sender: self)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "unknown"): \(String(describing: error))")
        handleLinkLost()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleLinkLost()
    }

    private func handleLinkLost() {
        connectedPeripheral = nil
        peripheralDidDisconnect()
        peripheralArray.removeAll()
        guard !isStopped else { return }
        // A radio that is off resumes scanning from the power-on callback instead.
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: scanServiceUUIDs)
        }
        delegate?.didDisconnectFromPeripheral(sender: self)
    }

    // MARK: - CBPeripheralDelegate (discovery)

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            print("discovered service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("discovered \(service.uuid)/\(characteristic.uuid) properties \(characteristic.properties.rawValue)")
        }
        peripheralDidDiscoverCharacteristics(characteristics, for: service, on: peripheral)
    }
}
