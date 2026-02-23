//
//  DictionarySearchView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CYomitanDicts

struct DictionarySearchView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var query: String = ""
    @State private var lastQuery: String = ""
    @State private var content: String = ""
    @State private var hasSearched = false
    @State private var searchFocused = false
    @State private var didInitialQuery = false
    @State private var popups: [PopupItem] = []
    @State private var clearHighlight: Bool = false
    var initialQuery: String = ""
    var initialAutofocus: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PopupWebView(
                    content: content,
                    position: .zero,
                    clearHighlight: clearHighlight,
                    onMine: { minedContent in
                        AnkiManager.shared.addNote(content: minedContent, context: MiningContext(sentence: lastQuery, documentTitle: nil, coverURL: nil))
                    },
                    onTextSelected: {
                        closePopups()
                        return handleTextSelection($0, maxResults: userConfig.maxResults, isVertical: false)
                    },
                    onTapOutside: closePopups
                )
                .id(lastQuery)
                
                ForEach(Array(popups.enumerated()), id: \.element.id) { index, _ in
                    PopupView(
                        isVisible: $popups[index].showPopup,
                        selectionData: popups[index].currentSelection,
                        lookupResults: popups[index].lookupResults,
                        dictionaryStyles: popups[index].dictionaryStyles,
                        screenSize: geometry.size,
                        isVertical: popups[index].isVertical,
                        coverURL: nil,
                        documentTitle: nil,
                        clearHighlight: popups[index].clearHighlight,
                        onTextSelected: {
                            closeChildPopups(parent: index)
                            return handleTextSelection($0, maxResults: userConfig.maxResults, isVertical: false)
                        },
                        onTapOutside: { closeChildPopups(parent: index) }
                    )
                    .simultaneousGesture(DragGesture().onEnded({ value in
                        if userConfig.popupSwipeToDismiss &&
                            popups[index].showPopup &&
                            (abs(value.translation.width) > CGFloat(userConfig.popupSwipeThreshold)) &&
                            (abs(value.translation.height) < 20) {
                            if index == 0 {
                                clearHighlight.toggle()
                            } else {
                                popups[index - 1].clearHighlight.toggle()
                            }
                            closeChildPopups(parent: index - 1)
                        }
                    }))
                    .zIndex(Double(100 + index))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            DictionarySearchBar(text: $query, isFocused: $searchFocused) {
                runLookup()
            }
        }
        .onAppear {
            if !didInitialQuery && !initialQuery.isEmpty {
                query = initialQuery
                runLookup()
            }
            if initialAutofocus || didInitialQuery {
                searchFocused = false
                Task { @MainActor in
                    searchFocused = true
                }
            } else {
                searchFocused = false
                didInitialQuery = true
            }
        }
    }
    
    private func runLookup() {
        closePopups()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSearched = true
        lastQuery = trimmed
        
        guard !trimmed.isEmpty else {
            content = ""
            return
        }
        
        let results = LookupEngine.shared.lookup(trimmed, maxResults: userConfig.maxResults)
        if results.isEmpty {
            content = ""
            return
        }
        
        let styles = LookupEngine.shared.getStyles()
        content = buildHtml(results: results, styles: styles)
    }
    
    private func handleTextSelection(_ selection: SelectionData, maxResults: Int, isVertical: Bool) -> Int? {
        let lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults)
        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        let popup = PopupItem(
            showPopup: false,
            currentSelection: selection,
            lookupResults: lookupResults,
            dictionaryStyles: dictionaryStyles,
            isVertical: isVertical,
            clearHighlight: false
        )
        popups.append(popup)
        
        if let firstResult = lookupResults.first {
            withAnimation(.default.speed(2)) {
                popups[popups.count - 1].showPopup = true
            }
            return String(firstResult.matched).count
        }
        return nil
    }
    
    private func closePopups() {
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2)) {
            for index in popups.indices {
                popups[index].showPopup = false
            }
        } completion: {
            popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    private func closeChildPopups(parent: Int) {
        var popupIds: Set<UUID> = []
        withAnimation(.default.speed(2)) {
            for index in popups.indices.dropFirst(parent + 1) {
                popups[index].showPopup = false
                popupIds.insert(popups[index].id)
            }
        } completion: {
            popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    private func buildHtml(results: [LookupResult], styles: [DictionaryStyle]) -> String {
        var entries: [EntryData] = []
        
        for result in results {
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.map { DeinflectionTag(name: String($0.name), description: String($0.description)) }
            
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
            
            let definitionTags = String(result.term.definition_tags).split(separator: " ").map { String($0) }
            
            entries.append(EntryData(
                expression: expression,
                reading: reading,
                matched: matched,
                deinflectionTrace: deinflectionTrace,
                glossaries: glossaries,
                frequencies: frequencies,
                pitches: pitches,
                definitionTags: definitionTags
            ))
        }
        
        var dictionaryStyles: [String: String] = [:]
        for style in styles {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        
        let stylesJson = (try? JSONEncoder().encode(dictionaryStyles)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entriesJson = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let audioSources = (try? JSONEncoder().encode(userConfig.enabledAudioSources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let customCSS = (try? JSONSerialization.data(withJSONObject: userConfig.customCSS, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        
        return """
        <script>
            window.dictionaryStyles = \(stylesJson);
            window.lookupEntries = \(entriesJson);
            window.collapseDictionaries = \(userConfig.collapseDictionaries);
            window.compactGlossaries = \(userConfig.compactGlossaries);
            window.audioSources = \(audioSources);
            window.audioEnableAutoplay = \(userConfig.audioEnableAutoplay);
            window.needsAudio = \(AnkiManager.shared.needsAudio);
            window.customCSS = \(customCSS);
        </script>
        <div id="entries-container"></div>
        """
    }
}

struct DictionarySearchBar: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    
    var body: some View {
        if #available(iOS 26, *) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                CustomSearchField(searchText: $text, isFocused: $isFocused, onSubmit: onSubmit)
                
                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive())
            .contentShape(Capsule())
            .padding(.horizontal, 30)
            .padding(.bottom, 4)
        }
        else {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                CustomSearchField(searchText: $text, isFocused: $isFocused, onSubmit: onSubmit)
                
                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }
}

struct CircleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    let interactive: Bool
    let fontSize: CGFloat
    
    init(systemName: String, interactive: Bool = true, fontSize: CGFloat = 20) {
        self.systemName = systemName
        self.interactive = interactive
        self.fontSize = fontSize
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(interactive ? .regular.interactive() : .regular)
                .padding(8)
                .contentShape(Circle())
        } else {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .padding(8)
        }
    }
}
