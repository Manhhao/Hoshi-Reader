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
    @Environment(\.dismiss) var dismiss
    @State private var isImportingFont = false
    @State private var importedFonts: [String] = []
    @State private var showingDeleteConfirmation = false
    @State private var fontToDelete: String? = nil
    
    var body: some View {
        @Bindable var userConfig = userConfig
        NavigationStack {
            List {
                Section("Theme") {
                    Picker("Appearance", selection: $userConfig.theme) {
                        ForEach(Themes.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if userConfig.theme == .custom {
                        Picker("Interface", selection: $userConfig.uiTheme) {
                            Text("System").tag(Themes.system)
                            Text("Light").tag(Themes.light)
                            Text("Dark").tag(Themes.dark)
                        }
                        ColorPicker("Background Color", selection: $userConfig.customBackgroundColor)
                        ColorPicker("Text Color", selection: $userConfig.customTextColor)
                    }
                }
                
                Section("Reader Layout") {
                    if #available(iOS 26, *) {
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
                    }
                    
                    HStack {
                        Picker("Font", selection: $userConfig.selectedFont) {
                            ForEach(FontManager.defaultFonts + importedFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        
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
                                        importedFonts = (try? FontManager.shared.getFontsFromStorage())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                                    }
                                }
                            } message: {
                                if let fontName = fontToDelete {
                                    Text("Delete \"\(fontName)\"?")
                                }
                            }
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
                                try? FontManager.shared.importFont(from: url)
                                importedFonts = (try? FontManager.shared.getFontsFromStorage())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
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
                    
                    HStack {
                        Text("Horizontal Padding")
                        Spacer()
                        Text("\(userConfig.horizontalPadding)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.horizontalPadding, in: 0...80, step: 2)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Vertical Padding")
                        Spacer()
                        Text("\(userConfig.verticalPadding)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.verticalPadding, in: 0...80, step: 2)
                            .labelsHidden()
                    }
                    
                    Toggle("Hide Furigana", isOn: $userConfig.readerHideFurigana)
                }
                
                Section("Reader Display") {
                    Toggle("Show Title", isOn: $userConfig.readerShowTitle)
                    Toggle("Show Character Count", isOn: $userConfig.readerShowCharacters)
                    Toggle("Show Percentage", isOn: $userConfig.readerShowPercentage)
                    
                    if userConfig.readerShowCharacters || userConfig.readerShowPercentage {
                        HStack {
                            Text("Position")
                            Spacer()
                            Picker("", selection: $userConfig.readerShowProgressTop) {
                                Text("Top").tag(true)
                                Text("Bottom").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
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
                        ), in: 100...500, step: 10)
                        
                        HStack {
                            Text("Height")
                            Spacer()
                            Text("\(userConfig.popupHeight)")
                                .fontWeight(.semibold)
                        }
                        Slider(value: .init(
                            get: { Double(userConfig.popupHeight) },
                            set: { userConfig.popupHeight = Int($0) }
                        ), in: 100...350, step: 10)
                    }
                    
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
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                importedFonts = (try? FontManager.shared.getFontsFromStorage())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
            }
        }
    }
}
