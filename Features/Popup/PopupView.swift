//
//  PopupView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CYomitanDicts

struct PopupLayout {
    let selectionRect: CGRect
    let screenSize: CGSize
    let maxWidth: CGFloat
    let height: CGFloat
    
    private let popupPadding: CGFloat = 4
    private let screenBorderPadding: CGFloat = 6
    
    private var spaceLeft: CGFloat {
        selectionRect.minX - popupPadding
    }
    
    private var spaceRight: CGFloat {
        screenSize.width - selectionRect.maxX - popupPadding
    }
    
    private var showOnRight: Bool {
        spaceRight >= spaceLeft
    }
    
    var width: CGFloat {
        min(max(spaceLeft, spaceRight) - screenBorderPadding, maxWidth)
    }
    
    var position: CGPoint {
        var x: CGFloat
        if showOnRight {
            x = selectionRect.maxX + popupPadding + (width / 2)
        } else {
            x = selectionRect.minX - popupPadding - (width / 2)
        }
        
        x = max(width / 2, min(x, screenSize.width - width / 2))
        
        var y = selectionRect.minY + (height / 2)
        y = max(height / 2, min(y, screenSize.height - height / 2))
        
        return CGPoint(x: x, y: y)
    }
}

struct PopupView: View {
    @Namespace private var namespace
    @Environment(UserConfig.self) private var userConfig
    @Binding var isVisible: Bool
    let selectionData: SelectionData?
    let lookupResults: [LookupResult]
    let dictionaryStyles: [String: String]
    let screenSize: CGSize
    
    private var layout: PopupLayout? {
        guard let selectionData else {
            return nil
        }
        
        return PopupLayout(
            selectionRect: selectionData.rect,
            screenSize: screenSize,
            maxWidth: CGFloat(userConfig.popupWidth),
            height: CGFloat(userConfig.popupHeight)
        )
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                if isVisible, let selectionData, let layout {
                    PopupWebView(
                        content: constructHtml(selectionData: selectionData),
                        onMine: { content in
                            AnkiManager.shared.addNote(content: content, sentence: selectionData.sentence)
                        }
                    )
                    .frame(width: layout.width, height: layout.height)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    .glassEffectID("popup", in: namespace)
                    .glassEffectTransition(.materialize)
                    .position(layout.position)
                    .animation(nil, value: layout.position)
                }
            }
        } else {
            if isVisible, let selectionData, let layout {
                PopupWebView(
                    content: constructHtml(selectionData: selectionData),
                    onMine: { content in
                        AnkiManager.shared.addNote(content: content, sentence: selectionData.sentence)
                    }
                )
                .frame(width: layout.width, height: layout.height)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .position(layout.position)
                .animation(nil, value: layout.position)
            }
        }
    }

    private func constructHtml(selectionData: SelectionData) -> String {
        var entries: [EntryData] = []
        
        for result in lookupResults {
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.map { DeinflectionTag(name: String($0.name), description: String($0.description)) }
            
            var glossaries: [GlossaryData] = []
            for glossary in result.term.glossaries {
                glossaries.append(GlossaryData(
                    dictionary: String(glossary.dict_name),
                    content: String(glossary.glossary)
                ))
            }
            
            var frequencies: [FrequencyData] = []
            for frequency in result.term.frequencies {
                var frequencyTags: [FrequencyTag] = []
                for frequencyTag in frequency.frequencies {
                    frequencyTags.append(FrequencyTag(value: Int(frequencyTag.value), displayValue: String(frequencyTag.display_value)))
                }
                frequencies.append(FrequencyData(
                    dictionary: String(frequency.dict_name),
                    frequencies: frequencyTags))
            }
            
            entries.append(EntryData(
                expression: expression,
                reading: reading,
                matched: matched,
                deinflectionTrace: deinflectionTrace,
                glossaries: glossaries,
                frequencies: frequencies
            ))
        }
        
        let styles = (try? JSONEncoder().encode(dictionaryStyles)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entriesJson = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        
        return """
        <script>
            window.dictionaryStyles = \(styles);
            window.lookupEntries = \(entriesJson);
            window.collapseDictionaries = \(userConfig.collapseDictionaries);
        </script>
        <div id="entries-container"></div>
        """
    }
}
