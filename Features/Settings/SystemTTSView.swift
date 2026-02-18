//
//  SystemTTSView.swift
//  Hoshi Reader
//
//  Copyright © 2026 liulifox233.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import AVFoundation

struct SystemTTSView: View {
    @Environment(UserConfig.self) var userConfig
    @Environment(\.dismiss) var dismiss
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    
    var body: some View {
        List {
            Section {
                ForEach(availableVoices, id: \.identifier) { voice in
                    VoiceRow(voice: voice, isAdded: isVoiceAdded(voice)) {
                        toggleVoice(voice)
                    }
                }
            } header: {
                Text("Japanese Voices")
            } footer: {
                Text("Eloquence voices are recommended for accurate pitch accent. Other voices may have intonation issues.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("System TTS Voices")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVoices()
        }
    }
    
    private func loadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "ja") }
        
        availableVoices = voices.sorted { v1, v2 in
            let isV1Eloquence = v1.identifier.hasPrefix("com.apple.eloquence")
            let isV2Eloquence = v2.identifier.hasPrefix("com.apple.eloquence")
            
            if isV1Eloquence != isV2Eloquence {
                return isV1Eloquence
            }
            
            return v1.name < v2.name
        }
    }
    
    private func isVoiceAdded(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let idPart = "voiceId=\(voice.identifier)"
        return userConfig.audioSources.contains { $0.url.contains(idPart) }
    }
    
    private func toggleVoice(_ voice: AVSpeechSynthesisVoice) {
        let idPart = "voiceId=\(voice.identifier)"
        
        if let index = userConfig.audioSources.firstIndex(where: { $0.url.contains(idPart) }) {
            userConfig.audioSources.remove(at: index)
        } else {
            let url = "tts://system?voiceId=\(voice.identifier)&term={term}&reading={reading}"
            userConfig.audioSources.append(AudioSource(name: voice.name, url: url))
        }
    }
}

struct VoiceRow: View {
    let voice: AVSpeechSynthesisVoice
    let isAdded: Bool
    let onSelect: () -> Void
    
    private var isEloquence: Bool {
        voice.identifier.hasPrefix("com.apple.eloquence")
    }
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Button {
                    TTSManager.shared.preview(voice: voice)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 30, weight: .thin))
                }
                .buttonStyle(.borderless)
                .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(voice.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        if !isEloquence {
                            QualityBadge(text: "Intonation Issues", color: .orange, icon: "exclamationmark.triangle.fill")
                        } else {
                            QualityBadge(text: "Accurate", color: .green, icon: "checkmark.shield.fill")
                        }
                    }
                    
                    Text(voice.identifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                if isAdded {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct QualityBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
        )
    }
}
