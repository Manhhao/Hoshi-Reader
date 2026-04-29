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

enum AudioPlaybackMode: String, CaseIterable, Codable {
    case interrupt = "interrupt"
    case duck = "duck"
    case mix = "mix"
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
    
    var bookshelfShowReading: Bool {
        didSet { UserDefaults.standard.set(bookshelfShowReading, forKey: "bookshelfShowReading") }
    }
    
    var dictionaryTabDefault: Bool {
        didSet { UserDefaults.standard.set(dictionaryTabDefault, forKey: "dictionaryTabDefault") }
    }
    
    var maxResults: Int {
        didSet { UserDefaults.standard.set(maxResults, forKey: "maxResults") }
    }
    
    var scanLength: Int {
        didSet { UserDefaults.standard.set(scanLength, forKey: "scanLength") }
    }
    
    var collapseDictionaries: Bool {
        didSet { UserDefaults.standard.set(collapseDictionaries, forKey: "collapseDictionaries") }
    }
    
    var compactGlossaries: Bool {
        didSet { UserDefaults.standard.set(compactGlossaries, forKey: "compactGlossaries") }
    }
    
    var showExpressionTags: Bool {
        didSet { UserDefaults.standard.set(showExpressionTags, forKey: "showExpressionTags") }
    }
    
    var harmonicFrequency: Bool {
        didSet { UserDefaults.standard.set(harmonicFrequency, forKey: "harmonicFrequency") }
    }
    
    var deduplicatePitchAccents: Bool {
        didSet { UserDefaults.standard.set(deduplicatePitchAccents, forKey: "deduplicatePitchAccents") }
    }
    
    var enableSync: Bool {
        didSet { UserDefaults.standard.set(enableSync, forKey: "enableSync") }
    }
    
    var syncMode: SyncMode {
        didSet { UserDefaults.standard.set(syncMode.rawValue, forKey: "syncMode") }
    }
    
    var enableAutoSync: Bool {
        didSet { UserDefaults.standard.set(enableAutoSync, forKey: "enableAutoSync") }
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
    
    var systemLightSepia: Bool {
        didSet { UserDefaults.standard.set(systemLightSepia, forKey: "systemLightSepia") }
    }
    
    var sepiaInvertInDark: Bool {
        didSet { UserDefaults.standard.set(sepiaInvertInDark, forKey: "sepiaInvertInDark") }
    }
    
    var customBackgroundColor: Color {
        didSet { Self.saveColor(customBackgroundColor, key: "customBackgroundColor") }
    }
    
    var customTextColor: Color {
        didSet { Self.saveColor(customTextColor, key: "customTextColor") }
    }
    
    var customInfoColor: Color {
        didSet { Self.saveColor(customInfoColor, key: "customInfoColor") }
    }
    
    var verticalWriting: Bool {
        didSet { UserDefaults.standard.set(verticalWriting, forKey: "verticalWriting") }
    }
    
    var selectedFont: String {
        didSet { UserDefaults.standard.set(selectedFont, forKey: "selectedFont") }
    }
    
    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    
    var readerHideFurigana: Bool {
        didSet { UserDefaults.standard.set(readerHideFurigana, forKey: "readerHideFurigana") }
    }
    
    var continuousMode: Bool {
        didSet { UserDefaults.standard.set(continuousMode, forKey: "continuousMode") }
    }
    
    var chapterSwipeDistance: Int {
        didSet { UserDefaults.standard.set(chapterSwipeDistance, forKey: "chapterSwipeDistance") }
    }
    
    var horizontalPadding: Int {
        didSet { UserDefaults.standard.set(horizontalPadding, forKey: "layoutHorizontalPadding") }
    }
    
    var verticalPadding: Int {
        didSet { UserDefaults.standard.set(verticalPadding, forKey: "layoutVerticalPadding") }
    }
    
    var avoidPageBreak: Bool {
        didSet { UserDefaults.standard.set(avoidPageBreak, forKey: "avoidPageBreak") }
    }
    
    var justifyText: Bool {
        didSet { UserDefaults.standard.set(justifyText, forKey: "justifyText") }
    }
    
    var layoutAdvanced: Bool {
        didSet { UserDefaults.standard.set(layoutAdvanced, forKey: "layoutAdvanced") }
    }
    
    var lineHeight: Double {
        didSet { UserDefaults.standard.set(lineHeight, forKey: "lineHeight") }
    }
    
    var characterSpacing: Double {
        didSet { UserDefaults.standard.set(characterSpacing, forKey: "characterSpacing") }
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
    
    var readerShowStatisticsToggle: Bool {
        didSet { UserDefaults.standard.set(readerShowStatisticsToggle, forKey: "readerShowStatisticsToggle") }
    }
    
    var readerShowReadingSpeed: Bool {
        didSet { UserDefaults.standard.set(readerShowReadingSpeed, forKey: "readerShowReadingSpeed") }
    }
    
    var readerShowReadingTime: Bool {
        didSet { UserDefaults.standard.set(readerShowReadingTime, forKey: "readerShowReadingTime") }
    }
    
    var readerShowSasayakiToggle: Bool {
        didSet { UserDefaults.standard.set(readerShowSasayakiToggle, forKey: "readerShowSasayakiToggle") }
    }
    
    var popupWidth: Int {
        didSet { UserDefaults.standard.set(popupWidth, forKey: "popupWidth") }
    }
    
    var popupHeight: Int {
        didSet { UserDefaults.standard.set(popupHeight, forKey: "popupHeight") }
    }
    
    var popupFullWidth: Bool {
        didSet { UserDefaults.standard.set(popupFullWidth, forKey: "popupFullWidth") }
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
    
    var audioEnableAutoplay: Bool {
        didSet { UserDefaults.standard.set(audioEnableAutoplay, forKey: "audioEnableAutoplay") }
    }
    
    var audioPlaybackMode: AudioPlaybackMode {
        didSet { UserDefaults.standard.set(audioPlaybackMode.rawValue, forKey: "audioPlaybackMode") }
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
        didSet { UserDefaults.standard.set(customCSS, forKey: "customCSS") }
    }
    
    var enableStatistics: Bool {
        didSet { UserDefaults.standard.set(enableStatistics, forKey: "enableStatistics") }
    }
    
    var statisticsEnableSync: Bool {
        didSet { UserDefaults.standard.set(statisticsEnableSync, forKey: "statisticsEnableSync") }
    }
    
    var statisticsSyncMode: StatisticsSyncMode {
        didSet { UserDefaults.standard.set(statisticsSyncMode.rawValue, forKey: "statisticsSyncMode") }
    }
    
    var statisticsAutostartMode: StatisticsAutostartMode {
        didSet { UserDefaults.standard.set(statisticsAutostartMode.rawValue, forKey: "statisticsAutostartMode") }
    }
    
    var enableSasayaki: Bool {
        didSet { UserDefaults.standard.set(enableSasayaki, forKey: "enableSasayaki") }
    }
    
    var sasayakiAutoScroll: Bool {
        didSet { UserDefaults.standard.set(sasayakiAutoScroll, forKey: "sasayakiAutoScroll") }
    }
    
    var sasayakiAutoPause: Bool {
        didSet { UserDefaults.standard.set(sasayakiAutoPause, forKey: "sasayakiAutoPause") }
    }
    
    var sasayakiEnableSync: Bool {
        didSet { UserDefaults.standard.set(sasayakiEnableSync, forKey: "sasayakiEnableSync") }
    }
    
    var sasayakiTextColor: Color {
        didSet { Self.saveColor(sasayakiTextColor, key: "sasayakiTextColor") }
    }
    
    var sasayakiBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiBackgroundColor, key: "sasayakiBackgroundColor") }
    }
    
