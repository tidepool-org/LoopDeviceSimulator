//
//  Device_SimulatorApp.swift
//  Device Simulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import BluetoothCommonKit

@main
struct Device_SimulatorApp: App, HorizontalSizeClassOverride {
    private var insulinDeliveryServiceViewModel = InsulinDeliveryServiceViewModel()

    @State private var _insulinDeliveryServiceViewActive = false
    @State private var serverName: String = InsulinDeliveryConstants.serverName

    private var insulinDeliveryServiceViewActive: Binding<Bool> {
        Binding(
            get: { _insulinDeliveryServiceViewActive },
            set: { viewActive in
                _insulinDeliveryServiceViewActive = viewActive
                if viewActive {
                    // Initialize the console
                    ConsoleOut.shared.delegate = insulinDeliveryServiceViewModel

                    // Initialize Elapsed Time Service
                    insulinDeliveryServiceViewModel.startServer(serverName: serverName)
                } else {
                    insulinDeliveryServiceViewModel.stopServer()
                }
            }
        )
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    HStack {
                        TextField("Server Name", text: $serverName)
                    }
                    NavigationLink(destination: insulinDeliveryServiceView,
                                   isActive: insulinDeliveryServiceViewActive) {
                        Text("Insulin Delivery Service")
                    }
                }
                .navigationTitle("Services \(Bundle.main.fullVersionString)")
            }
        }
    }
    
    private var insulinDeliveryServiceView: some View {
        InsulinDeliveryServiceView(viewModel: insulinDeliveryServiceViewModel)
            .environment(\.horizontalSizeClass, horizontalOverride)
    }
}
