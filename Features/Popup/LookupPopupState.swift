//
//  LookupPopupState.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CYomitanDicts

struct PopupItem: Identifiable {
    let id: UUID = UUID()
    var showPopup: Bool
    var currentSelection: SelectionData?
    var lookupResults: [LookupResult] = []
    var dictionaryStyles: [String: String] = [:]
    var isVertical: Bool
    var clearHighlightTrigger: Int = 0
}

private let popupAnimationSpeed: Double = 2.25

@MainActor
func appendLookupPopup(to popups: inout [PopupItem], selection: SelectionData, maxResults: Int, isVertical: Bool) -> Int? {
    let lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults)
    guard let firstResult = lookupResults.first else {
        return nil
    }
    
    var dictionaryStyles: [String: String] = [:]
    for style in LookupEngine.shared.getStyles() {
        dictionaryStyles[String(style.dict_name)] = String(style.styles)
    }
    
    popups.append(PopupItem(
        showPopup: false,
        currentSelection: selection,
        lookupResults: lookupResults,
        dictionaryStyles: dictionaryStyles,
        isVertical: isVertical
    ))
    
    withAnimation(.default.speed(popupAnimationSpeed)) {
        popups[popups.count - 1].showPopup = true
    }
    
    return String(firstResult.matched).count
}

@MainActor
func closeLookupPopups(_ popups: inout [PopupItem]) {
    withAnimation(.default.speed(popupAnimationSpeed)) {
        for index in popups.indices {
            popups[index].showPopup = false
        }
    }
}

@MainActor
func closeChildLookupPopups(_ popups: inout [PopupItem], parent: Int) {
    withAnimation(.default.speed(popupAnimationSpeed)) {
        for index in popups.indices.dropFirst(parent + 1) {
            popups[index].showPopup = false
        }
    }
}

@MainActor
func closeLookupPopupBranch(_ popups: inout [PopupItem], from index: Int) {
    withAnimation(.default.speed(popupAnimationSpeed)) {
        for popupIndex in popups.indices.dropFirst(index) {
            popups[popupIndex].showPopup = false
        }
    }
}

func visibleLookupPopupAncestor(in popups: [PopupItem], before index: Int) -> Int? {
    guard index > 0 else {
        return nil
    }
    
    for popupIndex in stride(from: index - 1, through: 0, by: -1) {
        if popups[popupIndex].showPopup {
            return popupIndex
        }
    }
    
    return nil
}

func markLookupPopupHighlightForClearing(_ popups: inout [PopupItem], at index: Int) {
    guard popups.indices.contains(index) else {
        return
    }
    popups[index].clearHighlightTrigger = popups[index].clearHighlightTrigger &+ 1
}
