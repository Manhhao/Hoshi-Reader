//
//  HoshiReader.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit
import WebKit

@main
struct HoshiReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var userConfig = UserConfig()
    @State private var pendingImportURL: URL?
    @State private var pendingLookup: String?
    
    init() {
        WebViewPreloader.shared.warmup()
        _ = DictionaryManager.shared
        configureTabBarAppearance()
    }
    
    private func configureTabBarAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.stackedLayoutAppearance.selected.iconColor = .label
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
    
    var body: some Scene {
        WindowGroup {
            BookshelfView(pendingImportURL: $pendingImportURL, pendingLookup: $pendingLookup)
                .environment(userConfig)
                .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        LocalFileServer.shared.endBackgroundTask()
                        LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                    case .background:
                        LocalFileServer.shared.startBackgroundTask()
                    default:
                        break
                    }
                }
                .onChange(of: userConfig.enableLocalAudio) { _, _ in
                    LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        if url.scheme == "hoshi" {
            if url.host == "ankiFetch" {
                AnkiManager.shared.fetch()
            } else if url.host == "ankiSuccess" {
                LocalFileServer.shared.clearCover()
            } else if url.host == "search" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
                   !text.isEmpty {
                    pendingLookup = text
                }
            }
        } else if url.isFileURL {
            pendingImportURL = url
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
