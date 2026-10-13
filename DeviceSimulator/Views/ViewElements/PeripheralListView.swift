//
//  PeripheralListView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import CoreBluetooth

struct MessageView: View {
    let message: String

    var body: some View {
        RoundedCardRowInstructions(message)
            .font(.callout)
            .foregroundColor(.gray)
    }
}

struct DeviceView: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading) {
            Text(device.name)
            Group {
                Text(device.advertisedName)
                Text(device.uuid)
            }
            .font(.callout)
            .foregroundColor(.gray)
        }
    }
}

struct Device: Hashable {
    var name: String
    var uuid: String
    var advertisedName: String
    var rssi: NSNumber
    var serviceData: [CBUUID: Data]?
}

/// Discovered-peripheral list shared by the test clients: refresh, prompt, one card per device.
struct DeviceListView: View {
    let title: String
    let prompt: String
    let devices: [Device]
    let onRefresh: () -> Void
    let onSelect: (Device) -> Void

    var body: some View {
        RoundedCardScrollView(title: title) {
            RoundedCard {
                Button(action: onRefresh) {
                    Text("Refresh List")
                    Spacer()
                }
            }
            Text(prompt)
            ForEach(devices, id: \.self) { device in
                RoundedCard {
                    Button(action: { onSelect(device) }) {
                        DeviceView(device: device)
                    }
                }
            }
        }
    }
}
