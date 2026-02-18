//
//  CSSEditorView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import SwiftUIIntrospect

struct CSSEditorView: View {
    let dictionaryManager = DictionaryManager.shared
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .introspect(.textEditor, on: .iOS(.v18, .v26)) { uiTextView in
                    uiTextView.smartQuotesType = .no
                    uiTextView.smartDashesType = .no
                }
        }
    }
    
    @ViewBuilder
    private var toolbar: some View {
        if #available(iOS 26, *) {
            HStack {
                dictionaryMenu
                    .glassEffect(.regular.interactive())
                Spacer()
                if isFocused {
                    Button {
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        } else {
            HStack {
                dictionaryMenu
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                if isFocused {
                    Button {
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
    
    private var dictionaryMenu: some View {
        Menu {
            ForEach(dictionaryManager.termDictionaries) { dict in
                Button(dict.name) {
                    text += """
                    [data-dictionary="\(dict.name)"] {
                        
                    }
                    
                    """
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.ja")
                Text("Insert Selector")
            }
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(height: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}
