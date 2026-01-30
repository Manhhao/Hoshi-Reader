//
//  AppearanceView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AppearanceView: View {
    let userConfig: UserConfig
    @Environment(\.dismiss) var dismiss
    
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
                
                Section("Reader") {
                    Toggle("Vertical Writing", isOn: $userConfig.verticalWriting)
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
        }
    }
}
