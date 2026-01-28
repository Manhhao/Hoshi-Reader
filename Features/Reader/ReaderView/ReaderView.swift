//
//  ReaderView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

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
    
    private let webViewPadding: CGFloat = 48
    
    init(document: EPUBDocument, rootURL: URL) {
        _viewModel = State(initialValue: ReaderViewModel(document: document, rootURL: rootURL))
    }
    
    var body: some View {
        // on ipad on first load, the geometry reader includes the safearea at the top
        // if you tab out and tab back in, the area recalculates causing the reader to be misaligned
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topSafeArea + webViewPadding)
                .contentShape(Rectangle())
            
            GeometryReader { geometry in
                ZStack {
                    VerticalWebView(
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
                    .id("\(userConfig.fontSize)-\(userConfig.horizontalPadding)-\(userConfig.verticalPadding)-\(Int(geometry.size.width))x\(Int(geometry.size.height))")
                    
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
        }
        .onAppear {
            // swiftui bug? if the button is pressed too quickly after opening a book, the menu slides to the top of the screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                viewModel.markReady()
            }
            
            if topSafeArea == 0 {
                topSafeArea = UIApplication.topSafeArea
            }
        }
        .overlay(alignment: .top) {
            VStack {
                if let title = viewModel.document.title {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .lineLimit(1)
                }
                Text("\(viewModel.currentCharacter) / \(viewModel.bookInfo.characterCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, topSafeArea)
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Circle()
                    .fill(.clear)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "chevron.left")
                    }
                    .onTapGesture {
                        dismiss()
                    }
                
                Spacer()
                
                // TODO: half of the button does nothing
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
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(!viewModel.ready)
            }
        }
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig)
                    .presentationDetents([.medium])
            case .chapters:
                ChapterListView(document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex in
                    viewModel.setIndex(index: spineIndex, progress: 0)
                    viewModel.activeSheet = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(edges: .top)
        .statusBarHidden()
    }
}
