//
//  SasayakiSheet.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct SasayakiSheet: View {
    @Environment(UserConfig.self) private var userConfig
    var player: SasayakiPlayer
    let onImportAudio: (URL) throws -> Void
    let onDismiss: () -> Void
    
    @State private var isImportingAudio = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    if player.hasAudio {
                        HStack(spacing: 20) {
                            Button {
                                userConfig.verticalWriting ? player.skip(forward: true) : player.skip(forward: false)
                            } label: {
                                Image(systemName: "15.arrow.trianglehead.counterclockwise")
                            }
                            
                            Button {
                                userConfig.verticalWriting ? player.nextCue() : player.prevCue()
                            } label: {
                                Image(systemName: "backward.fill")
                            }
                            
                            Button {
                                player.togglePlayback()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 30))
                            }
                            
                            Button {
                                userConfig.verticalWriting ? player.prevCue() : player.nextCue()
                            } label: {
                                Image(systemName: "forward.fill")
                            }
                            
                            Button {
                                userConfig.verticalWriting ? player.skip(forward: false) : player.skip(forward: true)
                            } label: {
                                Image(systemName: "15.arrow.trianglehead.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        
                        Text("\(Self.formatTime(player.currentTime)) / \(Self.formatTime(player.duration))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Button("Load Audio") {
                        isImportingAudio = true
                    }
                    
                    if let errorMessage = player.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("Playback") {
                    VStack {
                        HStack {
                            Text("Delay")
                            Spacer()
                            Text(String(format: "%+.2fs", player.delay))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Bindable(player).delay, in: -4...4, step: 0.05)
                    }
                    VStack {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.2fx", player.rate))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Bindable(player).rate, in: 0.5...3, step: 0.05)
                    }
                }
                
                Section("Settings") {
                    Toggle("Show Sasayaki Toggle", isOn: Bindable(userConfig).readerShowSasayakiToggle)
                    Toggle("Auto-Scroll", isOn: Bindable(userConfig).sasayakiAutoScroll)
                    Toggle("Auto-Pause on Lookup", isOn: Bindable(userConfig).sasayakiAutoPause)
                    Toggle("Pause on Images", isOn: Bindable(userConfig).sasayakiImagePause)
                    if userConfig.sasayakiImagePause {
                        HStack {
                            Text("Pause Duration")
                            Spacer()
                            Text("\(Int(userConfig.sasayakiImagePauseDuration))s")
                                .fontWeight(.semibold)
                            Stepper("", value: Bindable(userConfig).sasayakiImagePauseDuration, in: 1...30, step: 1)
                                .labelsHidden()
                        }
                    }
                }
                
                Section("Control Bar") {
                    Toggle("Show Control Bar", isOn: Bindable(userConfig).sasayakiShowControlBar)
                    if userConfig.sasayakiShowControlBar {
                        Toggle("Always Show Control Bar", isOn: Bindable(userConfig).sasayakiAlwaysShowControlBar)
                        HStack {
                            Text("Control Bar Side")
                            Spacer()
                            Picker("", selection: Bindable(userConfig).sasayakiControlBarSide) {
                                Text("Left").tag(SasayakiControlBarSide.left)
                                Text("Right").tag(SasayakiControlBarSide.right)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                }
                
                Section("Light Theme") {
                    ColorPicker("Text Color", selection: Bindable(userConfig).sasayakiTextColor)
                    ColorPicker("Background Color", selection: Bindable(userConfig).sasayakiBackgroundColor)
                }
                
                Section("Dark Theme") {
                    ColorPicker("Text Color", selection: Bindable(userConfig).sasayakiDarkTextColor)
                    ColorPicker("Background Color", selection: Bindable(userConfig).sasayakiDarkBackgroundColor)
                }
            }
            .navigationTitle("Sasayaki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingAudio,
                allowedContentTypes: ["mp3", "m4b", "mp4"].compactMap { UTType(filenameExtension: $0) }
            ) { result in
                guard case .success(let url) = result else { return }
                do {
                    try onImportAudio(url)
                } catch {
                    player.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
