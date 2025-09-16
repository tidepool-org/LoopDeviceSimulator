//
//  NumberEntryEntryView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-09-16.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

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
