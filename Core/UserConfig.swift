//
//  UserConfig.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

enum SyncMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case manual = "Manual"
}

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
    var bookshelfSortOption: SortOption {
        didSet { UserDefaults.standard.set(bookshelfSortOption.rawValue, forKey: "bookshelfSortOption") }
    }
    
    var maxResults: Int {
        didSet { UserDefaults.standard.set(maxResults, forKey: "maxResults") }
    }
    
    var collapseDictionaries: Bool {
        didSet { UserDefaults.standard.set(collapseDictionaries, forKey: "collapseDictionaries") }
    }
    
    var compactGlossaries: Bool {
        didSet { UserDefaults.standard.set(compactGlossaries, forKey: "compactGlossaries") }
    }
    
    var enableSync: Bool {
        didSet { UserDefaults.standard.set(enableSync, forKey: "enableSync") }
    }
    
    var syncMode: SyncMode {
        didSet { UserDefaults.standard.set(syncMode.rawValue, forKey: "syncMode") }
    }
    
    var googleClientId: String {
        didSet { UserDefaults.standard.set(googleClientId, forKey: "googleClientId") }
    }
    
    var theme: Themes {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    
    var uiTheme: Themes {
        didSet { UserDefaults.standard.set(uiTheme.rawValue, forKey: "uiTheme") }
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
    
    var verticalWriting: Bool {
        didSet { UserDefaults.standard.set(verticalWriting, forKey: "verticalWriting") }
    }
    
    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    
    var selectedFont: String {
        didSet { UserDefaults.standard.set(selectedFont, forKey: "selectedFont") }
    }
    
    var horizontalPadding: Int {
        didSet { UserDefaults.standard.set(horizontalPadding, forKey: "horizontalPadding") }
    }
    
    var verticalPadding: Int {
        didSet { UserDefaults.standard.set(verticalPadding, forKey: "verticalPadding") }
    }
    
    var readerHideFurigana: Bool {
        didSet { UserDefaults.standard.set(readerHideFurigana, forKey: "readerHideFurigana") }
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
    
    var readerShowProgressTop: Bool {
        didSet { UserDefaults.standard.set(readerShowProgressTop, forKey: "readerShowProgressTop") }
    }
    
    var popupWidth: Int {
        didSet { UserDefaults.standard.set(popupWidth, forKey: "popupWidth") }
    }
    
    var popupHeight: Int {
        didSet { UserDefaults.standard.set(popupHeight, forKey: "popupHeight") }
    }
    
    var popupSwipeToDismiss: Bool {
        didSet { UserDefaults.standard.set(popupSwipeToDismiss, forKey: "popupSwipeToDismiss") }
    }
    
    var popupSwipeThreshold: Int {
        didSet { UserDefaults.standard.set(popupSwipeThreshold, forKey: "popupSwipeThreshold") }
    }
    
    var audioSources: [AudioSource] {
        didSet {
            if let data = try? JSONEncoder().encode(audioSources) {
                UserDefaults.standard.set(data, forKey: "audioSources")
            }
        }
    }
    
    var enableLocalAudio: Bool {
        didSet {
            UserDefaults.standard.set(enableLocalAudio, forKey: "enableLocalAudio")
            if enableLocalAudio {
                audioSources.insert(UserConfig.localAudioSource, at: 0)
            } else {
                audioSources.removeAll { $0.url == LocalFileServer.localAudioURL }
            }
        }
    }
    
    var enabledAudioSources: [String] {
        audioSources.filter { $0.isEnabled }.map { $0.url }
    }
    
    static let localAudioSource = AudioSource(
        name: "Local",
        url: LocalFileServer.localAudioURL,
        isEnabled: true
    )
    
    static let defaultAudioSource = AudioSource(
        name: "Default",
        url: "https://hoshi-reader.manhhaoo-do.workers.dev/?term={term}&reading={reading}",
        isEnabled: true,
        isDefault: true
    )
    
    var customCSS: String {
        didSet {
            UserDefaults.standard.set(customCSS, forKey: "customCSS")
        }
    }
    
    var enableStatistics: Bool {
        didSet { UserDefaults.standard.set(enableStatistics, forKey: "enableStatistics") }
    }
    
    init() {
        let defaults = UserDefaults.standard
        
        self.bookshelfSortOption = defaults.string(forKey: "bookshelfSortOption")
            .flatMap(SortOption.init) ?? .recent
        
        self.maxResults = defaults.object(forKey: "maxResults") as? Int ?? 16
        self.collapseDictionaries = defaults.object(forKey: "collapseDictionaries") as? Bool ?? false
        self.compactGlossaries = defaults.object(forKey: "compactGlossaries") as? Bool ?? true
        
        self.enableSync = defaults.object(forKey: "enableSync") as? Bool ?? false
        self.syncMode = defaults.string(forKey: "syncMode")
            .flatMap(SyncMode.init) ?? .auto
        self.googleClientId = defaults.object(forKey: "googleClientId") as? String ?? ""
        
        self.theme = defaults.string(forKey: "theme")
            .flatMap(Themes.init) ?? .system
        self.uiTheme = defaults.string(forKey: "uiTheme")
            .flatMap(Themes.init) ?? .system
        self.customBackgroundColor = UserConfig.loadColor(key: "customBackgroundColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.customTextColor = UserConfig.loadColor(key: "customTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        
        self.verticalWriting = defaults.object(forKey: "verticalWriting") as? Bool ?? true
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.selectedFont = defaults.string(forKey: "selectedFont") ?? "Hiragino Mincho ProN"
        
        self.horizontalPadding = defaults.object(forKey: "horizontalPadding") as? Int ?? 10
        self.verticalPadding = defaults.object(forKey: "verticalPadding") as? Int ?? 0
        self.readerHideFurigana = defaults.object(forKey: "readerHideFurigana") as? Bool ?? false
        
        self.readerShowTitle = defaults.object(forKey: "readerShowTitle") as? Bool ?? true
        self.readerShowCharacters = defaults.object(forKey: "readerShowCharacters") as? Bool ?? true
        self.readerShowPercentage = defaults.object(forKey: "readerShowPercentage") as? Bool ?? true
        self.readerShowProgressTop = defaults.object(forKey: "readerShowProgressTop") as? Bool ?? true
        
        self.popupWidth = defaults.object(forKey: "popupWidth") as? Int ?? 320
        self.popupHeight = defaults.object(forKey: "popupHeight") as? Int ?? 250
        self.popupSwipeToDismiss = defaults.object(forKey: "popupSwipeToDismiss") as? Bool ?? false
        self.popupSwipeThreshold = defaults.object(forKey: "popupSwipeThreshold") as? Int ?? 40
        
        if let data = defaults.data(forKey: "audioSources"),
           let sources = try? JSONDecoder().decode([AudioSource].self, from: data) {
            self.audioSources = sources
        } else {
            self.audioSources = [UserConfig.defaultAudioSource]
        }
        self.enableLocalAudio = defaults.object(forKey: "enableLocalAudio") as? Bool ?? false
        self.customCSS = defaults.string(forKey: "customCSS") ?? ""
        
        self.enableStatistics = defaults.object(forKey: "enableStatistics") as? Bool ?? true
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
