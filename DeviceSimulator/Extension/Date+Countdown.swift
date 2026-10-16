//
//  Date+Countdown.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-15.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation

extension Date {
    /// "in 2 min 17 s" or "in 42 s" until this date, rounded up so the final second still reads "in 1 s".
    func countdown(from now: Date) -> String {
        let remaining = max(0, Int(timeIntervalSince(now).rounded(.up)))
        return remaining >= 60 ? "in \(remaining / 60) min \(remaining % 60) s" : "in \(remaining) s"
    }
}
