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
    var horizontalPadding: Int
    var verticalPadding: Int
    var size: CGSize
}

struct ReaderLoader: View {
    @State private var viewModel: ReaderLoaderViewModel
    
    init(book: BookMetadata) {
        _viewModel = State(initialValue: ReaderLoaderViewModel(book: book))
    }
    
    var body: some View {
        Group {
            if let doc = viewModel.document, let root = viewModel.rootURL {
                ReaderView(document: doc, rootURL: root)
                    .interactiveDismissDisabled()
            } else {
                ProgressView()
                    .onAppear {
                        viewModel.loadBook()
                    }
            }
        }
    }
}

struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderViewModel
    @State private var topSafeArea: CGFloat = 0
    @State private var focusMode = false
    
    private let webViewPadding: CGFloat = 12
    private let lineHeight: CGFloat = 12
    
    private let showProgressTop = true
    private let showTitle = true
    private let showCharacters = false
    private let showPercentage = false
    
    init(document: EPUBDocument, rootURL: URL) {
        _viewModel = State(initialValue: ReaderViewModel(document: document, rootURL: rootURL))
    }
    
    var progressString: String {
        var result: [String] = []
        if showCharacters {
            result.append("\(viewModel.currentCharacter) / \(viewModel.bookInfo.characterCount)")
        }
        if showPercentage {
            let percent = viewModel.bookInfo.characterCount > 0 ? (Double(viewModel.currentCharacter) / Double(viewModel.bookInfo.characterCount) * 100) : 0
            result.append("\(String(format: "%.2f%%", percent))")
        }
        return result.joined(separator: " ")
    }
    
    var body: some View {
        // on ipad on first load, the geometry reader includes the safearea at the top
        // if you tab out and tab back in, the area recalculates causing the reader to be misaligned
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topSafeArea + webViewPadding + (showProgressTop && !progressString.isEmpty ? lineHeight : 0) + (showTitle ? lineHeight : 0))
                .contentShape(Rectangle())
            
            GeometryReader { geometry in
                ZStack {
                    ReaderWebView(
                        fileURL: viewModel.getCurrentChapter(),
                        contentURL: viewModel.document.contentDirectory,
                        userConfig: userConfig,
                        viewSize: CGSize(width: geometry.size.width, height: geometry.size.height),
                        currentProgress: viewModel.currentProgress,
                        onNextChapter: viewModel.nextChapter,
                        onPreviousChapter: viewModel.previousChapter,
                        onSaveBookmark: viewModel.saveBookmark,
                        onTextSelected: { selection in
                            viewModel.handleTextSelection(selection, maxResults: userConfig.maxResults)
                        },
                        onTapOutside: viewModel.closePopup
                    )
                    .id(WebViewState(
                        verticalWriting: userConfig.verticalWriting,
                        fontSize: userConfig.fontSize,
                        horizontalPadding: userConfig.horizontalPadding,
                        verticalPadding: userConfig.verticalPadding,
                        size: geometry.size
                    ))
                    
                    PopupView(
                        isVisible: $viewModel.showPopup,
                        selectionData: viewModel.currentSelection,
                        lookupResults: viewModel.lookupResults,
                        dictionaryStyles: viewModel.dictionaryStyles,
                        screenSize: geometry.size,
                    )
                    .zIndex(100)
                }
            }
            
            HStack {
                CircleButton(systemName: "chevron.left")
                    .onTapGesture {
                        dismiss()
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
                } label: {
                    CircleButton(systemName: "slider.horizontal.3")
                }
                .tint(.primary)
                .opacity(focusMode ? 0 : 1)
            }
            .padding(.horizontal, 20)
            .frame(height: UIApplication.bottomSafeArea + 8, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.default.speed(2)) {
                    focusMode.toggle()
                }
            }
        }
        .onAppear {
            if topSafeArea == 0 {
                topSafeArea = UIApplication.topSafeArea
            }
        }
        .overlay(alignment: .top) {
            VStack {
                if !focusMode {
                    if showTitle {
                        if let title = viewModel.document.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 30)
                                .lineLimit(1)
                        }
                    }
                    if showProgressTop {
                        Text(progressString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, topSafeArea)
        }
        .overlay(alignment: .bottom) {
            VStack {
                if !showProgressTop {
                    Text(progressString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom)
        }
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig)
                    .presentationDetents([.medium])
                    .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
            case .chapters:
                ChapterListView(document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex in
                    viewModel.setIndex(index: spineIndex, progress: 0)
                    viewModel.activeSheet = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(edges: .top)
        .statusBarHidden(focusMode)
    }
}

struct CircleButton: View {
    let systemName: String
    let interactive: Bool
    
    init(systemName: String, interactive: Bool = true) {
        self.systemName = systemName
        self.interactive = interactive
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(interactive ? .regular.interactive() : .regular)
                .padding(8)
                .contentShape(Circle())
        } else {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .padding(8)
        }
    }
}
