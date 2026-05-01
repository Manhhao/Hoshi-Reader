//
//  DictionaryManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI
import CHoshiDicts
import CxxStdlib

enum DictionaryType: String {
    case term = "Term"
    case frequency = "Frequency"
    case pitch = "Pitch"
}

@Observable
@MainActor
class DictionaryManager {
    static let shared = DictionaryManager()
    
    private(set) var termDictionaries: [DictionaryInfo] = []
    private(set) var frequencyDictionaries: [DictionaryInfo] = []
    private(set) var pitchDictionaries: [DictionaryInfo] = []
    private(set) var updatableDictionaries: [(DictionaryInfo, DictionaryType)] = []
    private(set) var isImporting = false
    private(set) var isUpdating = false
    var shouldShowError = false
    var errorMessage = ""
    var currentImport = ""
    
    private static let configFileName = "config.json"
    private static let collapsedConfig = "collapsed.json"
    
    private init() {
        loadDictionaries()
        rebuildLookupQuery()
    }
    
    func loadDictionaries() {
        updatableDictionaries = []
        let storedTermDicts = (try? getDictionariesFromStorage(type: .term)) ?? []
        let storedFreqDicts = (try? getDictionariesFromStorage(type: .frequency)) ?? []
        let storedPitchDicts = (try? getDictionariesFromStorage(type: .pitch)) ?? []
        
        if let config = try? loadDictionaryConfig() {
            termDictionaries = collectDictionaries(storedDicts: storedTermDicts, configDicts: config.termDictionaries)
            frequencyDictionaries = collectDictionaries(storedDicts: storedFreqDicts, configDicts: config.frequencyDictionaries)
            pitchDictionaries = collectDictionaries(storedDicts: storedPitchDicts, configDicts: config.pitchDictionaries)
        } else {
            termDictionaries = storedTermDicts
            frequencyDictionaries = storedFreqDicts
            pitchDictionaries = storedPitchDicts
        }
    }
    
    func rebuildLookupQuery() {
        let enabledTermPaths = termDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }
        
