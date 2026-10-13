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

    /// Optional override for the advertised name; blank lets each server use its own default.
    @State private var serverName: String = ""

    /// Passed to each server on appearance; an empty string tells the view model to use its own default.
    private var serverNameOverride: String {
        serverName.trimmingCharacters(in: .whitespaces)
    }

    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    Section(footer: Text("Blank uses \(InsulinDeliveryConstants.serverName) for the pump and \(CGMConstants.serverName) for the CGM.")) {
                        TextField("Server Name (optional override)", text: $serverName)
                    }

                    // One server at a time: each server view starts on appear and stops on disappear,
                    // and the stack navigation shows a single detail view (HYD-Q-008).
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
                }
                .navigationTitle("Simulator \(Bundle.main.fullVersionString)")
            }
        }
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
