//
//  String+Numbers.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2026-10-13.
//  Copyright © 2026 Tidepool Project. All rights reserved.
//

import Foundation

extension String {
    /// Parses a tester-typed number, accepting the device locale's decimal separator (e.g. "1,5") as well as
    /// a plain "1.5". Whitespace around the value is ignored.
    var parsedDouble: Double? {
        let text = trimmingCharacters(in: .whitespaces)
        if let value = Double(text) { return value }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        return formatter.number(from: text)?.doubleValue
    }
}

extension Double {
    /// Whole values print without a fraction ("120"), others as-is; values outside Int's range or
    /// non-finite ones fall back to the plain description instead of trapping.
    var compactDescription: String {
        if isFinite, self == rounded(), let whole = Int(exactly: self) {
            return String(whole)
        }
        return String(self)
    }
}
