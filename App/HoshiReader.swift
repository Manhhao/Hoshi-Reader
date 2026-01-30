//
//  HoshiReader.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WebKit

@main
struct HoshiReaderApp: App {
    init() {
        WebViewPreloader.shared.warmup()
        _ = DictionaryManager.shared
    }
    
    @State private var userConfig = UserConfig()
    
    var body: some Scene {
        WindowGroup {
            BookshelfView()
                .environment(userConfig)
                .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "hoshi" else {
            return
        }
        if url.host == "ankiFetch" {
            AnkiManager.shared.fetch()
        }
    }
}

class WebViewPreloader {
    static let shared = WebViewPreloader()
    private var dummy: WKWebView?
    func warmup() {
        DispatchQueue.main.async {
            self.dummy = WKWebView(frame: .zero)
            self.dummy?.loadHTMLString("", baseURL: nil)
        }
    }
    
    func close() {
        guard dummy != nil else {
            return
        }
        DispatchQueue.main.async {
            self.dummy = nil
        }
    }
}
