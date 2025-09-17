//
//  AuthorizationControlClientView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import BluetoothCommonKit

struct AuthorizationControlClientView: View {
    @ObservedObject var viewModel: AuthorizationControlClientViewModel
    
    var body: some View {
        if viewModel.isPeripheralConnected {
            VStack {
                RoundedCardScrollView(title: "Authorization Control") {
                    RoundedCard {
                        Button(action: viewModel.stopClient) {
                            Text(viewModel.connectedMessage)
                            Spacer()
                        }
                        Divider()
                        Button(action: viewModel.switchToPeripheralList) {
                            Text("Display Peripheral List")
                            Spacer()
                        }
                        Divider()
                        Button(action: viewModel.clearConsole) {
                            Text("Clear Console")
                            Spacer()
                        }
                    }
                    
                    configurationControls
                    
                    readCharacteristics
                    
                    controlPointControls
                    
                    secureRequestControls
                    
                    RoundedCard(title: "Console") {
                        TextEditor(text: .constant(viewModel.consoleMessages))
                    }
                }
            }
        } else {
            deviceList
        }
    }
    
    @ViewBuilder
    private var configurationControls: some View {
        RoundedCard(title: "Configure Indications/Notifications") {
            Toggle("Configure Status", isOn: $viewModel.indicationsEnabledStatus)
            Toggle("Configure Control Point", isOn: $viewModel.indicationsEnabledControlPoint)
            Toggle("Configure Data Out Notify", isOn: $viewModel.indicationsEnabledDataOutNotify)
            Toggle("Configure Data Out Indicate", isOn: $viewModel.indicationsEnabledDataOutIndicate)
            if viewModel.indicationsEnabledMessageStatus != nil ||
                viewModel.indicationsEnabledMessageControlPoint != nil ||
                viewModel.indicationsEnabledMessageDataOutNotify != nil ||
                viewModel.indicationsEnabledMessageDataOutIndicate != nil
            {
                MessageView(message: "Status: \(String(describing: viewModel.indicationsEnabledMessageStatus)) Control Point: \(String(describing: viewModel.indicationsEnabledMessageControlPoint))  Data Out Notify: \(String(describing: viewModel.indicationsEnabledMessageDataOutNotify)) Data Out Indicate: \(String(describing: viewModel.indicationsEnabledMessageDataOutIndicate))")
            }
        }
    }
    
    @ViewBuilder
    private var readCharacteristics: some View {
        RoundedCard {
            VStack {
                readACStatusCharacteristic
            }
        }
    }
            
    private var readACStatusCharacteristic: some View {
        VStack {
            Button(action: viewModel.readACStatusCharacteristic) {
                Text("Read AC Status Characteristic")
            }
            .padding()
            if let message = viewModel.readMessageACStatusCharacteristic {
                MessageView(message: message)
            }
            if let message = viewModel.indicationsMessageStatus {
                MessageView(message: message)
            }
        }
    }
    
    private var controlPointControls: some View {
        RoundedCard(title: "AC Control Point") {
            getACSFeatures
            getAllActiveDescriptors
            getResourceHandleToUUIDMap
            getRestrictionMapIDList
            getATTMTU
            setClientNonceFixed
            invalidateKey
            startKeyExchange
            keyExchangeECDH
            keyExchangeKDF
            ecdhConfirmationCode
            ecdhConfirmationRandomNumber
        }
    }
    
