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

    @State private var serverName: String = InsulinDeliveryConstants.serverName
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    HStack {
                        TextField("Server Name", text: $serverName)
                    }
                    
                    Section(header: Text("Services")) {
                        NavigationLink(destination: insulinDeliveryServerView) {
                            Text("Insulin Delivery Server")
                        }
                    }
                    
                    Section(header: Text("Clients")) {
                        NavigationLink(destination: insulinDeliveryClientView) {
                            Text("Insulin Delivery Client")
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
        InsulinDeliveryServerView(viewModel: insulinDeliveryServerViewModel)
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
}
