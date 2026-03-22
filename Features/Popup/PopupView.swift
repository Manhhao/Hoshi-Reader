//
//  PopupView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CHoshiDicts

struct PopupLayout {
    let selectionRect: CGRect
    let screenSize: CGSize
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let isVertical: Bool
    let isFullWidth: Bool
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    
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
    
    private var spaceAbove: CGFloat {
        selectionRect.minY - topInset - popupPadding
    }
    
    private var spaceBelow: CGFloat {
        screenSize.height - bottomInset - selectionRect.maxY - popupPadding
    }
    
    private var showBelow: Bool {
        spaceBelow >= spaceAbove
    }
    
    var width: CGFloat {
        if isFullWidth {
            return screenSize.width - screenBorderPadding * 2
        }
        
        if isVertical {
            return min(max(spaceLeft, spaceRight) - screenBorderPadding, maxWidth)
        }
        
        return min(screenSize.width - screenBorderPadding * 2, maxWidth)
    }
    
    var height: CGFloat {
        if isVertical || isFullWidth {
            return maxHeight
        }
        
        return min(max(spaceAbove, spaceBelow) - screenBorderPadding, maxHeight)
    }
    
    var position: CGPoint {
        var x: CGFloat
        var y: CGFloat
        
        if isFullWidth {
            x = width / 2 + screenBorderPadding
            y = screenSize.height - height / 2 - screenBorderPadding
        } else {
            if isVertical {
                if showOnRight {
                    x = selectionRect.maxX + popupPadding + (width / 2)
                } else {
                    x = selectionRect.minX - popupPadding - (width / 2)
                }
                x = max(width / 2, min(x, screenSize.width - width / 2))
                
                y = selectionRect.minY + (height / 2)
                y = max(height / 2 + screenBorderPadding + topInset, min(y, screenSize.height - bottomInset - height / 2 - screenBorderPadding))
            } else {
                x = selectionRect.minX + (width / 2)
                x = max(width / 2 + screenBorderPadding, min(x, screenSize.width - width / 2 - screenBorderPadding))
                
                if showBelow {
                    y = selectionRect.maxY + popupPadding + (height / 2)
                } else {
                    y = selectionRect.minY - popupPadding - (height / 2)
                }
                y = max(height / 2 + topInset, min(y, screenSize.height - bottomInset - height / 2))
            }
        }
        return CGPoint(x: x, y: y)
    }
}

struct PopupView: View {
    @Environment(UserConfig.self) private var userConfig
    @Binding var isVisible: Bool
    let selectionData: SelectionData?
    let lookupResults: [LookupResult]
    let dictionaryStyles: [String: String]
    let screenSize: CGSize
    let isVertical: Bool
    let isFullWidth: Bool
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let coverURL: URL?
    let documentTitle: String?
    var clearHighlight: Bool
    var onTextSelected: ((SelectionData) -> Int?)?
    var onTapOutside: (() -> Void)?
    var onSwipeDismiss: (() -> Void)?
    
    private var layout: PopupLayout? {
        guard let selectionData else {
            return nil
        }
        
        let result = PopupLayout(
            selectionRect: selectionData.rect,
            screenSize: screenSize,
            maxWidth: CGFloat(userConfig.popupWidth),
            maxHeight: CGFloat(userConfig.popupHeight),
            isVertical: isVertical,
            isFullWidth: isFullWidth,
            topInset: topInset,
            bottomInset: bottomInset
        )
        
        guard result.width.isFinite,
              result.height.isFinite,
              result.position.x.isFinite,
              result.position.y.isFinite else {
            return nil
        }
        
        return result
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                if isVisible, let selectionData, let layout {
                    PopupWebView(
                        content: constructHtml(selectionData: selectionData),
                        position: CGPoint(x: layout.position.x - layout.width / 2, y: layout.position.y - layout.height / 2),
                        clearHighlight: clearHighlight,
                        onMine: { content in
                            AnkiManager.shared.addNote(content: content, context: MiningContext(sentence: selectionData.sentence, documentTitle: documentTitle, coverURL: coverURL))
                        },
                        onTextSelected: onTextSelected,
                        onTapOutside: onTapOutside,
                        onSwipeDismiss: onSwipeDismiss
                    )
                    .frame(width: max(1, layout.width), height: max(1, layout.height))
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    .position(layout.position)
                }
            }
        } else {
            if isVisible, let selectionData, let layout {
                PopupWebView(
                    content: constructHtml(selectionData: selectionData),
                    position: CGPoint(x: layout.position.x - layout.width / 2, y: layout.position.y - layout.height / 2),
                    clearHighlight: clearHighlight,
                    onMine: { content in
                        AnkiManager.shared.addNote(content: content, context: MiningContext(sentence: selectionData.sentence, documentTitle: documentTitle, coverURL: coverURL))
                    },
                    onTextSelected: onTextSelected,
                    onTapOutside: onTapOutside,
                    onSwipeDismiss: onSwipeDismiss
                )
                .frame(width: max(1, layout.width), height: max(1, layout.height))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                .position(layout.position)
            }
        }
    }
    
    private func constructHtml(selectionData: SelectionData) -> String {
        var entries: [EntryData] = []
        
        for result in lookupResults {
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.reversed().map { DeinflectionTag(name: String($0.name), description: String($0.description)) }
            
            var glossaries: [GlossaryData] = []
            for glossary in result.term.glossaries {
                glossaries.append(GlossaryData(
                    dictionary: String(glossary.dict_name),
                    content: String(glossary.glossary),
                    definitionTags: String(glossary.definition_tags),
                    termTags: String(glossary.term_tags)
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
            
            var pitches: [PitchData] = []
            for pitchEntry in result.term.pitches {
                var pitchPositions: [Int] = []
                for element in pitchEntry.pitch_positions {
                    let position = Int(element)
                    if !pitchPositions.contains(position) {
                        pitchPositions.append(position)
                    }
                }
                pitches.append(PitchData(dictionary: String(pitchEntry.dict_name), pitchPositions: pitchPositions))
            }
            
            let rules = String(result.term.rules).split(separator: " ").map { String($0) }
            
            entries.append(EntryData(
                expression: expression,
                reading: reading,
                matched: matched,
                deinflectionTrace: deinflectionTrace,
                glossaries: glossaries,
                frequencies: frequencies,
                pitches: pitches,
                rules: rules
            ))
        }
        
        let styles = (try? JSONEncoder().encode(dictionaryStyles)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entriesJson = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        
        let audioSources = (try? JSONEncoder().encode(userConfig.enabledAudioSources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let customCSS = (try? JSONSerialization.data(withJSONObject: userConfig.customCSS, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        
        return """
        <script>
            window.dictionaryStyles = \(styles);
            window.lookupEntries = \(entriesJson);
            window.collapseDictionaries = \(userConfig.collapseDictionaries);
            window.compactGlossaries = \(userConfig.compactGlossaries);
            window.audioSources = \(audioSources);
            window.audioEnableAutoplay = \(userConfig.audioEnableAutoplay);
            window.audioPlaybackMode = "\(userConfig.audioPlaybackMode.rawValue)";
            window.needsAudio = \(AnkiManager.shared.needsAudio);
            window.allowDupes = \(AnkiManager.shared.allowDupes);
            window.compactGlossariesAnki = \(AnkiManager.shared.compactGlossaries);
            window.customCSS = \(customCSS);
            window.swipeThreshold = \(userConfig.popupSwipeToDismiss ? userConfig.popupSwipeThreshold : 0);
        </script>
        <div id="entries-container"></div>
        """
    }
}
