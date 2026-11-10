//
//  DeviceSimulatorApp.swift
//  Device Simulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import BluetoothCommonKit

@main
struct DeviceSimulatorApp: App, HorizontalSizeClassOverride {
    private var insulinDeliveryServerViewModel = InsulinDeliveryServerViewModel()
    private var insulinDeliveryClientViewModel = InsulinDeliveryClientViewModel()
    private var authorizationControlClientViewModel = AuthorizationControlClientViewModel()
    private var cgmServerViewModel = CGMServerViewModel()
    private var cgmClientViewModel = CGMClientViewModel()

    /// Optional override for the advertised name; blank lets each server use its own default. Kept across relaunches.
    @AppStorage(TesterSettingsStore.serverNameKey) private var serverName: String = ""
    @State private var isConfirmingReset = false

    /// Passed to each server on appearance; an empty string tells the view model to use its own default.
    private var serverNameOverride: String {
        serverName.trimmingCharacters(in: .whitespaces)
    }

    init() {
        // The log captures the kits' console from the first message; it must exist before any server starts.
        _ = SessionLog.shared
    }

    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    Section(footer: Text("Blank uses \(InsulinDeliveryConstants.serverName) for the pump and \(CGMConstants.serverName) for the CGM.")) {
                        TextField("Server Name (optional override)", text: $serverName)
                    }

                    // One server at a time: each server view starts on appear and stops on disappear,
                    // and the stack navigation shows a single detail view.
                    Section(header: Text("Services")) {
                        NavigationLink(destination: insulinDeliveryServerView) {
                            Text("Insulin Delivery Server")
                        }
                        NavigationLink(destination: cgmServerView) {
                            Text("CGM Sensor Server")
                        }
                    }

                    Section(header: Text("Clients")) {
                        NavigationLink(destination: insulinDeliveryClientView) {
                            Text("Insulin Delivery Client")
                        }
                        NavigationLink(destination: cgmClientView) {
                            Text("CGM Collector Client")
                        }
                        NavigationLink(destination: authorizationControlClientView) {
                            Text("Authorization Control Client")
                        }
                    }

                    Section(header: Text("Diagnostics"), footer: Text("Every Bluetooth transaction, tester action and lifecycle event from both modes, kept across relaunches and exportable as JSONL.")) {
                        NavigationLink(destination: SessionLogView()) {
                            Text("Session Log")
                        }
                    }

                    Section(footer: Text("Puts every tester setting back to its default and forgets all pairings and device history. The session log is kept. The defaults are listed in the README.")) {
                        Button("Reset to Defaults", role: .destructive) {
                            isConfirmingReset = true
                        }
                        .confirmationDialog("Reset the simulator to its defaults?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                            Button("Reset Settings, Pairings and History", role: .destructive, action: resetToDefaults)
                        } message: {
                            Text("Loop will have to pair again. The session log is kept.")
                        }
                    }
                }
                .navigationTitle("Simulator \(Bundle.main.fullVersionString)")
            }
            .testToolNotice()
        }
    }

    /// The documented default state. Each server view model resets what it owns, including a server that is
    /// still running beside this list on iPad; the root owns the server name and the two clients' pairings.
    private func resetToDefaults() {
        SessionLog.shared.stimulus("Reset to Defaults")
        serverName = ""
        insulinDeliveryServerViewModel.resetToDefaults()
        cgmServerViewModel.resetToDefaults()
        SecurityStateStore.shared.forget(.cgmClient)
        SecurityStateStore.shared.forget(.authorizationControlClient)
        SessionLog.shared.log(.lifecycle, "reset to defaults: tester settings, pairings and device history cleared", mode: .app, role: .tester)
    }
    
    private var insulinDeliveryServerView: some View {
        InsulinDeliveryServerView(viewModel: insulinDeliveryServerViewModel, serverName: serverNameOverride)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }
    
    private var insulinDeliveryClientView: some View {
        InsulinDeliveryClientView(viewModel: insulinDeliveryClientViewModel)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }
    
    private var authorizationControlClientView: some View {
        AuthorizationControlClientView(viewModel: authorizationControlClientViewModel)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }

    private var cgmServerView: some View {
        CGMServerView(viewModel: cgmServerViewModel, serverName: serverNameOverride)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }

    private var cgmClientView: some View {
        CGMClientView(viewModel: cgmClientViewModel)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }
}
