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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var userConfig = UserConfig.shared
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var pendingLookup: String?
    @State private var pendingTab: Int?
    @State private var showSignOutConfirmation = false
    @State private var cloudManagedBooks = [BookMetadata]()
    @State private var showUploadLocalBooksConfirmation = false
    @State private var showQuotaExceededConfirmation = false
    private var shortcutHandler = ShortcutHandler.shared
    
    init() {
        TokenStorage.clearOldKeys()
        BookStorage.migrateFromDocuments()
        BookStorage.migrateBooks()
        WebViewPreloader.shared.warmup()
        _ = DictionaryManager.shared
        _ = GoogleDriveHandler.shared
        if userConfig.enableCloudKitSync {
            Task {
                await CloudKitSyncManager.shared.initializeSyncEngine()
            }
        }
        configureTabBarAppearance()
    }
    
    private func configureTabBarAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.stackedLayoutAppearance.selected.iconColor = .label
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
    
    var body: some Scene {
        WindowGroup {
            BookshelfView(
                pendingImportURL: $pendingImportURL,
                pendingRemoteImportURL: $pendingRemoteImportURL,
                pendingLookup: $pendingLookup,
                pendingTab: $pendingTab
            )
            .environment(userConfig)
            .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme == .sepia && userConfig.sepiaInvertInDark ? nil : userConfig.theme.colorScheme))
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    LocalFileServer.shared.endBackgroundTask()
                    LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                    if userConfig.autoUpdateDictionaries {
                        DictionaryManager.shared.autoUpdateDictionaries()
                    }
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
            .onChange(of: shortcutHandler.pendingType, initial: true) { _, type in
                switch type {
                case "de.manhhao.hoshi.books":
                    pendingTab = 0
                case "de.manhhao.hoshi.dictionary":
                    pendingLookup = ""
                default:
                    break
                }
                shortcutHandler.pendingType = nil
            }
            .task {
                await observeCloudKitEvents()
            }
            .alert("Clear local books?", isPresented: $showSignOutConfirmation) {
                Button("Confirm", role: .destructive) {
                    Task {
                        try await CloudKitSyncManager.shared.deleteLocal(books: cloudManagedBooks)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have logged out iCloud account. Do you want to clear local book data of the previous account?")
            }
            .alert("Upload local books?", isPresented: $showUploadLocalBooksConfirmation) {
                Button("Upload") {
                    Task {
                        try? await CloudKitSyncManager.shared.uploadUnmanagedBooks()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have logged in a new iCloud account. Do you want to upload local books to this iCloud server?")
            }
            .alert("iCloud Storage Full", isPresented: $showQuotaExceededConfirmation) {
                Button("OK") {}
            } message: {
                Text("iCloud syncing has been disabled because you have run out of iCloud space. Please free up space or upgrade your storage.")
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        if url.scheme == "hoshi" {
            if url.host == "ankiFetch" {
                AnkiManager.shared.fetch()
            } else if url.host == "ankiSuccess" {
                LocalFileServer.shared.clearMedia()
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let expression = components.queryItems?.first(where: { $0.name == "expression" })?.value {
                    AnkiManager.shared.addWord(expression)
                }
            } else if url.host == "search" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                pendingLookup = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            } else if url.host == "open", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                      let remoteURL = URL(string: urlString) {
                pendingRemoteImportURL = remoteURL
            }
        } else if url.isFileURL {
            pendingImportURL = url
        }
    }
    
    private func observeCloudKitEvents() async {
        let onError: @MainActor (CloudKitSyncManager.Event) -> Void = { event in
            if case let .account(accountEvent) = event {
                switch accountEvent {
                case .signOut(managedBooks: let managedBooks):
                    self.cloudManagedBooks = managedBooks
                    showSignOutConfirmation = true
                    userConfig.enableCloudKitSync = false
                case .signIn:
                    fallthrough
                case .accountChanged:
                    showUploadLocalBooksConfirmation = true
                }
            } else if case let .error(syncError) = event {
                switch syncError {
                case .quotaExceeded:
                    showQuotaExceededConfirmation = true
                    userConfig.enableCloudKitSync = false
                }
            }
        }
        await CloudKitSyncManager.shared.observeEvents(onError)
    }
}

@Observable
class ShortcutHandler {
    static let shared = ShortcutHandler()
    var pendingType: String?
    func handle(_ shortcutItem: UIApplicationShortcutItem) {
        pendingType = shortcutItem.type
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShortcutSceneDelegate.self
        return config
    }
}

class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            ShortcutHandler.shared.handle(shortcutItem)
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        ShortcutHandler.shared.handle(shortcutItem)
        completionHandler(true)
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
