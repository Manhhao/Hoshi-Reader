//
//  StatisticsSheet.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct StatisticsSheet: View {
    let viewModel: ReaderViewModel
    
    private var chapterCharactersRemaining: Int {
        let range = viewModel.currentChapterRange
        return range.total - range.character
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.currentSession.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.currentSession.readingSpeed) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.currentSession.readingTime).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Book:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.currentSession.timeToRead(viewModel.bookInfo.characterCount - viewModel.currentCharacter)).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Chapter:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.currentSession.timeToRead(chapterCharactersRemaining)).formatted())**")
                    }
                } header: {
                    HStack {
                        Text("Session")
                        if !viewModel.isTracking {
                            Button {
                                viewModel.startTracking()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Button {
                                viewModel.stopTracking()
                            } label: {
                                Image(systemName: "pause.fill")
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.todaysTotal.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.todaysTotal.readingSpeed) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.todaysTotal.readingTime).formatted())**")
                    }
                } header: {
                    Text("Today")
                }
                
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.allTimeTotal.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.allTimeTotal.readingSpeed) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.allTimeTotal.readingTime).formatted())**")
                    }
                } header: {
                    Text("All Time")
                }
            }
            .monospacedDigit()
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.activeSheet = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
