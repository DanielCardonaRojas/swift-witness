//
//  String+Extensions.swift
//  Witness
//
//  Created by Daniel Cardona on 3/01/25.
//

import Foundation

extension String {
    func lowercaseFirst() -> String {
        guard let firstLetter = self.first else { return self }

        // Check if the first letter is already lowercase
        if firstLetter.isLowercase {
            return self
        }

        // Convert the first letter to lowercase and concatenate with the rest of the string
        return firstLetter.lowercased() + self.dropFirst()
    }
}
