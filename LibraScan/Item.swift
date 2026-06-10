//
//  Item.swift
//  LibraScan
//
//  Created by Libra Hu on 2026-06-10 19:39.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
