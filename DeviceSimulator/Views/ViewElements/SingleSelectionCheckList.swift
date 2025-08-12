//
//  SingleSelectionCheckList.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

public struct SingleSelectionCheckList<Item: Hashable & CustomStringConvertible>: View {
    let items: [Item]
    @Binding var selectedItem: Item

    public init(items: [Item],
                selectedItem: Binding<Item>) {
        self.items = items
        _selectedItem = selectedItem
    }

    public var body: some View {
        VStack(spacing: 12) {
            ForEach(items, id:\.self) { item in
                CheckSelectionRow<Item>(item: item,
                                        selectedItem: self.$selectedItem)
            }
        }
    }
}

struct CheckSelectionRow<Item>: View where Item: Hashable & CustomStringConvertible {
    var item: Item
    @Binding var selectedItem: Item

    var isSelected: Bool {
        selectedItem == item
    }

    var body: some View {
        HStack {
            Button(action: { selectedItem = item } ) {
                Text(String(describing: item))
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

struct SingleSelectionCheckList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapper()
    }

    struct PreviewWrapper: View {
        enum Shape: Int, CaseIterable, CustomStringConvertible {
            case square
            case circle
            case triangle
            case rectangle

            var description: String {
                switch self {
                case .square:
                    return "Square"
                case .circle:
                    return "Circle"
                case .triangle:
                    return "Triangle"
                case .rectangle:
                    return "Rectangle"
                }
            }
        }
        @State var selectedFruit: Shape = .square

        var body: some View {
            SingleSelectionCheckList<Shape>(items: Shape.allCases,
                                            selectedItem: $selectedFruit)
        }
    }
}
