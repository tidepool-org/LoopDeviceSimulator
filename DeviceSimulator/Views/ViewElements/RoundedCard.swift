//
//  RoundedCard.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

fileprivate let inset: CGFloat = 16

struct RoundedCardTitle: View {
    var title: String
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
            .padding(.leading, titleInset)
    }

    private var isCompact: Bool {
        return self.horizontalSizeClass == .compact
    }

    private var titleInset: CGFloat {
        return isCompact ? inset : 0
    }
}

struct RoundedCardRowInstructions: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
    }
}

struct RoundedCardFooter: View {
    var text: String
    var alignment: HorizontalAlignment

    init(_ text: String, alignment: HorizontalAlignment = .leading, inset footerInset: CGFloat? = nil) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        RoundedCardRowInstructions(text)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.horizontal, inset)
    }
}

public struct RoundedCardValueRow: View {
    var label: String
    var value: String
    var highlightValue: Bool
    var highlightColor: Color
    var disclosure: Bool

    public init(label: String, value: String, highlightValue: Bool = false, highlightColor: Color = .accentColor, disclosure: Bool = false) {
        self.label = label
        self.value = value
        self.highlightValue = highlightValue
        self.highlightColor = highlightColor
        self.disclosure = disclosure
    }

    public var body: some View {
        HStack {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(highlightValue ? highlightColor : .secondary)
                .multilineTextAlignment(.leading)
            if disclosure {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
        }
    }
}

public struct RoundedCardToggleRow: View {
    var label: String
    @Binding var enabled: Bool
    let toggleTintColor: Color

    public var body: some View {
        Toggle(isOn: $enabled) {
           Text(label)
        }
        .toggleStyle(SwitchToggleStyle(tint: toggleTintColor))
    }
}

struct RoundedCard<Content: View>: View {
    var content: () -> Content?
    var alignment: HorizontalAlignment
    var title: String?
    var footer: String?
    var backgroundColor: Color
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(title: String? = nil, footer: String? = nil, alignment: HorizontalAlignment = .leading, backgroundColor: Color = Color(.secondarySystemGroupedBackground), @ViewBuilder content: @escaping () -> Content? = { nil }) {
        self.content = content
        self.alignment = alignment
        self.title = title
        self.footer = footer
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        VStack(spacing: 10) {
            if let title = title {
                RoundedCardTitle(title)
            }

            if content() != nil {
                if isCompact {
                    VStack(spacing: 0) {
                        borderLine
                        VStack(alignment: alignment, content: content)
                            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                            .padding(inset)
                            .background(backgroundColor)
                        borderLine
                    }
                } else {
                    VStack(alignment: alignment, content: content)
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                        .padding(.horizontal, inset)
                        .padding(.vertical, 10)
                        .background(backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }

            if let footer = footer {
                RoundedCardFooter(footer)
            }
        }
    }

    var borderLine: some View {
        Rectangle().fill(Color(.quaternaryLabel))
            .frame(height: 0.5)
    }

    private var isCompact: Bool {
        return self.horizontalSizeClass == .compact
    }

    private var padding: CGFloat {
        return isCompact ? 0 : inset
    }

    private var cornerRadius: CGFloat {
        return isCompact ? 0 : 8
    }

}

struct RoundedCardScrollView<Content: View>: View {
    var content: () -> Content
    var title: String?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ScrollView {
            if let title = title {
                HStack {
                    Text(title)
                        .font(Font.largeTitle.weight(.bold))
                        .padding(.top)
                    Spacer()
                }
                .padding([.leading, .trailing])
                .navigationBarTitleDisplayMode(.inline)
            }
            VStack(alignment: .leading, spacing: 25, content: content)
                .padding(padding)
        }
        .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
    }

    private var padding: CGFloat {
        return self.horizontalSizeClass == .regular ? inset : 0
    }

}


