//
//  VNModeSettingsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct VNModeSettingsView: View {
    @Environment(UserConfig.self) var userConfig
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section("Screen Mode") {
                Picker("Mode", selection: $userConfig.visualNovelScreenMode) {
                    ForEach(VisualNovelScreenMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if userConfig.visualNovelScreenMode == .sentences {
                    HStack {
                        Text("Sentences per Screen")
                        Spacer()
                        Text("\(userConfig.visualNovelSentencesPerScreen)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.visualNovelSentencesPerScreen, in: 1...12)
                            .labelsHidden()
                    }
                    Toggle("Keep Dialogue Together", isOn: $userConfig.visualNovelPreserveDialogueBubbles)
                }
            }

            Section {
                HStack {
                    Text("Reveal Speed")
                    Spacer()
                    Text(userConfig.visualNovelRevealSpeed == 0 ? "Instant" : "\(userConfig.visualNovelRevealSpeed)")
                        .fontWeight(.semibold)
                }
                Slider(value: .init(
                    get: { Double(userConfig.visualNovelRevealSpeed) },
                    set: { userConfig.visualNovelRevealSpeed = Int($0) }
                ), in: 0...120, step: 1)
            } header: {
                Text("Reveal Animation")
            } footer: {
                Text("How quickly text appears on a new screen, in characters per second. Instant shows the full screen immediately.")
            }

            Section("Navigation") {
                Toggle("Tap to Advance", isOn: $userConfig.visualNovelClickAdvance)
            }

            if userConfig.enableSasayaki {
                Section {
                    Toggle("Keep Sasayaki Text Together", isOn: $userConfig.visualNovelMergeCrossScreenSasayakiCues)
                } header: {
                    Text("Sasayaki")
                } footer: {
                    Text("Automatically advance to the next screen when a Sasayaki cue continues onto it.")
                }
            }
        }
        .navigationTitle("Visual Novel Mode")
    }
}
