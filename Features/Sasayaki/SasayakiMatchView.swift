//
//  SasayakiMatchView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct SasayakiMatchView: View {
    @Environment(\.dismiss) private var dismiss
    
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    
    @State private var isImporting = false
    @State private var fileURL: URL?
    @State private var searchWindow: Double = 200
    @State private var isMatching = false
    @State private var match: SasayakiMatchData?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    HStack {
                        Text(fileURL?.lastPathComponent ?? "No file selected")
                            .lineLimit(1)
                        Spacer()
                        Button("Open") {
                            isImporting = true
                        }
                    }
                }
                
                Section {
                    VStack {
                        HStack {
                            Text("Search Window")
                            Spacer()
                            Text("\(Int(searchWindow))")
                                .fontWeight(.semibold)
                        }
                        Slider(value: $searchWindow, in: 50...350, step: 25)
                    }
                    Button {
                        matchFile()
                    } label: {
                        if isMatching {
                            HStack {
                                ProgressView()
                                Text("Matching…")
                            }
                        } else {
                            Text("Match")
                        }
                    }
                    .disabled(fileURL == nil || isMatching)
                }
                
                if let match {
                    Section("Current Match") {
                        LabeledContent("Match Rate", value: matchRate(for: match))
                    }
                }
            }
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                match = viewModel.loadSasayakiMatch(book: book)
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "srt")!]
            ) { result in
                if case .success(let url) = result {
                    fileURL = url
                }
            }
        }
    }
    
    private func matchRate(for matchData: SasayakiMatchData) -> String {
        let matched = matchData.matches.count
        let total = matched + matchData.unmatched
        
        let percentage = total > 0 ? (Double(matched) / Double(total)) * 100 : 0
        return "\(matched)/\(total) (\(String(format: "%.1f%%", percentage)))"
    }
    
    private func matchFile() {
        guard let fileURL else {
            return
        }
        
        isMatching = true
        Task { @MainActor in
            defer { isMatching = false }
            match = try? await viewModel.runSasayakiMatch(
                book: book,
                srtURL: fileURL,
                searchWindow: Int(searchWindow)
            )
        }
    }
}
