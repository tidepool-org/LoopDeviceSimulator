//
//  CustomInsetGroupedListStyle.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

extension View {
    public func insetGroupedListStyle() -> some View {
        modifier(CustomInsetGroupedListStyle())
    }
}

fileprivate struct CustomInsetGroupedListStyle: ViewModifier, HorizontalSizeClassOverride {
    @ViewBuilder func body(content: Content) -> some View {
        // For compact sizes (e.g. iPod Touch), don't inset, in order to more efficiently utilize limited real estate
        if horizontalOverride == .compact {
            content
                .listStyle(GroupedListStyle())
                .environment(\.horizontalSizeClass, horizontalOverride)
        } else {
            content
                .listStyle(InsetGroupedListStyle())
                .environment(\.horizontalSizeClass, horizontalOverride)
        }
    }
}
