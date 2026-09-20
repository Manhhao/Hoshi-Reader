//
//  SasayakiMatchView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Speech
import SwiftUI
import UniformTypeIdentifiers

struct SasayakiMatchView: View {
    @Environment(\.dismiss) private var dismiss
    
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    
    @State private var useAudio = false
    @State private var isImporting = false
    @State private var subtitleURL: URL?
    @State private var audioURL: URL?
    @State private var characterCount = 0
    @State private var match: SasayakiMatchData?
    @State private var transcript: SasayakiTranscript?
    @State private var showClearTranscript = false
    
    private var canTranscribe: Bool {
        if #available(iOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(fileURL?.lastPathComponent ?? String(localized: "No file selected"))
                            .lineLimit(1)
                        Spacer()
                        Button("Open") {
                            isImporting = true
                        }
                        .disabled(isMatching)
                    }
                    if isMatching {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(progressLabel)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                if let progressDetail {
                                    Text(progressDetail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Pause") {
                            viewModel.pauseSasayakiTranscription()
                        }
                    } else {
                        Button(matchButtonTitle) {
                            start()
                        }
                        .disabled(fileURL == nil)
                    }
                }
                
                if let errorMessage = viewModel.sasayakiError {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                
                if match != nil || transcript != nil {
                    Section("Current Match") {
                        if let match, characterCount > 0 {
                            LabeledContent("Coverage", value: coverage(for: match))
                        }
                        if let transcript, transcript.duration > 0 {
                            LabeledContent("Transcribed") {
                                Text("\(timeString(transcript.through)) / \(timeString(transcript.duration))")
                                    .monospacedDigit()
                            }
                        }
                        if transcript != nil {
                            Button("Clear Transcription", role: .destructive) {
                                showClearTranscript = true
                            }
                            .disabled(isMatching)
                        }
                    }
                }
            }
            .contentMargins(.top, canTranscribe ? 0 : nil, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 12) {
                if canTranscribe {
                    Picker("", selection: $useAudio) {
                        Text("Subtitles").tag(false)
                        Text("Transcription").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isMatching)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
            }
            .alert("Clear transcription?", isPresented: $showClearTranscript) {
                Button("Clear", role: .destructive) {
                    try? viewModel.clearSasayakiTranscript(book: book)
                    transcript = nil
                    viewModel.sasayakiError = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only clears transcription data, match is kept.")
            }
            .navigationTitle(book.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                reloadMatch()
                if canTranscribe, let url = viewModel.loadSasayakiAudioURL(book: book) {
                    audioURL = url
                }
                if isMatching {
                    useAudio = true
                }
            }
            .onDisappear {
                viewModel.pauseSasayakiTranscription()
            }
            .onChange(of: isMatching) { _, running in
                if !running {
                    reloadMatch()
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: allowedTypes) { result in
                if case .success(let url) = result {
                    if useAudio {
                        audioURL = url
                    } else {
                        subtitleURL = url
                    }
                }
            }
        }
    }
    
    private var isMatching: Bool {
        viewModel.sasayakiIsRunning(book)
    }
    
    private var fileURL: URL? {
        useAudio ? audioURL : subtitleURL
    }
    
    private var matchButtonTitle: String {
        guard useAudio, let transcript else {
            return "Match"
        }
        return transcript.through > 0 && !transcript.isComplete ? "Resume" : "Match"
    }
    
    private var allowedTypes: [UTType] {
        let extensions = useAudio ? ["mp3", "m4b", "m4a"] : ["srt", "txt"]
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }
    
    private var progressLabel: String {
        switch viewModel.sasayakiProgress {
        case .downloading(let fraction):
            return "Downloading model… \(Int(fraction * 100))%"
        case .transcribing(let through, let duration, _):
            guard duration > 0 else {
                return "Transcribing…"
            }
            return "Transcribing \(timeString(through)) / \(timeString(duration))"
        case .aligning:
            return "Aligning…"
        case nil:
            return "Matching…"
        }
    }
    
    private var progressDetail: String? {
        guard case .transcribing(_, _, let remaining) = viewModel.sasayakiProgress, let remaining else {
            return nil
        }
        let minutes = Int((remaining / 60).rounded(.up))
        return "about \(minutes) min left"
    }
    
    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
    
    private func coverage(for matchData: SasayakiMatchData) -> String {
        let matched = matchData.matchedCharacters
        let percentage = (Double(matched) / Double(characterCount)) * 100
        return "\(matched)/\(characterCount) (\(String(format: "%.1f%%", percentage)))"
    }
    
    private func start() {
        guard let fileURL else {
            return
        }
        
        viewModel.sasayakiError = nil
        if !useAudio {
            do {
                match = try viewModel.runSasayakiMatch(book: book, srtURL: fileURL)
            } catch {
                viewModel.sasayakiError = error.localizedDescription
            }
        } else if #available(iOS 26.0, *) {
            viewModel.startSasayakiTranscription(book: book, audioURL: fileURL)
        }
    }
    
    private func reloadMatch() {
        guard let root = try? BookStorage.getBooksDirectory().appendingPathComponent(book.folder) else {
            return
        }
        match = BookStorage.loadSasayakiMatch(root: root)
        transcript = BookStorage.loadSasayakiTranscript(root: root)
        characterCount = BookStorage.loadBookInfo(root: root)?.characterCount ?? 0
    }
}
