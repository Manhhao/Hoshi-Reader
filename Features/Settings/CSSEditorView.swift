//
//  CSSEditorView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

struct CSSEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocus: Bool
    
    init(text: Binding<String>, isFocus: Binding<Bool>) {
        self._text = text
        self._isFocus = isFocus
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        let coordinator = context.coordinator
        textView.delegate = coordinator
        
        let toolBar = UIToolbar()
        let resetButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: coordinator, action: #selector(Coordinator.resetCSS))
        let spacerItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let toolBarDoneItem = UIBarButtonItem(title: "Done", style: .plain, target: coordinator, action: #selector(Coordinator.dismissKeyboard))
        toolBar.items = [resetButtonItem, spacerItem, toolBarDoneItem]
        toolBar.sizeToFit()
        toolBar.backgroundColor = .clear
        textView.inputAccessoryView = toolBar
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        
        if text != uiView.text {
            uiView.text = text
        }
        
        if isFocus {
            if !uiView.isFirstResponder {
                Task {
                    uiView.becomeFirstResponder()
                }
            }
        } else {
            if uiView.isFirstResponder {
                Task {
                    uiView.resignFirstResponder()
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CSSEditorView
        var scrollTask: Task<Void, any Error>?
        
        init(parent: CSSEditorView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocus {
                parent.isFocus = true
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }
            
            var selectedRange: NSRange?
            if #available(iOS 26, *) {
                selectedRange = textView.selectedRanges.first
            } else {
                selectedRange = textView.selectedRange
            }
            
            if let selectedRange, scrollTask == nil {
                scrollTask = Task {
                    textView.scrollRangeToVisible(selectedRange)
                    try? await Task.sleep(for: .seconds(0.3))
                    scrollTask = nil
                }
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocus {
                parent.isFocus = false
            }
        }
        
        @objc
        func dismissKeyboard() {
            parent.isFocus = false
        }
        
        @objc
        func resetCSS() {
            parent.text = DictionaryInfo.defaultCSS
        }
    }
}

struct PreviewView: View {
    @State var text = ""
    @State var focus = false
    @State var showSheet = false
    
    var body: some View {
        Group {
            Button("show sheet") {
                showSheet = true
            }
        }
        .sheet(isPresented: $showSheet) {
            CSSEditorView(text: $text, isFocus: $focus)
                .presentationDetents([.large])
                .padding()
        }
    }
}

#Preview {
    PreviewView()
}
