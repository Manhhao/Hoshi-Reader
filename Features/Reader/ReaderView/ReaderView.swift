//
//  ReaderView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct WebViewState: Hashable {
    var verticalWriting: Bool
    var fontSize: Int
    var selectedFont: String
    var hideFurigana: Bool
    var horizontalPadding: Int
    var verticalPadding: Int
    var avoidPageBreak: Bool
    var justifyText: Bool
    var layoutAdvanced: Bool
    var lineHeight: Double
    var characterSpacing: Double
    var size: CGSize
}

struct ReaderLoader: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderLoaderViewModel
    
    init(book: BookMetadata) {
        _viewModel = State(initialValue: ReaderLoaderViewModel(book: book))
    }
    
    var body: some View {
        if let doc = viewModel.document, let root = viewModel.rootURL {
            ReaderView(
                book: viewModel.book,
                document: doc,
                rootURL: root,
                enableStatistics: userConfig.enableStatistics,
                autostartStatistics: userConfig.statisticsAutostartMode == .on,
                autoSyncEnabled: userConfig.enableSync && userConfig.enableAutoSync,
                syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                statsSyncMode: userConfig.statisticsSyncMode,
                syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
            )
        }
    }
}

struct ReaderView: View {
    @Environment(\.dismissReader) private var dismissReader
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderViewModel
    @State private var topSafeArea: CGFloat = UIApplication.topSafeArea
    @State private var focusMode = false
    @State private var inactiveSince: Date?
    @State private var topBarLeftWidth: CGFloat = 0
    @State private var topBarRightWidth: CGFloat = 0
    @State private var topBarTotalWidth: CGFloat = 0
    @State private var titleNaturalWidth: CGFloat = 0
    
    private let webViewPadding: CGFloat = 4
    private let lineHeight: CGFloat = 16
    
    private var sepiaInverted: Bool {
        userConfig.theme == .sepia && userConfig.sepiaInvertInDark && systemColorScheme == .dark
    }
    
    private var readerBackgroundColor: Color {
        if sepiaInverted {
            return Color(red: 0.094, green: 0.082, blue: 0.047)
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return Color(red: 0.949, green: 0.886, blue: 0.788)
        }
        return userConfig.theme == .custom ? userConfig.customBackgroundColor : Color(.systemBackground)
    }
    
    private var readerTextColor: String? {
        if sepiaInverted {
            return "#F2E2C9"
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return "#332A1B"
        }
        return userConfig.theme == .custom ? UIColor(userConfig.customTextColor).hexString : nil
    }
    
    private var readerTheme: ColorScheme {
        if userConfig.theme == .custom {
            return userConfig.uiTheme.colorScheme ?? systemColorScheme
        }
        if userConfig.theme == .sepia && userConfig.sepiaInvertInDark {
            return systemColorScheme
        }
        return userConfig.theme.colorScheme ?? systemColorScheme
    }
    
    private var sasayakiTextColor: Color {
        readerTheme == .dark ? userConfig.sasayakiDarkTextColor : userConfig.sasayakiTextColor
    }
    
    private var sasayakiBackgroundColor: Color {
        readerTheme == .dark ? userConfig.sasayakiDarkBackgroundColor : userConfig.sasayakiBackgroundColor
    }
    
    private func updateSasayakiColors() {
        viewModel.bridge.send(.updateSasayakiColors(
            textHex: UIColor(sasayakiTextColor).hexString,
            backgroundHex: UIColor(sasayakiBackgroundColor).hexString
        ))
    }
    
