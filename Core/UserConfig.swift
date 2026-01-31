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
    case sepia = "Sepia"
    case custom = "Custom"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .sepia: .light
        default: nil
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
    
    var verticalPadding: Int {
        didSet { UserDefaults.standard.set(verticalPadding, forKey: "verticalPadding") }
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
    
    var verticalWriting: Bool {
        didSet { UserDefaults.standard.set(verticalWriting, forKey: "verticalWriting") }
    }
    
    var googleClientId: String {
        didSet { UserDefaults.standard.set(googleClientId, forKey: "googleClientId") }
    }
    
    var uiTheme: Themes {
        didSet { UserDefaults.standard.set(uiTheme.rawValue, forKey: "uiTheme") }
    }
    
    var readerShowProgressTop: Bool {
        didSet { UserDefaults.standard.set(readerShowProgressTop, forKey: "readerShowProgressTop") }
    }
    
    var readerShowTitle: Bool {
        didSet { UserDefaults.standard.set(readerShowTitle, forKey: "readerShowTitle") }
    }
    
    var readerShowCharacters: Bool {
        didSet { UserDefaults.standard.set(readerShowCharacters, forKey: "readerShowCharacters") }
    }
    
    var readerShowPercentage: Bool {
        didSet { UserDefaults.standard.set(readerShowPercentage, forKey: "readerShowPercentage") }
    }
    
    var customBackgroundColor: Color {
        didSet {
            Self.saveColor(customBackgroundColor, key: "customBackgroundColor")
        }
    }
    
    var customTextColor: Color {
        didSet {
            Self.saveColor(customTextColor, key: "customTextColor")
        }
    }
    
    var selectedFont: String {
        didSet { UserDefaults.standard.set(selectedFont, forKey: "selectedFont") }
    }
    
    init() {
        let defaults = UserDefaults.standard
        
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.horizontalPadding = defaults.object(forKey: "horizontalPadding") as? Int ?? 10
        self.verticalPadding = defaults.object(forKey: "verticalPadding") as? Int ?? 0
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
        
        self.uiTheme = defaults.string(forKey: "uiTheme")
            .flatMap(Themes.init) ?? .system
        
        self.customBackgroundColor = UserConfig.loadColor(key: "customBackgroundColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.customTextColor = UserConfig.loadColor(key: "customTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        
        self.selectedFont = defaults.string(forKey: "selectedFont") ?? "Hiragino Mincho ProN"
        
        self.verticalWriting = defaults.object(forKey: "verticalWriting") as? Bool ?? true
        
        self.readerShowProgressTop = defaults.object(forKey: "readerShowProgressTop") as? Bool ?? true
        self.readerShowTitle = defaults.object(forKey: "readerShowTitle") as? Bool ?? true
        self.readerShowCharacters = defaults.object(forKey: "readerShowCharacters") as? Bool ?? true
        self.readerShowPercentage = defaults.object(forKey: "readerShowPercentage") as? Bool ?? true
    }
    
    private static func saveColor(_ color: Color, key: String) {
        let uiColor = UIColor(color)
        let colorData = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)
        UserDefaults.standard.set(colorData, forKey: key)
    }
    
    private static func loadColor(key: String) -> Color? {
        guard let colorData = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            return Color(uiColor)
        }
        return nil
    }
}
