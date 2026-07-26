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
