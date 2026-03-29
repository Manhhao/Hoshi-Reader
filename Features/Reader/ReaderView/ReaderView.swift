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
            ReaderView(document: doc, rootURL: root, enableStatistics: userConfig.enableStatistics, autostartStatistics: userConfig.statisticsAutostartMode == .on)
        }
    }
}

struct ReaderView: View {
    @Environment(\.dismissReader) private var dismissReader
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderViewModel
    @State private var topSafeArea: CGFloat = UIApplication.topSafeArea
    @State private var focusMode = false
    
    private let webViewPadding: CGFloat = 4
    private let lineHeight: CGFloat = 16
    
    private var readerBackgroundColor: Color {
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return Color(red: 0.949, green: 0.886, blue: 0.788)
        }
        if userConfig.theme == .custom {
            return userConfig.customBackgroundColor
        }
        return Color(.systemBackground)
    }
    
    private var readerTextColor: String? {
        userConfig.theme == .custom ? UIColor(userConfig.customTextColor).hexString : nil
    }
    
    init(document: EPUBDocument, rootURL: URL, enableStatistics: Bool, autostartStatistics: Bool) {
        _viewModel = State(initialValue: ReaderViewModel(document: document, rootURL: rootURL, enableStatistics: enableStatistics, autostartStatistics: autostartStatistics))
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
                .frame(height: max(topSafeArea, 25) + webViewPadding + (userConfig.readerShowProgressTop && !progressString.isEmpty ? lineHeight : 0) + (userConfig.readerShowTitle ? lineHeight : 0))
                .contentShape(Rectangle())
            
            GeometryReader { geometry in
                ZStack {
                    if userConfig.continuousMode {
                        ScrollReaderWebView(
                            userConfig: userConfig,
                            bridge: viewModel.bridge,
                            onNextChapter: viewModel.nextChapter,
                            onPreviousChapter: viewModel.previousChapter,
                            onSaveBookmark: viewModel.saveBookmark,
                            onInternalLink: viewModel.jumpToLink,
                            onInternalJump: viewModel.syncProgressAfterLinkJump,
                            onTextSelected: {
                                viewModel.closePopups()
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth)
                            },
                            onTapOutside: viewModel.closePopups,
                            onScroll: {
                                viewModel.closePopups()
                                if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                    viewModel.startTracking()
                                }
                            }
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            size: geometry.size,
                        ))
                    } else {
                        ReaderWebView(
                            userConfig: userConfig,
                            viewSize: CGSize(width: geometry.size.width.rounded(), height: geometry.size.height.rounded()),
                            bridge: viewModel.bridge,
                            onNextChapter: viewModel.nextChapter,
                            onPreviousChapter: viewModel.previousChapter,
                            onSaveBookmark: viewModel.saveBookmark,
                            onInternalLink: viewModel.jumpToLink,
                            onInternalJump: viewModel.syncProgressAfterLinkJump,
                            onTextSelected: {
                                viewModel.closePopups()
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth)
                            },
                            onTapOutside: viewModel.closePopups,
                            onPageTurn: {
                                viewModel.closePopups()
                                if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                    viewModel.startTracking()
                                }
                            }
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            size: geometry.size,
                        ))
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
                            clearHighlight: popup.clearHighlight,
                            onTextSelected: {
                                if let index = viewModel.popups.firstIndex(where: { $0.id == popupId }) {
                                    viewModel.closeChildPopups(parent: index)
                                }
                                return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: false, isFullWidth: false)
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
                                    viewModel.clearWebHighlight()
                                    viewModel.closePopups()
                                } else if viewModel.popups.indices.contains(index - 1) {
                                    viewModel.popups[index - 1].clearHighlight.toggle()
                                    viewModel.closeChildPopups(parent: index - 1)
                                }
                            }
                        )
                        .zIndex(Double(100 + (viewModel.popups.firstIndex(where: { $0.id == popupId }) ?? 0)))
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
                        viewModel.activeSheet = .chapters
                    } label: {
                        Label("Chapters", systemImage: "list.bullet")
                    }
                    
                    Button {
                        viewModel.activeSheet = .appearance
                    } label: {
                        Label("Appearance", systemImage: "paintbrush.pointed")
                    }
                    
                    if userConfig.enableStatistics {
                        Button {
                            viewModel.activeSheet = .statistics
                        } label: {
                            Label("Statistics", systemImage: "chart.xyaxis.line")
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
            VStack {
                if !focusMode {
                    if userConfig.readerShowTitle {
                        if let title = viewModel.document.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor.opacity(0.5)) : AnyShapeStyle(.tertiary))
                                .padding(.horizontal, 30)
                                .lineLimit(1)
                        }
                    }
                    if userConfig.readerShowProgressTop && !progressString.isEmpty {
                        Text(progressString)
                            .font(.caption)
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                            .monospacedDigit()
                            .tracking(-0.4)
                    }
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
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig, showDismiss: true)
                    .presentationDetents([.medium])
                    .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme.colorScheme ?? systemColorScheme))
            case .chapters:
                ChapterListView(document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex, fragment in
                    viewModel.jumpToChapter(index: spineIndex, fragment: fragment)
                    viewModel.activeSheet = nil
                    viewModel.clearWebHighlight()
                    viewModel.closePopups()
                } onJumpToCharacter: { count in
                    viewModel.jumpToCharacter(count)
                    viewModel.activeSheet = nil
                    viewModel.clearWebHighlight()
                    viewModel.closePopups()
                }
            case .statistics:
                StatisticsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
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
        .onChange(of: readerTextColor) { _, hex in
            viewModel.bridge.send(.updateTextColor(hex))
        }
        .onChange(of: scenePhase) { _, phase in
            guard viewModel.isTracking else {
                return
            }
            if phase == .active {
                viewModel.lastTimestamp = .now
                viewModel.isPaused = false
            }
            else {
                viewModel.isPaused = true
            }
        }
        .ignoresSafeArea(edges: .top)
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(focusMode)
        .persistentSystemOverlays(focusMode ? .hidden : .automatic)
        .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
    }
}
