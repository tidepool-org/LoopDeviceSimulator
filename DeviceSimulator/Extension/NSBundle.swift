//
//  NSBundle.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

extension Bundle {
    var fullVersionString: String {
        return "\(shortVersionString) (\(version))"
    }

    var shortVersionString: String {
        return object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }

    var version: String {
        return object(forInfoDictionaryKey: "CFBundleVersion") as! String
    }
}
