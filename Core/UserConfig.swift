//
//  UserConfig.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

enum Themes: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
class UserConfig {
    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    
    var horizontalPadding: Int {
        didSet { UserDefaults.standard.set(horizontalPadding, forKey: "horizontalPadding") }
    }
    
    var bookshelfSortOption: SortOption {
        didSet { UserDefaults.standard.set(bookshelfSortOption.rawValue, forKey: "bookshelfSortOption") }
    }
    
    var theme: Themes {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    
    var popupWidth: Int {
        didSet { UserDefaults.standard.set(popupWidth, forKey: "popupWidth") }
    }
    
    var popupHeight: Int {
        didSet { UserDefaults.standard.set(popupHeight, forKey: "popupHeight") }
    }
    
    var maxResults: Int {
        didSet { UserDefaults.standard.set(maxResults, forKey: "maxResults") }
    }
    
    var collapseDictionaries: Bool {
        didSet { UserDefaults.standard.set(collapseDictionaries, forKey: "collapseDictionaries") }
    }
    
    var enableSync: Bool {
        didSet { UserDefaults.standard.set(enableSync, forKey: "enableSync") }
    }
    
    var googleClientId: String {
        didSet { UserDefaults.standard.set(googleClientId, forKey: "googleClientId") }
    }
    
    init() {
        let defaults = UserDefaults.standard
        
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.horizontalPadding = defaults.object(forKey: "horizontalPadding") as? Int ?? 10
        self.popupWidth = defaults.object(forKey: "popupWidth") as? Int ?? 320
        self.popupHeight = defaults.object(forKey: "popupHeight") as? Int ?? 250
        self.maxResults = defaults.object(forKey: "maxResults") as? Int ?? 16
        self.collapseDictionaries = defaults.object(forKey: "collapseDictionaries") as? Bool ?? true
        
        self.enableSync = defaults.object(forKey: "enableSync") as? Bool ?? false
        self.googleClientId = defaults.object(forKey: "googleClientId") as? String ?? ""
        
        self.bookshelfSortOption = defaults.string(forKey: "bookshelfSortOption")
            .flatMap(SortOption.init) ?? .recent
        
        self.theme = defaults.string(forKey: "theme")
            .flatMap(Themes.init) ?? .system
    }
}
