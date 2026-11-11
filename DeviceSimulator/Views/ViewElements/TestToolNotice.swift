//
//  TestToolNotice.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-11-10.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//
//  The simulator must never be mistaken for a medical device, and the pump it presents must never be
//  taken for one that delivers insulin. A bar on every screen says so; tapping it opens the full wording.

import SwiftUI

enum TestToolNotice {
    static let short = "Test tool, not a medical device. Simulated pump and CGM only; no insulin is delivered."

    static let paragraphs: [String] = [
        "This application is a software test tool for engineers and testers working on Tidepool Loop. It is not a medical device and must not be used to make treatment decisions.",
        "The pump it presents over Bluetooth is a simulation. It cannot command, and is not connected to, any physical infusion pump. No insulin is delivered by this tool under any circumstances.",
        "The CGM it presents over Bluetooth is a simulation. Its glucose values are generated from scenarios, curves and constants chosen by the tester and bear no relation to any person's glucose.",
        "Values shown by this tool, or by an app connected to it, are test data only.",
    ]
}

/// The persistent bar: one line, readable at a glance, tappable for the full text.
struct TestToolNoticeBar: View {
    @State private var isShowingTerms = false

    var body: some View {
        Button {
            isShowingTerms = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(TestToolNotice.short)
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.yellow.opacity(0.18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Test tool notice. \(TestToolNotice.short)")
        .sheet(isPresented: $isShowingTerms) {
            TermsOfUseView()
        }
    }
}

struct TermsOfUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Test tool, not a medical device", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(TestToolNotice.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.body)
                    }
                    Divider()
                    Text("Simulator version \(Bundle.main.fullVersionString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension View {
    /// Pins the test-tool bar to the bottom of the screen, under whatever this view shows.
    func testToolNotice() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            TestToolNoticeBar()
        }
    }
}

#Preview {
    NavigationStack {
        List { Text("Content") }
            .navigationTitle("Simulator")
    }
    .testToolNotice()
}
