//
//  AppearanceView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AppearanceView: View {
    let userConfig: UserConfig
    let showDismiss: Bool
    @Environment(\.dismiss) var dismiss
    @State private var isImportingFont = false
    @State private var importedFonts: [String] = []
    @State private var downloadingFont: String? = nil
    @State private var showingDeleteConfirmation = false
    @State private var fontToDelete: String? = nil
    
    var body: some View {
        @Bindable var userConfig = userConfig
        let fontSelection = Binding<String>(
            get: { userConfig.selectedFont },
            set: { newFont in
                guard downloadingFont == nil else { return }
                
                guard FontManager.downloadableFonts.contains(newFont),
                      !FontManager.shared.hasDownloadedFont(name: newFont) else {
                    userConfig.selectedFont = newFont
                    return
                }
                
                let previousFont = userConfig.selectedFont
                downloadingFont = newFont
                
                Task {
                    let success = await FontManager.downloadFont(newFont)
                    downloadingFont = nil
                    userConfig.selectedFont = success ? newFont : previousFont
                }
            }
        )
        NavigationStack {
            List {
                Section("Theme") {
                    Picker("Appearance", selection: $userConfig.theme) {
                        ForEach(Themes.allCases, id: \.self) { mode in
                            Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if userConfig.theme == .system {
                        Toggle("Use Sepia as Light Theme", isOn: $userConfig.systemLightSepia)
                    }
                    if userConfig.theme == .custom {
                        Picker("Interface", selection: $userConfig.uiTheme) {
                            Text("System").tag(Themes.system)
                            Text("Light").tag(Themes.light)
                            Text("Dark").tag(Themes.dark)
                        }
                        ColorPicker("Background Color", selection: $userConfig.customBackgroundColor)
                        ColorPicker("Text Color", selection: $userConfig.customTextColor)
                        ColorPicker("Info Color", selection: $userConfig.customInfoColor)
                    }
                }
                
                Section("Text") {
                    HStack {
                        Text("Text Orientation")
                        Spacer()
                        Picker("", selection: $userConfig.verticalWriting) {
                            Text("縦").tag(true)
                            Text("横").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                    
                    HStack {
                        Picker("Font", selection: fontSelection) {
                            ForEach(FontManager.defaultFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(FontManager.downloadableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(importedFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .disabled(downloadingFont != nil)
                        
                        if !FontManager.shared.isDefaultFont(name: userConfig.selectedFont) {
                            Button {
                                fontToDelete = userConfig.selectedFont
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("", isPresented: $showingDeleteConfirmation, titleVisibility: .hidden) {
                                Button("Delete", role: .destructive) {
                                    if let fontName = fontToDelete {
                                        try? FontManager.shared.deleteFont(name: fontName)
                                        userConfig.selectedFont = FontManager.defaultFonts[0]
                                        importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                                    }
                                }
                            } message: {
                                if let fontName = fontToDelete {
                                    Text("Delete \"\(fontName)\"?")
                                }
                            }
                        }
                        
                        if downloadingFont != nil {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    
                    Button {
                        isImportingFont = true
                    } label: {
                        Text("Import Font")
                    }
                    .fileImporter(
                        isPresented: $isImportingFont,
                        allowedContentTypes: [.font],
                        onCompletion: { result in
                            if case .success(let url) = result {
                                FontManager.shared.importFont(from: url)
                                importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                            }
                        }
                    )
                    
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(userConfig.fontSize)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.fontSize, in: 16...40)
                            .labelsHidden()
                    }
                    
                    Toggle("Hide Furigana", isOn: $userConfig.readerHideFurigana)
                }
                
                Section("Layout") {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Picker("", selection: $userConfig.continuousMode) {
                            Text("Paginated").tag(false)
                            Text("Continuous").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    
                    if userConfig.continuousMode {
                        VStack {
                            HStack {
                                Text("Chapter Swipe Distance")
                                Spacer()
                                Text("\(userConfig.chapterSwipeDistance)")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: .init(
                                get: { Double(userConfig.chapterSwipeDistance) },
                                set: { userConfig.chapterSwipeDistance = Int($0) }
                            ), in: 10...60, step: 5)
                        }
                    }
                    
                    HStack {
                        Text("Horizontal Padding")
                        Spacer()
                        Text("\(userConfig.horizontalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.horizontalPadding, in: 0...50, step: 1)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Vertical Padding")
                        Spacer()
                        Text("\(userConfig.verticalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.verticalPadding, in: 0...50, step: 1)
                            .labelsHidden()
                    }
                    
                    Toggle("Avoid Page Break", isOn: $userConfig.avoidPageBreak)
                    
                    Toggle("Justify Text", isOn: $userConfig.justifyText)
                    
                    Toggle("Advanced", isOn: $userConfig.layoutAdvanced)
                    if userConfig.layoutAdvanced {
                        VStack {
                            HStack {
                                Text("Line Height")
                                Spacer()
                                Text("\(userConfig.lineHeight, specifier: "%.2f")")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $userConfig.lineHeight, in: 1.0...2.5, step: 0.05)
                        }
                        VStack {
                            HStack {
                                Text("Character Spacing")
                                Spacer()
                                Text("\(Int(userConfig.characterSpacing))%")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $userConfig.characterSpacing, in: -10...10, step: 1)
                        }
                    }
                }
                
                Section("Display") {
                    Toggle("Show Title", isOn: $userConfig.readerShowTitle)
                    Toggle("Show Character Count", isOn: $userConfig.readerShowCharacters)
                    Toggle("Show Percentage", isOn: $userConfig.readerShowPercentage)
                    
                    if userConfig.readerShowCharacters || userConfig.readerShowPercentage {
                        HStack {
                            Text("Progress Position")
                            Spacer()
                            Picker("", selection: $userConfig.readerShowProgressTop) {
                                Text("Top").tag(true)
                                Text("Bottom").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                    
                    if userConfig.enableStatistics {
                        Toggle("Show Statistics Toggle", isOn: $userConfig.readerShowStatisticsToggle)
                        Toggle("Show Reading Speed", isOn: $userConfig.readerShowReadingSpeed)
                        Toggle("Show Reading Time", isOn: $userConfig.readerShowReadingTime)
                    }
                    
                    if userConfig.enableSasayaki {
                        Toggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                    }
                }
                
                Section("Popup") {
                    VStack {
                        HStack {
                            Text("Width")
                            Spacer()
                            Text("\(userConfig.popupWidth)")
                                .fontWeight(.semibold)
                        }
                        Slider(value: .init(
                            get: { Double(userConfig.popupWidth) },
                            set: { userConfig.popupWidth = Int($0) }
                        ), in: 100...700, step: 10)
                        
                        HStack {
                            Text("Height")
                            Spacer()
                            Text("\(userConfig.popupHeight)")
                                .fontWeight(.semibold)
                        }
                        Slider(value: .init(
                            get: { Double(userConfig.popupHeight) },
                            set: { userConfig.popupHeight = Int($0) }
                        ), in: 100...500, step: 10)
                    }
                    
                    Toggle("Full-width", isOn: Bindable(userConfig).popupFullWidth)
                    
                    Toggle("Swipe to Dismiss", isOn: Bindable(userConfig).popupSwipeToDismiss)
                    if userConfig.popupSwipeToDismiss {
                        VStack {
                            HStack {
                                Text("Swipe Threshold")
                                Spacer()
                                Text("\(userConfig.popupSwipeThreshold)")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: .init(
                                get: { Double(userConfig.popupSwipeThreshold) },
                                set: { userConfig.popupSwipeThreshold = Int($0) }
                            ), in: 20...80, step: 5)
                        }
                    }
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showDismiss {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .onAppear {
                importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
            }
        }
    }
}
