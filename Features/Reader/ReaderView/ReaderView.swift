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
    var blurImages: Bool
    var layoutAdvanced: Bool
    var lineHeight: Double
    var characterSpacing: Double
    var paragraphSpacing: Double
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
                syncBookData: userConfig.enableSync && userConfig.syncUploadBooks,
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
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ReaderViewModel
    @State private var topSafeArea: CGFloat = UIApplication.topSafeArea
    @State private var focusMode = false
    @State private var inactiveSince: Date?
    @State private var imageURL: URL?
    private let webViewPadding: CGFloat = 4
    
    private var bottomSafeArea: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 20
        }
        return UIApplication.bottomSafeArea
    }
    
    private var readerBottomPadding: CGFloat {
        bottomSafeArea > 0 ? bottomSafeArea : max(topSafeArea, 25)
    }
    
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
        syncBookData: Bool,
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
            syncBookData: syncBookData,
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
                .frame(height: max(topSafeArea, 40) + webViewPadding)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
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
                                        .font(.system(size: 16))
                                        .frame(width: 26, height: 20)
                                        .contentShape(Rectangle())
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
                            }
                        }
                        
                        Spacer()
                        
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
                                        .font(.system(size: 16))
                                        .frame(width: 26, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 16)
                    .opacity(focusMode ? 1 : 0)
                    .allowsHitTesting(focusMode)
                }
            
            GeometryReader { geometry in
                ZStack {
                    let viewSize = CGSize(width: geometry.size.width.rounded(), height: (geometry.size.height + (userConfig.verticalWriting ? CGFloat(userConfig.fontSize) : 0)).rounded())
                    let scrollViewSize = CGSize(
                        width: userConfig.verticalWriting ? (geometry.size.width * (1 - CGFloat(userConfig.horizontalPadding) / 100)).rounded() : viewSize.width,
                        height: userConfig.verticalWriting ? viewSize.height : (geometry.size.height * (1 - CGFloat(userConfig.verticalPadding) / 100)).rounded()
                    )
                    if userConfig.continuousMode {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if viewModel.popups.isEmpty {
                                    withAnimation(.default.speed(2)) {
                                        focusMode.toggle()
                                    }
                                } else {
                                    viewModel.closePopups()
                                }
                            }
                        
                        ScrollReaderWebView(
                            userConfig: userConfig,
                            viewportWidth: Int(scrollViewSize.width),
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
                                if !focusMode {
                                    withAnimation(.default.speed(2)) {
                                        focusMode = true
                                    }
                                }
                                let selection = SelectionData(
                                    text: $0.text,
                                    sentence: $0.sentence,
                                    rect: $0.rect.offsetBy(
                                        dx: (geometry.size.width - scrollViewSize.width) / 2,
                                        dy: userConfig.verticalWriting ? 0 : (geometry.size.height - scrollViewSize.height) / 2
                                    ),
                                    normalizedOffset: $0.normalizedOffset
                                )
                                return viewModel.handleTextSelection(selection, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                            },
                            onTapOutside: {
                                if viewModel.popups.isEmpty {
                                    withAnimation(.default.speed(2)) {
                                        focusMode.toggle()
                                    }
                                } else {
                                    viewModel.closePopups()
                                }
                            },
                            onScroll: {
                                viewModel.closePopups()
                                if !focusMode {
                                    withAnimation(.default.speed(2)) {
                                        focusMode = true
                                    }
                                }
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
                            onHighlightCreated: viewModel.addHighlight,
                            onImageTapped: { imageURL = $0 }
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
                            blurImages: userConfig.blurImages,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            paragraphSpacing: userConfig.paragraphSpacing,
                            size: scrollViewSize,
                        ))
                        .frame(width: scrollViewSize.width, height: scrollViewSize.height)
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
                                if !focusMode {
                                    withAnimation(.default.speed(2)) {
                                        focusMode = true
                                    }
                                }
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                            },
                            onTapOutside: {
                                if viewModel.popups.isEmpty {
                                    withAnimation(.default.speed(2)) {
                                        focusMode.toggle()
                                    }
                                } else {
                                    viewModel.closePopups()
                                }
                            },
                            onPageTurn: {
                                viewModel.clearForwardHistory()
                                viewModel.closePopups()
                                if !focusMode {
                                    withAnimation(.default.speed(2)) {
                                        focusMode = true
                                    }
                                }
                                if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                    viewModel.startTracking()
                                }
                            },
                            onRestoreCompleted: {
                                viewModel.handleRestoreCompleted()
                            },
                            onHighlightCreated: viewModel.addHighlight,
                            onImageTapped: { imageURL = $0 }
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
                            blurImages: userConfig.blurImages,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            paragraphSpacing: userConfig.paragraphSpacing,
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
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
            
            Color.clear
                .frame(height: readerBottomPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.clearSelection()
                    if viewModel.popups.isEmpty {
                        withAnimation(.default.speed(2)) {
                            focusMode.toggle()
                        }
                    } else {
                        viewModel.closePopups()
                    }
                }
                .overlay(alignment: .center) {
                    if userConfig.readerAlwaysShowProgress && !progressString.isEmpty {
                        VStack {
                            Text(progressString)
                                .font(.caption)
                                .monospacedDigit()
                                .tracking(-0.4)
                        }
                        .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                        .offset(y: -3)
                    }
                }
        }
        .background(readerBackgroundColor.ignoresSafeArea())
        .overlay(alignment: .top) {
            let showTitle = userConfig.readerShowTitle
            let showTopProgress = userConfig.readerShowProgressTop && !progressString.isEmpty && !userConfig.readerAlwaysShowProgress
            if showTitle || showTopProgress {
                VStack(spacing: 2) {
                    if showTitle {
                        Text(viewModel.book.displayTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    if showTopProgress {
                        Text(progressString)
                            .font(.caption)
                            .monospacedDigit()
                            .tracking(-0.4)
                    }
                }
                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .conditionalGlassEffect()
                .padding(.horizontal, 40)
                .padding(.top, max(topSafeArea, 25))
                .opacity(focusMode ? 0 : 1)
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button {
                    if viewModel.isTracking {
                        viewModel.stopTracking()
                    }
                    dismissReader?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .conditionalGlassEffect()
                
                Spacer()
                
                let showBottomProgress = !userConfig.readerShowProgressTop && !progressString.isEmpty && !userConfig.readerAlwaysShowProgress
                let showStats = userConfig.enableStatistics && !statisticsString.isEmpty
                if showBottomProgress || showStats {
                    VStack(spacing: 2) {
                        if showStats {
                            Text(statisticsString)
                                .font(.caption)
                                .monospacedDigit()
                                .tracking(-0.4)
                        }
                        if showBottomProgress {
                            Text(progressString)
                                .font(.caption)
                                .monospacedDigit()
                                .tracking(-0.4)
                        }
                    }
                    .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .conditionalGlassEffect()
                }
                
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
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .conditionalGlassEffect()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomSafeArea > 0 ? bottomSafeArea : 8)
            .opacity(focusMode ? 0 : 1)
            .allowsHitTesting(!focusMode)
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
        .overlay {
            if let url = imageURL {
                FullscreenImageView(url: url, backgroundColor: readerBackgroundColor) {
                    imageURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig, showDismiss: true)
                    .presentationDetents([.medium])
                    .preferredColorScheme(readerTheme)
            case .chapters:
                ChapterListView(displayTitle: viewModel.book.displayTitle, document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex, fragment in
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
        .task {
            let onSynced: @MainActor (CloudKitSyncManager.Event) -> Void = { [weak viewModel] direction in
                guard let viewModel else { return }
                viewModel.handleCloudKitSync(event: direction, dismiss: dismiss)
            }
            await CloudKitSyncManager.shared.addEventHandlers([onSynced])
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
        .ignoresSafeArea(edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(focusMode)
        .persistentSystemOverlays(focusMode ? .hidden : .automatic)
        .preferredColorScheme(readerTheme)
    }
}
