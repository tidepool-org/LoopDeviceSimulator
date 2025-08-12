//
//  ContentPreview.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct ContentPreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            content
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPod touch (7th generation)"))
                .previewDisplayName("iPod touch (7th generation) - Light")
            content
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (2nd generation)"))
                .previewDisplayName("iPhone SE (2nd generation) - Light")
            content
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 12 Pro Max"))
                .previewDisplayName("iPhone 12 Pro Max - Dark")
        }
    }
}

struct ContentPreviewWithBackground<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ContentPreview {
            ZStack {
                Color(.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                ScrollView {
                    content
                }
                .padding()
            }
        }
    }
}
