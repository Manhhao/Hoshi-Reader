//
//  CSSEditorView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct CSSEditorView: View {
    let dictionaryManager = DictionaryManager.shared
    let fontManager = FontManager.shared
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    fontMenu
                    dictionaryMenu
                    Spacer()
                    Button("Done") { isFocused = false }
                }
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
            Image(systemName: "character.book.closed.ja")
        }
    }
    
    private var fontMenu: some View {
        Menu {
            ForEach(fontManager.allFonts, id: \.self) { fontName in
                Button(fontName) {
                    text += "font-family: \"\(fontName)\";"
                }
            }
        } label: {
            Image(systemName: "textformat.size.larger.ja")
        }
    }
}
