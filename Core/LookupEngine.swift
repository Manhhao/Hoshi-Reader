//
//  LookupEngine.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CHoshiDicts

class LookupEngine {
    static let shared = LookupEngine()
    
    private var dictQuery: DictionaryQuery?
    private var deinflector: Deinflector?
    private var lookupEngine: Lookup?
    
    private init() {
        deinflector = Deinflector()
    }
    
    func buildQuery(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL]) {
        dictQuery = DictionaryQuery()
        for path in termPaths {
            dictQuery?.add_term_dict(std.string(path.path(percentEncoded: false)))
        }
        for path in freqPaths {
            dictQuery?.add_freq_dict(std.string(path.path(percentEncoded: false)))
        }
        for path in pitchPaths {
            dictQuery?.add_pitch_dict(std.string(path.path(percentEncoded: false)))
        }
        lookupEngine = Lookup(&dictQuery!, &deinflector!)
    }
    
    func lookup(_ str: String, maxResults: Int = 16, scanLength: Int = 16) -> [LookupResult] {
        return Array(lookupEngine?.lookup(std.string(str), Int32(maxResults), scanLength) ?? [])
    }
    
    func getStyles() -> [DictionaryStyle] {
        return Array(dictQuery?.get_styles() ?? [])
    }
    
    func withMediaFile<T>(dictName: String, mediaPath: String, _ body: (Data) -> T) -> T {
        let view = dictQuery!.get_media_file_view(std.string(dictName), std.string(mediaPath))
        let size = Int(view.size)
        guard size > 0, let ptr = UnsafeMutableRawPointer(mutating: view.data) else {
            return body(Data())
        }
        let data = Data(bytesNoCopy: ptr, count: size, deallocator: .none)
        return body(data)
    }
    
    func getMediaFile(dictName: String, mediaPath: String) -> Data {
        return withMediaFile(dictName: dictName, mediaPath: mediaPath) { Data($0) }
    }
}
