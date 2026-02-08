//
//  CustomSearchField.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SwiftUI

class SearchField: UITextField {
    var targetLanguage: String? // avoid modifying `init`
    var onTransitionComplete: (() -> Void)?
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // get the coordinator of the transition of navigation push
        let transitionCoordinator = self.parentViewController?.transitionCoordinator
        if let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                self.onTransitionComplete?()
            }
        } else {
            self.onTransitionComplete?()
        }
    }
    
    override var textInputMode: UITextInputMode? {
        guard let targetLanguage else {
            return super.textInputMode
        }
        
        // add explanation in PrivacyInfo.xcprivacy
        for inputMode in UITextInputMode.activeInputModes {
            if let lang = inputMode.primaryLanguage, lang.hasPrefix(targetLanguage) {
                return inputMode
            }
        }
        
        return super.textInputMode
    }
}

struct CustomSearchField: UIViewRepresentable {
    @Binding var searchText: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let searchField = SearchField()
        searchField.text = searchText
        searchField.targetLanguage = "ja"
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        searchField.delegate = context.coordinator
        searchField.onTransitionComplete = { [weak searchField] in
            if context.coordinator.isFocused {
                searchField?.becomeFirstResponder()
            }
        }
        return searchField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.updateSelf(searchText: $searchText, isFocused: $isFocused)
        
        // detect `isFocused` after the first `updateUIView` search field and the navigation push
        if uiView.window != nil {
            if isFocused {
                uiView.becomeFirstResponder()
            } else {
                uiView.resignFirstResponder()
            }
        }
        
        if uiView.text != searchText{
            uiView.text = searchText
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(searchText: $searchText, isFocused: $isFocused, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var searchText: String
        @Binding var isFocused: Bool
        let onSubmit: () -> Void
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused {
                isFocused = true
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            isFocused = false
            return true
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            searchText = textField.text ?? ""
            onSubmit()
        }
        
        init(searchText: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self._searchText = searchText
            self._isFocused = isFocused
            self.onSubmit = onSubmit
        }
        
        func updateSelf(searchText: Binding<String>, isFocused: Binding<Bool>) {
            self._searchText = searchText
            self._isFocused = isFocused
        }
    }
    
}

// MARK: - Extensions

extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = responder as? UIViewController {
                return vc
            }
            responder = r.next
        }
        return nil
    }
}
