//
//  UITextField.swift
//  LoopDeviceSimulator
//
//  Created by Nathaniel Hamming on 2025-08-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import UIKit

extension UITextField {
    
    func selectAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        self.selectedTextRange = self.textRange(from: self.beginningOfDocument, to: self.endOfDocument)
    }

    func moveCursorToEnd() {
        dispatchPrecondition(condition: .onQueue(.main))
        let newPosition = self.endOfDocument
        self.selectedTextRange = self.textRange(from: newPosition, to: newPosition)
    }
    
    func moveCursorToBeginning() {
        dispatchPrecondition(condition: .onQueue(.main))
        let newPosition = self.beginningOfDocument
        self.selectedTextRange = self.textRange(from: newPosition, to: newPosition)
    }
}