    private func flushAutoSyncInBackground() {
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        
        Task {
            await viewModel.flushAutoSync()
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }
    
    init(
        book: BookMetadata,
        document: EPUBDocument,
        rootURL: URL,
        enableStatistics: Bool,
        autostartStatistics: Bool,
        autoSyncEnabled: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) {
        _viewModel = State(initialValue: ReaderViewModel(
            book: book,
            document: document,
            rootURL: rootURL,
            enableStatistics: enableStatistics,
            autostartStatistics: autostartStatistics,
            autoSyncEnabled: autoSyncEnabled,
            syncStats: syncStats,
            statsSyncMode: statsSyncMode,
            syncAudioBook: syncAudioBook
        ))
    }
    
    private var progressString: String {
        var result: [String] = []
        if userConfig.readerShowCharacters {
            result.append("\(viewModel.currentCharacter) / \(viewModel.bookInfo.characterCount)")
        }
        if userConfig.readerShowPercentage {
            let percent = viewModel.bookInfo.characterCount > 0 ? (Double(viewModel.currentCharacter) / Double(viewModel.bookInfo.characterCount) * 100) : 0
            result.append("\(String(format: "%.2f%%", percent))")
        }
        return result.joined(separator: " ")
    }
    
    private var statisticsString: String {
        var result: [String] = []
        if userConfig.readerShowReadingSpeed {
            result.append("\(viewModel.sessionStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h")
        }
        if userConfig.readerShowReadingTime {
            result.append("\(Duration.seconds(viewModel.sessionStatistics.readingTime).formatted(.time(pattern: .hourMinute)))")
        }
        return result.joined(separator: " ")
    }
    
    var body: some View {
        // on ipad on first load, the geometry reader includes the safearea at the top
        // if you tab out and tab back in, the area recalculates causing the reader to be misaligned
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(topSafeArea, 25) + webViewPadding
                       + (userConfig.readerShowProgressTop && !progressString.isEmpty ? lineHeight : 0)
                       + ((userConfig.readerShowTitle
                           || (userConfig.enableStatistics && userConfig.readerShowStatisticsToggle)
                           || (userConfig.enableSasayaki && userConfig.readerShowSasayakiToggle && viewModel.sasayakiPlayer.hasAudio)
                           || viewModel.backTarget != nil || viewModel.forwardTarget != nil) ? lineHeight : 0))
                .contentShape(Rectangle())
            
            GeometryReader { geometry in
                ZStack {
                    let viewSize = CGSize(width: geometry.size.width.rounded(), height: (geometry.size.height + (userConfig.verticalWriting ? CGFloat(userConfig.fontSize) : 0)).rounded())
                    if userConfig.continuousMode {
                        ScrollReaderWebView(
                            userConfig: userConfig,
                            bridge: viewModel.bridge,
                            textColor: readerTextColor,
                            sasayakiTextColor: sasayakiTextColor,
                            sasayakiBackgroundColor: sasayakiBackgroundColor,
                            onNextChapter: viewModel.nextChapter,
                            onPreviousChapter: viewModel.previousChapter,
                            onSaveBookmark: viewModel.saveBookmark,
                            onInternalLink: viewModel.jumpToLink,
                            onInternalJump: viewModel.syncProgressAfterLinkJump,
                            onTextSelected: {
                                viewModel.closePopups()
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                            },
                            onTapOutside: viewModel.closePopups,
                            onScroll: {
                                viewModel.closePopups()
                                if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                    viewModel.startTracking()
                                }
                            },
                            onProgressChanged: {
                                viewModel.updateProgress($0)
                                viewModel.clearForwardHistory()
                            },
                            onRestoreCompleted: {
                                viewModel.handleRestoreCompleted()
                            },
                            onHighlightCreated: viewModel.addHighlight
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            justifyText: userConfig.justifyText,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            size: geometry.size,
                        ))
                        .frame(width: viewSize.width, height: viewSize.height)
                    } else {
                        ReaderWebView(
                            userConfig: userConfig,
                            viewSize: viewSize,
                            bridge: viewModel.bridge,
                            textColor: readerTextColor,
                            sasayakiTextColor: sasayakiTextColor,
                            sasayakiBackgroundColor: sasayakiBackgroundColor,
                            onNextChapter: viewModel.nextChapter,
                            onPreviousChapter: viewModel.previousChapter,
                            onSaveBookmark: viewModel.saveBookmark,
                            onInternalLink: viewModel.jumpToLink,
                            onInternalJump: viewModel.syncProgressAfterLinkJump,
                            onTextSelected: {
                                viewModel.closePopups()
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                            },
                            onTapOutside: viewModel.closePopups,
                            onPageTurn: {
                                viewModel.clearForwardHistory()
                                viewModel.closePopups()
                                if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                    viewModel.startTracking()
                                }
                            },
                            onRestoreCompleted: {
                                viewModel.handleRestoreCompleted()
                            },
                            onHighlightCreated: viewModel.addHighlight
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            justifyText: userConfig.justifyText,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            size: geometry.size,
                        ))
                        .frame(width: viewSize.width, height: viewSize.height)
                    }
                    
                    ForEach($viewModel.popups) { $popup in
                        let popupId = popup.id
                        PopupView(
                            userConfig: userConfig,
                            isVisible: $popup.showPopup,
                            selectionData: popup.currentSelection,
                            lookupResults: popup.lookupResults,
                            dictionaryStyles: popup.dictionaryStyles,
                            screenSize: geometry.size,
                            isVertical: popup.isVertical,
                            isFullWidth: popup.isFullWidth,
                            coverURL: viewModel.coverURL,
                            documentTitle: viewModel.document.title,
                            clearSelection: popup.clearSelection,
                            onTextSelected: {
                                if let index = viewModel.popups.firstIndex(where: { $0.id == popupId }) {
                                    viewModel.closeChildPopups(parent: index)
                                }
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: false, isFullWidth: false, autoPause: userConfig.sasayakiAutoPause)
                            },
                            onTapOutside: {
                                if let index = viewModel.popups.firstIndex(where: { $0.id == popupId }) {
                                    viewModel.closeChildPopups(parent: index)
                                }
                            },
                            onSwipeDismiss: {
                                guard let index = viewModel.popups.firstIndex(where: { $0.id == popupId }),
                                      viewModel.popups.indices.contains(index) else {
                                    return
                                }
                                if index == 0 {
                                    viewModel.clearSelection()
                                    viewModel.closePopups()
                                } else if viewModel.popups.indices.contains(index - 1) {
                                    viewModel.popups[index - 1].clearSelection.toggle()
                                    viewModel.closeChildPopups(parent: index - 1)
                                }
                            },
                            onPause: {
                                viewModel.wasPaused = false
                            },
                            sasayakiCue: popup.sasayakiCue,
                            sasayakiPlayer: viewModel.sasayakiPlayer,
                            wasPaused: viewModel.wasPaused
                        )
                        .zIndex(Double(100 + (viewModel.popups.firstIndex(where: { $0.id == popupId }) ?? 0)))
                    }
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.secondary)
                    }
                }
            }
            
            HStack {
                CircleButton(systemName: "chevron.left")
                    .onTapGesture {
                        if viewModel.isTracking {
                            viewModel.stopTracking()
                        }
                        dismissReader?()
                    }
                    .opacity(focusMode ? 0 : 1)
                
                Spacer()
                
                Menu {
                    Button {
                        viewModel.activeSheet = .appearance
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                    
                    Button {
                        viewModel.activeSheet = .chapters
                    } label: {
                        Label("Chapters", systemImage: "list.bullet")
                    }
                    
                    Button {
                        viewModel.activeSheet = .highlights
                    } label: {
                        Label("Highlights", systemImage: "highlighter")
                    }
                    
                    if userConfig.enableStatistics {
                        Button {
                            viewModel.activeSheet = .statistics
                        } label: {
                            Label("Statistics", systemImage: "chart.xyaxis.line")
                        }
                    }
                    
                    if userConfig.enableSasayaki && viewModel.sasayakiPlayer.hasMatch {
                        Button {
                            viewModel.activeSheet = .sasayaki
                        } label: {
                            Label("Sasayaki", systemImage: "waveform")
                        }
                    }
                } label: {
                    CircleButton(systemName: "slider.horizontal.3")
                }
                .tint(.primary)
                .opacity(focusMode ? 0 : 1)
            }
            .padding(.horizontal, 20)
            .frame(height: (UIApplication.bottomSafeArea > 25 ? UIApplication.bottomSafeArea : 44) + 10, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.default.speed(2)) {
                    focusMode.toggle()
                }
            }
        }
        .background(readerBackgroundColor)
        .overlay(alignment: .top) {
            VStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    HStack {
                        HStack(spacing: 2) {
                            if userConfig.enableStatistics && userConfig.readerShowStatisticsToggle {
                                Button {
                                    if viewModel.isTracking {
                                        viewModel.stopTracking()
                                    } else {
                                        viewModel.startTracking()
                                    }
                                } label: {
                                    Image(systemName: viewModel.isTracking ? "timer" : "chart.xyaxis.line")
                                        .font(.subheadline)
                                        .frame(width: 24, height: lineHeight)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                            }
                            
                            if let character = viewModel.backTarget {
                                Button {
                                    viewModel.navigateBackwards()
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.uturn.backward.circle")
                                        Text(character.formatted(.number.grouping(.never)))
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                                .opacity(focusMode ? 0 : 1)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { topBarLeftWidth = $0 }
                        
                        Spacer(minLength: 0)
                        
                        HStack(spacing: 2) {
                            if let character = viewModel.forwardTarget {
                                Button {
                                    viewModel.navigateForwards()
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(character.formatted(.number.grouping(.never)))
                                        Image(systemName: "arrow.uturn.right.circle")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                                .opacity(focusMode ? 0 : 1)
                            }
                            
                            if userConfig.enableSasayaki && userConfig.readerShowSasayakiToggle && viewModel.sasayakiPlayer.hasAudio {
                                Button {
                                    if viewModel.wasPaused {
                                        viewModel.wasPaused = false
                                    } else {
                                        viewModel.sasayakiPlayer.togglePlayback()
                                    }
                                } label: {
                                    Image(systemName: viewModel.sasayakiPlayer.isPlaying || viewModel.wasPaused ? "pause.fill" : "waveform")
                                        .font(.subheadline)
                                        .frame(width: 24, height: lineHeight)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { topBarRightWidth = $0 }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { topBarTotalWidth = $0 }
                    
                    if userConfig.readerShowTitle, let title = viewModel.document.title {
                        let gap: CGFloat = 2
                        let leftEdge = topBarLeftWidth + gap
                        let rightEdge = topBarTotalWidth - topBarRightWidth - gap
                        let availableSpace = max(0, rightEdge - leftEdge)
                        let displayWidth = min(titleNaturalWidth, availableSpace)
                        let titleLeading = max(leftEdge, min(rightEdge - displayWidth, (topBarTotalWidth - displayWidth) / 2))
                        
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor.opacity(0.5)) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .frame(width: min(titleNaturalWidth, availableSpace), alignment: .center)
                            .offset(x: titleLeading)
                            .opacity(focusMode ? 0 : 1)
                    }
                }
                .overlay {
                    if userConfig.readerShowTitle, let title = viewModel.document.title {
                        Text(title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .fixedSize()
                            .hidden()
                            .allowsHitTesting(false)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleNaturalWidth = $0 }
                    }
                }
                .padding(.horizontal, 15)
                
                if userConfig.readerShowProgressTop && !progressString.isEmpty {
                    Text(progressString)
                        .font(.caption)
                        .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        .tracking(-0.4)
                        .opacity(focusMode ? 0 : 1)
                }
            }
            .padding(.top, max(topSafeArea, 25))
        }
        .overlay(alignment: .bottom) {
            VStack {
                if !focusMode {
                    if userConfig.enableStatistics && !statisticsString.isEmpty {
                        Text(statisticsString)
                            .font(.caption)
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                    }
                    if !userConfig.readerShowProgressTop && !progressString.isEmpty {
                        Text(progressString)
                            .font(.caption)
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                    }
                }
            }
            .monospacedDigit()
            .tracking(-0.4)
        }
        .overlay {
            if viewModel.isSyncing {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                    
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.secondary)
                }
            }
        }
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig, showDismiss: true)
                    .presentationDetents([.medium])
                    .preferredColorScheme(readerTheme)
            case .chapters:
                ChapterListView(document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex, fragment in
                    viewModel.jumpToChapter(index: spineIndex, fragment: fragment)
                    viewModel.activeSheet = nil
                    viewModel.clearSelection()
                    viewModel.closePopups()
                } onJumpToCharacter: { count in
                    viewModel.jumpToCharacter(count)
                    viewModel.activeSheet = nil
                    viewModel.clearSelection()
                    viewModel.closePopups()
                }
            case .highlights:
                HighlightListView(
                    document: viewModel.document,
                    bookInfo: viewModel.bookInfo,
                    highlights: viewModel.highlights,
                    onJump: { highlight in
                        viewModel.jumpToCharacter(highlight.character)
                        viewModel.activeSheet = nil
                        viewModel.clearSelection()
                        viewModel.closePopups()
                    },
                    onDelete: { highlight in
                        viewModel.removeHighlight(highlight)
                    }
                )
                .presentationDetents([.medium, .large])
            case .statistics:
                StatisticsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            case .sasayaki:
                SasayakiSheet(player: viewModel.sasayakiPlayer, onImportAudio: { url in
                    try viewModel.importSasayakiAudio(from: url)
                }) {
                    viewModel.activeSheet = nil
                }
                .presentationDetents([.medium])
            }
        }
        .task(id: viewModel.isTracking) {
            guard viewModel.isTracking, !viewModel.isPaused else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !viewModel.isPaused {
                    viewModel.updateStats()
                }
            }
        }
        .task {
            await viewModel.syncOnOpen()
        }
        .onChange(of: readerTextColor) { _, hex in viewModel.bridge.send(.updateTextColor(hex)) }
        .onChange(of: sasayakiTextColor) { _, _ in updateSasayakiColors() }
        .onChange(of: sasayakiBackgroundColor) { _, _ in updateSasayakiColors() }
        .onChange(of: userConfig.sasayakiAutoScroll) { _, _ in viewModel.sasayakiPlayer.updateIdleTimerDisabled() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            let shouldResync = inactiveSince.map { Date.now.timeIntervalSince($0) >= 600 } ?? false
            inactiveSince = nil
            if shouldResync {
                Task {
                    await viewModel.syncAfterForeground()
                }
            }
            guard viewModel.isTracking else {
                return
            }
            viewModel.resetTrackingBaseline()
            viewModel.isPaused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            inactiveSince = .now
            flushAutoSyncInBackground()
            guard viewModel.isTracking else {
                return
            }
            viewModel.isPaused = true
        }
        .onDisappear {
            viewModel.sasayakiPlayer.teardown()
            Task {
                await viewModel.flushAutoSync()
            }
        }
        .ignoresSafeArea(edges: .top)
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(focusMode)
        .persistentSystemOverlays(focusMode ? .hidden : .automatic)
        .preferredColorScheme(readerTheme)
    }
}
