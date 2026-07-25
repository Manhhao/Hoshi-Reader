//
//  SearchFieldLanguage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import ObjectiveC
import UIKit

private let inputLanguageClassPrefix = "HoshiInputLanguage_"

extension UISearchBar {
    static var currentSearchTextField: UITextField? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            var pending: [UIView] = [window]
            while let view = pending.popLast() {
                if let searchBar = view as? UISearchBar {
                    return searchBar.searchTextField
                }
                pending.append(contentsOf: view.subviews)
            }
        }
        return nil
    }
}

extension UITextField {
    func setPreferredInputLanguage(_ language: String) {
        let currentClass: AnyClass = object_getClass(self)!
        let currentName = NSStringFromClass(currentClass)
        guard !currentName.hasPrefix(inputLanguageClassPrefix) else { return }
        
        let name = inputLanguageClassPrefix + language + "_" + currentName
        object_setClass(self, NSClassFromString(name) ?? Self.makeInputLanguageSubclass(named: name, of: currentClass, language: language))
        if isFirstResponder {
            reloadInputViews()
        }
    }
    
    private static func makeInputLanguageSubclass(named name: String, of superclass: AnyClass, language: String) -> AnyClass {
        let subclass: AnyClass = objc_allocateClassPair(superclass, name, 0)!
        let inputMode: @convention(block) (UIResponder) -> UITextInputMode? = { _ in
            UITextInputMode.activeInputModes.first { $0.primaryLanguage?.hasPrefix(language) == true }
        }
        class_addMethod(
            subclass,
            #selector(getter: UIResponder.textInputMode),
            imp_implementationWithBlock(inputMode),
            "@@:"
        )
        objc_registerClassPair(subclass)
        return subclass
    }
}
