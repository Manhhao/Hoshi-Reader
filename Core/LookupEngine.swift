//
//  LookupEngine.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CYomitanDicts

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
            dictQuery?.add_dict(std.string(path.path))
        }
        for path in freqPaths {
            dictQuery?.add_freq_dict(std.string(path.path))
        }
        for path in pitchPaths {
            dictQuery?.add_pitch_dict(std.string(path.path))
        }
        lookupEngine = Lookup(&dictQuery!, &deinflector!)
    }
    
    func lookup(_ str: String, maxResults: Int = 16) -> [LookupResult] {
        return Array(lookupEngine?.lookup(std.string(str), Int32(maxResults)) ?? [])
    }
    
    func getStyles() -> [DictionaryStyle] {
        return Array(dictQuery?.get_styles() ?? [])
    }
}
