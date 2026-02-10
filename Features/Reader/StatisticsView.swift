//
//  StatisticsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct StatisticsView: View {
    let viewModel: ReaderViewModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.charsRead.formatted(.number.grouping(.never)))**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.avgSpeed.formatted(.number.grouping(.never))) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.timeRead).formatted())**")
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
                        Text("**0**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**0 / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**00:00:00**")
                    }
                } header: {
                    Text("All Time")
                }
                
                Section("History") {
                    
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
