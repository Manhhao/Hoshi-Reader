//
//  FontManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreText
import Foundation

class FontManager {
    static let shared = FontManager()
    static let defaultFonts = ["Hiragino Mincho ProN", "Hiragino Kaku Gothic ProN"]
    static let downloadableFonts = ["Klee", "Tsukushi A Round Gothic", "YuKyokasho", "YuMincho", "YuGothic"]
    private static let yuKyokashoYoko = "YuKyokasho Yoko"
    
    private static func fontsDirectory() throws -> URL {
        try BookStorage.getAppDirectory().appendingPathComponent("Fonts")
    }
    
    func importFont(from: URL) {
        let destinationPath = "Fonts/\(from.lastPathComponent)"
        _ = try? BookStorage.copySecurityScopedFile(from: from, to: destinationPath)
    }
    
    func storedFonts() throws -> [URL] {
        let directory = try Self.fontsDirectory()
        
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent != "System" }
    }
    
    func storedFontUrl(name: String) throws -> URL?  {
        return try storedFonts().first(where: { $0.deletingPathExtension().lastPathComponent == name } )
    }
    
    func fontUrl(name: String, verticalWriting: Bool = true) throws -> URL? {
        if Self.downloadableFonts.contains(name) {
            let fileName = (name == "YuKyokasho" && !verticalWriting) ? Self.yuKyokashoYoko : name
            let url = try Self.fontsDirectory()
                .appendingPathComponent("System")
                .appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        return try storedFontUrl(name: name)
    }
    
    func hasDownloadedFont(name: String) -> Bool {
        guard (try? fontUrl(name: name)) != nil else { return false }
        if name == "YuKyokasho" {
            return (try? fontUrl(name: name, verticalWriting: false)) != nil
        }
        return true
    }
    
    func deleteFont(name: String) throws {
        guard let url = try? storedFontUrl(name: name) else { return }
        try? BookStorage.delete(at: url)
    }
    
    func isDefaultFont(name: String) -> Bool {
        return Self.defaultFonts.contains(name) || Self.downloadableFonts.contains(name)
    }
    
    static func downloadFont(_ familyName: String) async -> Bool {
        if familyName == "YuKyokasho" {
            let verticalDownloaded = await downloadSingleFont(familyName)
            guard verticalDownloaded else { return false }
            return await downloadSingleFont(yuKyokashoYoko)
        }
        return await downloadSingleFont(familyName)
    }
    
    private static func downloadSingleFont(_ familyName: String) async -> Bool {
        if shared.storeSystemFont(familyName) {
            return true
        }
        guard let postScriptName = postScriptName(for: familyName) else {
            return false
        }
        
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let descriptor = CTFontDescriptorCreateWithAttributes(
                    [kCTFontNameAttribute: postScriptName] as CFDictionary
                )
                
                CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
                    [descriptor] as CFArray,
                    nil
                ) { state, _ in
                    guard state == .didFinish || state == .didFailWithError else {
                        return true
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume()
                    }
                    return false
                }
            }
        }
        return shared.storeSystemFont(familyName)
    }
    
    private func storeSystemFont(_ familyName: String) -> Bool {
        if (try? fontUrl(name: familyName)) != nil {
            return true
        }
        
        guard let sourceUrl = systemFontUrl(familyName) else {
            return false
        }
        
        return (try? BookStorage.copyFile(from: sourceUrl, to: "Fonts/System/\(familyName)")) != nil
    }
    
    private func systemFontUrl(_ familyName: String) -> URL? {
        guard let postScriptName = Self.postScriptName(for: familyName) else {
            return nil
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontNameAttribute: postScriptName] as CFDictionary
        )
        guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor] else {
            return nil
        }
        
        for match in matches {
            if let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL {
                return url
            }
        }
        return nil
    }
    
    nonisolated private static func postScriptName(for familyName: String) -> String? {
        switch familyName {
        case "Klee":
            return "Klee-Medium"
        case "Tsukushi A Round Gothic":
            return "TsukuARdGothic-Regular"
        case "YuKyokasho":
            return "YuKyo-Medium"
        case "YuMincho":
            return "YuMin-Medium"
        case "YuGothic":
            return "YuGo-Medium"
        case yuKyokashoYoko:
            return "YuKyo_Yoko-Medium"
        default:
            return nil
        }
    }
}
