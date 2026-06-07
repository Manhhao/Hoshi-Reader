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
    let fontManager = FontManager.shared
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var textView: UITextView?
    
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
                    textView = uiTextView
                }
        }
    }
    
    private var toolbar: some View {
        HStack {
            fontMenu
                .conditionalGlassEffect()
            dictionaryMenu
                .conditionalGlassEffect()
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
                .conditionalGlassEffect()
            }
        }
        .padding(8)
    }
    
    private var dictionaryMenu: some View {
        Menu {
            ForEach(dictionaryManager.termDictionaries) { dict in
                Button(dict.index.title) {
                    insertText("""
                    [data-dictionary="\(dict.index.title)"] {
                        
                    }
                    
                    """)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.ja")
                Text("Selector")
            }
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(height: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
    
    private var fontMenu: some View {
        Menu {
            ForEach(fontManager.allFonts, id: \.self) { fontName in
                Button(fontName) {
                    let cssFontName = fontManager.cssFontName(name: fontName)
                    insertText("font-family: \"\(cssFontName)\" !important;")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "textformat.size.larger.ja")
                Text("Font")
            }
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(height: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
    
    private func insertText(_ insertedText: String) {
        guard let textView else {
            text += insertedText
            return
        }
        
        textView.insertText(insertedText)
        text = textView.text
    }
}