    private var getACSFeatures: some View {
        VStack {
            Button(action: viewModel.getACSFeatures) {
                Text("Get ACS Features")
            }
            if let message = viewModel.getACSFeaturesMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getAllActiveDescriptors: some View {
        VStack {
            Divider()
            Button(action: viewModel.getAllActiveDescriptors) {
                Text("Get All Active Descriptors")
            }
            if let message = viewModel.getAllActiveDescriptorsMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getResourceHandleToUUIDMap: some View {
        VStack {
            Divider()
            Button(action: viewModel.getResourceHandleToUUIDMap) {
                Text("Get Resource Handle To UUID Map")
            }
            if let message = viewModel.getResourceHandleToUUIDMapMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getRestrictionMapIDList: some View {
        VStack {
            Divider()
            Button(action: viewModel.getRestrictionMapIDList) {
                Text("Get Restriction Map ID List")
            }
            if let message = viewModel.getRestrictionMapIDListMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var getATTMTU: some View {
        VStack {
            Divider()
            Button(action: viewModel.getATTMTU) {
                Text("Get ATT MTU")
            }
            if let message = viewModel.getATTMTUMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var setClientNonceFixed: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.algorithmKeyIDString)
            }
            Button(action: viewModel.setClientNonceFixed) {
                Text("Set Client Nonce Fixed")
            }
            if let message = viewModel.setClientNonceFixedMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var invalidateKey: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }

            Button(action: viewModel.invalidateKey) {
                Text("Invalidate Key")
            }
            if let message = viewModel.invalidateKeyMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var startKeyExchange: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }
            Button(action: viewModel.startKeyExchange) {
                Text("Start Key Exchange")
            }
            if let message = viewModel.startKeyExchangeMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var keyExchangeECDH: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }
            Button(action: viewModel.keyExchangeECDH) {
                Text("Key Exchange ECDH")
            }
            if let message = viewModel.keyExchangeECDHMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var keyExchangeKDF: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                Spacer()
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }
            Button(action: viewModel.keyExchangeKDF) {
                Text("Key Exchange KDF")
            }
            if let message = viewModel.keyExchangeKDFMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var ecdhConfirmationCode: some View {
        VStack {
            Divider()
            HStack {
                Text("Key ID")
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }
            HStack {
                Text("OOB Number")
                NumberEntryEntryView(title: "Enter OOB Number", number: $viewModel.oobRandomNumberString)
            }
            Button(action: viewModel.ecdhConfirmationCode) {
                Text("ECDH Confirmation Code")
            }
            if let message = viewModel.ecdhConfirmationCodeMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var ecdhConfirmationRandomNumber: some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                Text("Key ID")
                NumberEntryEntryView(title: "Enter Key ID", number: $viewModel.ecdhKeyIDString)
            }
            Button(action: viewModel.ecdhConfirmationRandomNumber) {
                Text("ECDH Confirmation Random Number")
            }
            if let message = viewModel.ecdhConfirmationRandomNumberMessage {
                MessageView(message: message)
            }
        }
    }
    
    private var secureRequestControls: some View {
        RoundedCard(title: "Secure Request") {
            VStack {
                Button(action: viewModel.sendSecureRequest) {
                    Text("Send secure request")
                }
                if let message = viewModel.sendSecureRequestMessage {
                    MessageView(message: message)
                }
            }
        }
    }
    
    struct NumberEntryEntryView: View {
        let title: String
        @Binding var number: String

        var body: some View {
            DismissibleKeyboardTextField(
                text: $number,
                placeholder: title,
                font: .preferredFont(forTextStyle: .headline),
                textColor: .blue,
                textAlignment: .right,
                keyboardType: .decimalPad,
                shouldBecomeFirstResponder: false,
                maxLength: 5,
                doneButtonColor: UIColor(Color.accentColor),
                textFieldDidBeginEditing: nil
            )
        }
    }
    
    @ViewBuilder
    private var deviceList: some View {
        RoundedCardScrollView(title: "Discovered Peripherals") {
            RoundedCard() {
                Button(action: viewModel.refreshList) {
                    Text("Refresh List")
                    Spacer()
                }
            }
            Text("Select Authorization Control Service to connect")
            ForEach(viewModel.deviceList, id:\.self) { device in
                RoundedCard() {
                    Button(action: { viewModel.connectToDevice(device) }) {
                        DeviceView(device: device)
                    }
                }
            }
        }
    }
}

struct AuthorizationControlClientView_Previews: PreviewProvider {
    static var previews: some View {
        AuthorizationControlClientView(viewModel: AuthorizationControlClientViewModel())
    }
}
