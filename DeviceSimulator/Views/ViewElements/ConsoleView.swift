//
//  ConsoleView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

/// Read-only log card shared by every client view.
struct ConsoleView: View {
    let title: String
    let output: String

    var body: some View {
        RoundedCard(title: title) {
            TextEditor(text: .constant(output))
                .frame(minHeight: 120)
        }
    }
}

struct ConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleView(title: "Server Console", output: "testing output")
    }
}
