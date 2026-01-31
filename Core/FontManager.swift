//
//  FontManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

class FontManager {
    static let shared = FontManager()
    static let defaultFonts = ["Hiragino Mincho ProN", "Hiragino Kaku Gothic ProN"]
    
    private static func getFontsDirectory() throws -> URL {
        try BookStorage.getDocumentsDirectory().appendingPathComponent("Fonts")
    }
    
    func importFont(from: URL) throws {
        let destinationPath = "Fonts/\(from.lastPathComponent)"
        let _ = try? BookStorage.copySecurityScopedFile(from: from, to: destinationPath)
    }
    
    func getFontsFromStorage() throws -> [URL] {
        let directory = try Self.getFontsDirectory()
        
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }
    
    func getFontUrl(name: String) throws -> URL?  {
        return try getFontsFromStorage().first(where: { $0.deletingPathExtension().lastPathComponent == name } )
    }
    
    func deleteFont(name: String) throws {
        guard let url = try? getFontUrl(name: name) else { return }
        try? BookStorage.delete(at: url)
    }
    
    func isDefaultFont(name: String) -> Bool {
        return Self.defaultFonts.contains(name)
    }
}
