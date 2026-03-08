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
    private(set) var isImporting = false
    var shouldShowError = false
    var errorMessage = ""
    var currentImport = ""
    
    private static let configFileName = "config.json"
    
    private init() {
        loadDictionaries()
    }
    
    func loadDictionaries() {
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
        rebuildLookupQuery()
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
            print(index)
            return DictionaryInfo(index: index, path: $0)
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
        let recommendedDictionaries: [(url: String, type: DictionaryType)] = [
            ("https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english.zip", .term),
            ("https://api.jiten.moe/api/frequency-list/download", .frequency),
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
                for (index, dictionary) in recommendedDictionaries.enumerated() {
                    await MainActor.run {
                        self.currentImport = "\(index + 1) / \(recommendedDictionaries.count)"
                    }
                    
                    let (temp, _) = try await URLSession.shared.download(from: URL(string: dictionary.url)!)
                    tempFiles.append(temp)
                    
                    let destinationPath = try await Self.getDictionariesDirectory()
                        .appendingPathComponent(dictionary.type.rawValue).path(percentEncoded: false)
                    
                    let importResult = dictionary_importer.import(
                        std.string(temp.path(percentEncoded: false)),
                        std.string(destinationPath)
                    )
                    
                    if importResult.term_count == 0 && importResult.meta_count == 0 {
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
            
            for (index, url) in urls.enumerated() {
                await MainActor.run {
                    self.currentImport = "\(index + 1) / \(urls.count)"
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
                
                if importResult.term_count > 0 || importResult.meta_count > 0 {
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
            }
        case .frequency:
            for index in indexSet {
                let dictionary = frequencyDictionaries[index]
                try? BookStorage.delete(at: dictionary.path)
                frequencyDictionaries.remove(at: index)
            }
        case .pitch:
            for index in indexSet {
                let dictionary = pitchDictionaries[index]
                try? BookStorage.delete(at: dictionary.path)
                pitchDictionaries.remove(at: index)
            }
        }
        updateOrder(type: type)
        saveDictionaryConfig()
        rebuildLookupQuery()
    }
    
    private static func getDictionariesDirectory() throws -> URL {
        try BookStorage.getDocumentsDirectory().appendingPathComponent("Dictionaries")
    }
    
    private func rebuildLookupQuery() {
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
    
    private func showError(_ message: String) {
        errorMessage = message
        shouldShowError = true
    }
}
