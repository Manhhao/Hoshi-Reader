//
//  RemoteDownloadHandler.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@Observable
@MainActor
class RemoteDownloadHandler {
    private(set) var isDownloading: Bool = false
    var shouldShowError: Bool = false
    var errorMessage: String = ""
    
    func downloadEPUB(from url: URL) async throws -> URL {
        isDownloading = true
        defer {
            isDownloading = false
        }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        return tempURL
    }
}
