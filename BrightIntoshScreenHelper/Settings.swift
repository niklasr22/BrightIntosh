//
//  Settings.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 04.04.26.
//

import Foundation

extension UserDefaults {
    @objc dynamic var active: Bool {
        return bool(forKey: "active")
    }
    
    @objc dynamic var brightness: Float {
        return float(forKey: "brightness")
    }
    
    @objc dynamic var helpers: String? {
        return string(forKey: "helpers")
    }
}

