//
//  HorizontalSizeClassOverride.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-08.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

protocol HorizontalSizeClassOverride {
    var horizontalOverride: UserInterfaceSizeClass { get }
}

extension HorizontalSizeClassOverride {
    var horizontalOverride: UserInterfaceSizeClass {
        if UIScreen.main.bounds.height <= 640 {
            return .compact
        } else {
            return .regular
        }
    }
}