        let enabledFreqPaths = frequencyDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }
        
        let enabledPitchPaths = pitchDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }
        
        LookupEngine.shared.buildQuery(termPaths: enabledTermPaths, freqPaths: enabledFreqPaths, pitchPaths: enabledPitchPaths)
    }
    
    func collectDictionaries(storedDicts: [DictionaryInfo], configDicts: [DictionaryConfig.DictionaryEntry]) -> [DictionaryInfo] {
        var result: [DictionaryInfo] = []
        
        // collect dictionaries that are saved in config
        for configDict in configDicts.sorted(by: { $0.order < $1.order }) {
            if let stored = storedDicts.first(where: { $0.path.lastPathComponent == configDict.fileName }) {
                var dictInfo = stored
                dictInfo.isEnabled = configDict.isEnabled
                dictInfo.order = configDict.order
                result.append(dictInfo)
            }
        }
        
        // append remaining dicts that were imported
        let currentResult = Set(result.map({ $0.path.lastPathComponent }))
        for storedDict in storedDicts {
            if !currentResult.contains(storedDict.path.lastPathComponent) {
                var dictInfo = storedDict
                dictInfo.isEnabled = true
                dictInfo.order = result.count
                result.append(dictInfo)
            }
        }
        return result
    }
    
    func getDictionariesFromStorage(type: DictionaryType) throws -> [DictionaryInfo] {
        let directory = try Self.getDictionariesDirectory()
            .appendingPathComponent(type.rawValue)
        
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap {
            let values = try $0.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                try? BookStorage.delete(at: $0)
                return nil
            }
            guard let index = BookStorage.load(DictionaryIndex.self, from: $0.appendingPathComponent("index.json")) else {
                try? BookStorage.delete(at: $0)
                return nil
            }
            let result = DictionaryInfo(index: index, path: $0)
            if index.isUpdatable && !index.indexUrl.isEmpty && !index.downloadUrl.isEmpty {
                updatableDictionaries.append((result, type))
            }
            return result
        }
    }
    
    private func loadDictionaryConfig() throws -> DictionaryConfig? {
        let configURL = try Self.getDictionariesDirectory()
            .appendingPathComponent(Self.configFileName)
        
        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            return try decoder.decode(DictionaryConfig.self, from: data)
        }
        return nil
    }
    
    private func saveDictionaryConfig() {
        let config = DictionaryConfig(
            termDictionaries: termDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order
                )
            },
            frequencyDictionaries: frequencyDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order
                )
            },
            pitchDictionaries: pitchDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order
                )
            }
        )
        
        guard let configURL = try? Self.getDictionariesDirectory()
            .appendingPathComponent(Self.configFileName) else {
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            
            let directory = configURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            try data.write(to: configURL, options: .atomic)
        } catch {
            showError("failed to save dictionary config: \(error.localizedDescription)")
        }
    }
    
    func importRecommendedDictionaries() {
        let recommendedDictionaries: [(name: String, url: String, type: DictionaryType)] = [
            ("JMdict", "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english.json", .term),
            ("Jiten", "https://api.jiten.moe/api/frequency-list/index", .frequency),
        ]
        
        isImporting = true
        
        Task.detached {
            var tempFiles: [URL] = []
            defer {
                for file in tempFiles {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            
            do {
                for (name, url, type) in recommendedDictionaries {
                    await MainActor.run {
                        self.currentImport = "Fetching \(name)"
                    }
                    
                    let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
                    let remoteIndex = try JSONDecoder().decode(DictionaryIndex.self, from: data)
                    
                    await MainActor.run {
                        self.currentImport = "Downloading \(remoteIndex.title)"
                    }
                    
                    let (temp, _) = try await URLSession.shared.download(from: URL(string: remoteIndex.downloadUrl)!)
                    tempFiles.append(temp)
                    
                    await MainActor.run {
                        self.currentImport = "Importing \(remoteIndex.title)"
                    }
                    
                    let destinationPath = try await Self.getDictionariesDirectory()
                        .appendingPathComponent(type.rawValue).path(percentEncoded: false)
                    
                    let importResult = dictionary_importer.import(
                        std.string(temp.path(percentEncoded: false)),
                        std.string(destinationPath)
                    )
                    
                    if !importResult.success {
                        throw URLError(.cannotParseResponse)
                    }
                }
                
                await MainActor.run {
                    self.isImporting = false
                    self.loadDictionaries()
                    self.saveDictionaryConfig()
                    self.rebuildLookupQuery()
                }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.showError("failed to download dictionaries: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func importDictionary(from urls: [URL], type: DictionaryType) {
        let destinationPath: String
        do {
            destinationPath = try Self.getDictionariesDirectory()
                .appendingPathComponent(type.rawValue).path(percentEncoded: false)
        } catch {
            showError("failed to import dictionary: \(error.localizedDescription)")
            return
        }
        
        isImporting = true
        
        Task.detached {
            var imported: [String] = []
            var failed: [String] = []
            
            for url in urls {
                await MainActor.run {
                    self.currentImport = "Importing \(url.lastPathComponent)"
                }
                
                let current = url.lastPathComponent
                guard url.startAccessingSecurityScopedResource() else {
                    failed.append(current)
                    continue
                }
                
                defer { url.stopAccessingSecurityScopedResource() }
                
                let importResult = dictionary_importer.import(
                    std.string(url.path(percentEncoded: false)),
                    std.string(destinationPath)
                )
                
                if importResult.success {
                    imported.append(current)
                } else {
                    failed.append(current)
                }
            }
            
            await MainActor.run {
                self.isImporting = false
                
                if !imported.isEmpty {
                    self.loadDictionaries()
                    self.saveDictionaryConfig()
                    self.rebuildLookupQuery()
                }
                
                if imported.isEmpty {
                    self.showError("failed to import dictionary")
                } else if !failed.isEmpty {
                    self.showError("some dictionaries could not be imported:\n\(failed.joined(separator: "\n"))")
                }
            }
        }
    }
    
    func updateDictionaries() {
        let dictionaries = updatableDictionaries
        isUpdating = true
        Task.detached {
            var tempFiles: [URL] = []
            defer {
                for file in tempFiles {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            do {
                for (dictionary, type) in dictionaries {
                    let index = dictionary.index
                    await MainActor.run {
                        self.currentImport = "Checking \(index.title)"
                    }
                    
                    let (data, _) = try await URLSession.shared.data(from: URL(string: index.indexUrl)!)
                    let remoteIndex = try JSONDecoder().decode(DictionaryIndex.self, from: data)
                    
                    if index.revision == remoteIndex.revision {
                        continue
                    }
                    
                    await MainActor.run {
                        self.currentImport = "Downloading \(remoteIndex.title)"
                    }
                    
                    let (temp, _) = try await URLSession.shared.download(from: URL(string: remoteIndex.downloadUrl)!)
                    tempFiles.append(temp)
                    
                    await MainActor.run {
                        self.currentImport = "Importing \(remoteIndex.title)"
                    }
                    
                    let destinationPath = try await Self.getDictionariesDirectory()
                        .appendingPathComponent(type.rawValue).path(percentEncoded: false)
                    
                    let importResult = dictionary_importer.import(
                        std.string(temp.path(percentEncoded: false)),
                        std.string(destinationPath)
                    )
                    
                    if !importResult.success {
                        continue
                    }
                    
                    await MainActor.run {
                        self.loadDictionaries()
                        let old = dictionary.index.title
                        let new = String(importResult.title)
                        if old != new {
                            if let currentIndex = self.getDictionaryIndex(title: old, type: type) {
                                let wasEnabled = self.isDictionaryEnabled(at: currentIndex, type: type)
                                self.deleteDictionary(indexSet: IndexSet(integer: currentIndex), type: type)
                                let importedIndex = self.getDictionaryIndex(title: new, type: type)!
                                self.setDictionaryEnabled(index: importedIndex, enabled: wasEnabled, type: type)
                                self.moveDictionary(from: IndexSet(integer: importedIndex), to: currentIndex, type: type)
                                AnkiManager.shared.updateHandlebar(old: old, new: new)
                            }
                        } else {
                            self.rebuildLookupQuery()
                        }
                    }
                }
                
                await MainActor.run {
                    self.isUpdating = false
                }
            } catch {
                await MainActor.run {
                    self.isUpdating = false
                    self.showError("failed to update dictionaries: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func toggleDictionary(id: UUID, enabled: Bool, type: DictionaryType) {
        switch type {
        case .term:
            guard let index = termDictionaries.firstIndex(where: { $0.id == id }) else { return }
            termDictionaries[index].isEnabled = enabled
        case .frequency:
            guard let index = frequencyDictionaries.firstIndex(where: { $0.id == id }) else { return }
            frequencyDictionaries[index].isEnabled = enabled
        case .pitch:
            guard let index = pitchDictionaries.firstIndex(where: { $0.id == id }) else { return }
            pitchDictionaries[index].isEnabled = enabled
        }
        saveDictionaryConfig()
        rebuildLookupQuery()
    }
    
    func moveDictionary(from: IndexSet, to: Int, type: DictionaryType) {
        switch type {
        case .term:
            termDictionaries.move(fromOffsets: from, toOffset: to)
        case .frequency:
            frequencyDictionaries.move(fromOffsets: from, toOffset: to)
        case .pitch:
            pitchDictionaries.move(fromOffsets: from, toOffset: to)
        }
        updateOrder(type: type)
        saveDictionaryConfig()
        rebuildLookupQuery()
    }
    
    func updateOrder(type: DictionaryType) {
        switch type {
        case .term:
            for index in termDictionaries.indices {
                termDictionaries[index].order = index
            }
        case .frequency:
            for index in frequencyDictionaries.indices {
                frequencyDictionaries[index].order = index
            }
        case .pitch:
            for index in pitchDictionaries.indices {
                pitchDictionaries[index].order = index
            }
        }
    }
    
    func deleteDictionary(indexSet: IndexSet, type: DictionaryType) {
        switch type {
        case .term:
            for index in indexSet {
                let dictionary = termDictionaries[index]
                try? BookStorage.delete(at: dictionary.path)
                termDictionaries.remove(at: index)
                updatableDictionaries.removeAll{ $0.0.index.title == dictionary.index.title }
            }
        case .frequency:
            for index in indexSet {
                let dictionary = frequencyDictionaries[index]
                try? BookStorage.delete(at: dictionary.path)
                frequencyDictionaries.remove(at: index)
                updatableDictionaries.removeAll{ $0.0.index.title == dictionary.index.title }
            }
        case .pitch:
            for index in indexSet {
                let dictionary = pitchDictionaries[index]
                try? BookStorage.delete(at: dictionary.path)
                pitchDictionaries.remove(at: index)
                updatableDictionaries.removeAll{ $0.0.index.title == dictionary.index.title }
            }
        }
        updateOrder(type: type)
        saveDictionaryConfig()
        rebuildLookupQuery()
    }
    
    private func isDictionaryEnabled(at index: Int, type: DictionaryType) -> Bool {
        switch type {
        case .term:
            termDictionaries[index].isEnabled
        case .frequency:
            frequencyDictionaries[index].isEnabled
        case .pitch:
            pitchDictionaries[index].isEnabled
        }
    }
    
    private func setDictionaryEnabled(index: Int, enabled: Bool, type: DictionaryType) {
        switch type {
        case .term:
            termDictionaries[index].isEnabled = enabled
        case .frequency:
            frequencyDictionaries[index].isEnabled = enabled
        case .pitch:
            pitchDictionaries[index].isEnabled = enabled
        }
    }
    
    private func getDictionaryIndex(title: String, type: DictionaryType) -> Int? {
        switch type {
        case .term:
            termDictionaries.firstIndex { $0.index.title == title }
        case .frequency:
            frequencyDictionaries.firstIndex { $0.index.title == title }
        case .pitch:
            pitchDictionaries.firstIndex { $0.index.title == title }
        }
    }
    
    private static func getDictionariesDirectory() throws -> URL {
        try BookStorage.getAppDirectory().appendingPathComponent("Dictionaries")
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        shouldShowError = true
    }
}
