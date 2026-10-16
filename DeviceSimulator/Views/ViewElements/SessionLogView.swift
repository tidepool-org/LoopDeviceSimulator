//
//  SessionLogView.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-16.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import SwiftUI

/// The session log on the device: newest first, filterable by kind, shared as the JSONL file (HYD-O-004).
struct SessionLogView: View {
    private let log = SessionLog.shared
    @State private var filter: SessionLogEntry.Kind?
    @State private var confirmClear = false

    var body: some View {
        List(entries) { entry in
            row(entry)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
        .listStyle(.plain)
        .navigationTitle("Session Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Kind", selection: $filter) {
                        Text("All kinds").tag(SessionLogEntry.Kind?.none)
                        ForEach(SessionLogEntry.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(Optional(kind))
                        }
                    }
                } label: {
                    Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                ShareLink(item: log.fileURL, preview: SharePreview("HYDRA session log"))
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Clear the session log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { log.clear() }
        } message: {
            Text("Deletes the log file on this device. Share it first if you need it.")
        }
        .safeAreaInset(edge: .bottom) {
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }

    private var entries: [SessionLogEntry] {
        guard let filter else { return log.recent }
        return log.recent.filter { $0.kind == filter }
    }

    private var footerText: String {
        let shown = filter.map { " · showing \(entries.count) \($0.rawValue)" } ?? ""
        return "\(log.entryCount) entries · \(log.fileSizeDescription)\(shown)"
    }

    private func row(_ entry: SessionLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(entry.timestamp.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3))))
                    .font(.caption.monospacedDigit())
                Text(entry.kind.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(tint(for: entry.kind).opacity(0.18), in: Capsule())
                Text("\(entry.mode.rawValue) \(entry.role.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(entry.detail)
                .font(.caption.monospaced())
                .lineLimit(4)
        }
    }

    private func tint(for kind: SessionLogEntry.Kind) -> Color {
        switch kind {
        case .connection: return .blue
        case .read: return .teal
        case .write: return .indigo
        case .notify: return .green
        case .indicate: return .mint
        case .stimulus: return .orange
        case .lifecycle: return .purple
        case .trace: return .gray
        case .error: return .red
        }
    }
}

struct SessionLogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SessionLogView()
        }
    }
}
