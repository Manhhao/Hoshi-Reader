//
//  ContentsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum ContentsTab: CaseIterable, Identifiable {
    case chapters
    case highlights
    case gallery
    var id: Self { self }
    
    var title: LocalizedStringKey {
        switch self {
        case .chapters: "Chapters"
        case .highlights: "Highlights"
        case .gallery: "Gallery"
        }
    }
}

struct ContentsView: View {
    @Bindable var viewModel: ReaderViewModel
    let readerTheme: ColorScheme
    let onImageSelected: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showJumpToAlert = false
    @State private var showInvalidInputAlert = false
    @State private var jumpToInput = ""
    @State private var detent: PresentationDetent = .medium
    
    private var progressText: String {
        progressLabel(viewModel.currentCharacter, viewModel.bookInfo.characterCount)
    }
    
    private var chapterProgressText: String {
        let chapter = viewModel.currentChapterRange
        return progressLabel(chapter.character, chapter.total)
    }
    
    private func progressLabel(_ character: Int, _ total: Int) -> String {
        let percent = total > 0 ? (Double(character) / Double(total) * 100) : 0
        return "\(character) / \(total) (\(String(format: "%.1f%%", percent)))"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(progressText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                detent = .large
                                jumpToInput = ""
                                showJumpToAlert = true
                            } label: {
                                Image(systemName: "arrow.right.to.line")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        Text(chapterProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("", selection: $viewModel.contentsTab) {
                        ForEach(ContentsTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                content
                    .frame(maxHeight: .infinity)
                    .contentMargins(.top, 0, for: .scrollContent)
            }
            .navigationTitle(viewModel.book.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .preferredColorScheme(readerTheme)
        .alert("Jump to", isPresented: $showJumpToAlert) {
            TextField("Character count", text: $jumpToInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                if let count = Int(jumpToInput), count >= 0 {
                    jump { viewModel.jumpToCharacter(count) }
                } else {
                    showInvalidInputAlert = true
                }
            }
        }
        .alert("Invalid input", isPresented: $showInvalidInputAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid character count")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.contentsTab {
        case .chapters:
            ChapterListView(
                document: viewModel.document,
                bookInfo: viewModel.bookInfo,
                currentCharacter: viewModel.currentCharacter
            ) { spineIndex, fragment in
                jump { viewModel.jumpToChapter(index: spineIndex, fragment: fragment) }
            }
        case .highlights:
            HighlightListView(
                document: viewModel.document,
                bookInfo: viewModel.bookInfo,
                highlights: viewModel.highlights,
                onJump: { highlight in
                    jump { viewModel.jumpToCharacter(highlight.character) }
                },
                onDelete: { highlight in
                    viewModel.removeHighlight(highlight)
                }
            )
        case .gallery:
            GalleryView(images: viewModel.imageURLs) { url in
                onImageSelected(url)
            }
        }
    }
    
    private func jump(_ action: () -> Void) {
        action()
        viewModel.activeSheet = nil
        viewModel.clearSelection()
        viewModel.closePopups()
    }
}