    var sasayakiDarkTextColor: Color {
        didSet { Self.saveColor(sasayakiDarkTextColor, key: "sasayakiDarkTextColor") }
    }
    
    var sasayakiDarkBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiDarkBackgroundColor, key: "sasayakiDarkBackgroundColor") }
    }
    
    init() {
        let defaults = UserDefaults.standard
        
        self.bookshelfSortOption = defaults.string(forKey: "bookshelfSortOption")
            .flatMap(SortOption.init) ?? .recent
        self.bookshelfShowReading = defaults.object(forKey: "bookshelfShowReading") as? Bool ?? false
        
        self.dictionaryTabDefault = defaults.object(forKey: "dictionaryTabDefault") as? Bool ?? false
        self.maxResults = defaults.object(forKey: "maxResults") as? Int ?? 16
        self.scanLength = defaults.object(forKey: "scanLength") as? Int ?? 16
        self.collapseDictionaries = defaults.object(forKey: "collapseDictionaries") as? Bool ?? false
        self.compactGlossaries = defaults.object(forKey: "compactGlossaries") as? Bool ?? true
        self.showExpressionTags = defaults.object(forKey: "showExpressionTags") as? Bool ?? false
        self.harmonicFrequency = defaults.object(forKey: "harmonicFrequency") as? Bool ?? false
        self.deduplicatePitchAccents = defaults.object(forKey: "deduplicatePitchAccents") as? Bool ?? false
        
        self.enableSync = defaults.object(forKey: "enableSync") as? Bool ?? false
        self.syncMode = defaults.string(forKey: "syncMode")
            .flatMap(SyncMode.init) ?? .auto
        self.enableAutoSync = defaults.object(forKey: "enableAutoSync") as? Bool ?? false
        self.googleClientId = defaults.object(forKey: "googleClientId") as? String ?? ""
        
        self.theme = defaults.string(forKey: "theme")
            .flatMap(Themes.init) ?? .system
        self.uiTheme = defaults.string(forKey: "uiTheme")
            .flatMap(Themes.init) ?? .system
        self.systemLightSepia = defaults.object(forKey: "systemLightSepia") as? Bool ?? false
        self.sepiaInvertInDark = defaults.object(forKey: "sepiaInvertInDark") as? Bool ?? false
        self.customBackgroundColor = UserConfig.loadColor(key: "customBackgroundColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.customTextColor = UserConfig.loadColor(key: "customTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.customInfoColor = UserConfig.loadColor(key: "customInfoColor") ?? Color(.sRGB, red: 0.6, green: 0.6, blue: 0.6)
        
        self.verticalWriting = defaults.object(forKey: "verticalWriting") as? Bool ?? true
        self.selectedFont = defaults.string(forKey: "selectedFont") ?? "Hiragino Mincho ProN"
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.readerHideFurigana = defaults.object(forKey: "readerHideFurigana") as? Bool ?? false
        
        self.continuousMode = defaults.object(forKey: "continuousMode") as? Bool ?? false
        self.chapterSwipeDistance = defaults.object(forKey: "chapterSwipeDistance") as? Int ?? 20
        self.horizontalPadding = defaults.object(forKey: "layoutHorizontalPadding") as? Int ?? 5
        self.verticalPadding = defaults.object(forKey: "layoutVerticalPadding") as? Int ?? 0
        self.avoidPageBreak = defaults.object(forKey: "avoidPageBreak") as? Bool ?? false
        self.justifyText = defaults.object(forKey: "justifyText") as? Bool ?? false
        self.layoutAdvanced = defaults.object(forKey: "layoutAdvanced") as? Bool ?? false
        self.lineHeight = defaults.object(forKey: "lineHeight") as? Double ?? 1.65
        self.characterSpacing = defaults.object(forKey: "characterSpacing") as? Double ?? 0
        
        self.readerShowTitle = defaults.object(forKey: "readerShowTitle") as? Bool ?? true
        self.readerShowCharacters = defaults.object(forKey: "readerShowCharacters") as? Bool ?? true
        self.readerShowPercentage = defaults.object(forKey: "readerShowPercentage") as? Bool ?? true
        self.readerShowProgressTop = defaults.object(forKey: "readerShowProgressTop") as? Bool ?? true
        self.readerShowStatisticsToggle = defaults.object(forKey: "readerShowStatisticsToggle") as? Bool ?? false
        self.readerShowReadingSpeed = defaults.object(forKey: "readerShowReadingSpeed") as? Bool ?? false
        self.readerShowReadingTime = defaults.object(forKey: "readerShowReadingTime") as? Bool ?? false
        self.readerShowSasayakiToggle = defaults.object(forKey: "readerShowSasayakiToggle") as? Bool ?? false
        
        self.popupWidth = defaults.object(forKey: "popupWidth") as? Int ?? 320
        self.popupHeight = defaults.object(forKey: "popupHeight") as? Int ?? 250
        self.popupFullWidth = defaults.object(forKey: "popupFullWidth") as? Bool ?? false
        self.popupSwipeToDismiss = defaults.object(forKey: "popupSwipeToDismiss") as? Bool ?? false
        self.popupSwipeThreshold = defaults.object(forKey: "popupSwipeThreshold") as? Int ?? 40
        
        if let data = defaults.data(forKey: "audioSources"),
           let sources = try? JSONDecoder().decode([AudioSource].self, from: data) {
            self.audioSources = sources
        } else {
            self.audioSources = [UserConfig.defaultAudioSource]
        }
        self.enableLocalAudio = defaults.object(forKey: "enableLocalAudio") as? Bool ?? false
        self.audioEnableAutoplay = defaults.object(forKey: "audioEnableAutoplay") as? Bool ?? false
        self.audioPlaybackMode = defaults.string(forKey: "audioPlaybackMode")
            .flatMap(AudioPlaybackMode.init) ?? .interrupt
        self.customCSS = defaults.string(forKey: "customCSS") ?? ""
        
        self.enableStatistics = defaults.object(forKey: "enableStatistics") as? Bool ?? false
        self.statisticsEnableSync = defaults.object(forKey: "statisticsEnableSync") as? Bool ?? false
        self.statisticsSyncMode = defaults.string(forKey: "statisticsSyncMode")
            .flatMap(StatisticsSyncMode.init) ?? .merge
        self.statisticsAutostartMode = defaults.string(forKey: "statisticsAutostartMode")
            .flatMap(StatisticsAutostartMode.init) ?? .off
        
        self.enableSasayaki = defaults.object(forKey: "enableSasayaki") as? Bool ?? false
        self.sasayakiAutoScroll = defaults.object(forKey: "sasayakiAutoScroll") as? Bool ?? true
        self.sasayakiAutoPause = defaults.object(forKey: "sasayakiAutoPause") as? Bool ?? true
        self.sasayakiEnableSync = defaults.object(forKey: "sasayakiEnableSync") as? Bool ?? false
        self.sasayakiTextColor = UserConfig.loadColor(key: "sasayakiTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.sasayakiBackgroundColor = UserConfig.loadColor(key: "sasayakiBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
        self.sasayakiDarkTextColor = UserConfig.loadColor(key: "sasayakiDarkTextColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.sasayakiDarkBackgroundColor = UserConfig.loadColor(key: "sasayakiDarkBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
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
