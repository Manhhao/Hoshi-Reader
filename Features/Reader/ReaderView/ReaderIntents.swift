//
//  ReaderIntents.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

@MainActor
final class ReaderIntentBridge {
    static let shared = ReaderIntentBridge()
    weak var reader: ReaderViewModel?
}

struct NextPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Page"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        ReaderIntentBridge.shared.reader?.turnPage(.forward)
        return .result()
    }
}

struct PreviousPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Page"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        ReaderIntentBridge.shared.reader?.turnPage(.backward)
        return .result()
    }
}
