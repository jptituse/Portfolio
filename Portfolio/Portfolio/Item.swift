//
//  Item.swift
//  Portfolio
//
//  Created by Waynar Bocangel on 11/7/26.
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
