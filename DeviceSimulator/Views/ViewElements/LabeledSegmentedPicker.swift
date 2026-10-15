//
//  LabeledSegmentedPicker.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-14.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI

/// A segmented picker over every case of an option type. The segmented style hides the picker's own title,
/// so the label sits above the control.
struct LabeledSegmentedPicker<Option: Hashable & CaseIterable & CustomStringConvertible>: View {
    let label: String
    @Binding var selection: Option

    init(_ label: String, selection: Binding<Option>) {
        self.label = label
        self._selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            Picker(label, selection: $selection) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}
