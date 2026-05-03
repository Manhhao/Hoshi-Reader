//
//  DictionarySearchView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CHoshiDicts

struct DictionarySearchView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query: String = ""
    @State private var lastQuery: String = ""
    @State private var content: String = ""
    @State private var dictionaryStyles: [String: String] = [:]
    @State private var lookupEntries: [[String: Any]] = []
    @State private var hasSearched = false
    @State private var searchFocused = false
    @State private var didInitialQuery = false
    @State private var popups: [PopupItem] = []
    @State private var clearSelection: Bool = false
    @State private var backCount: Int = 0
    @State private var forwardCount: Int = 0
    @State private var backTrigger: Bool = false
    @State private var forwardTrigger: Bool = false
    var initialQuery: String = ""
    var initialAutofocus: Bool = true
    var shouldFocus: Bool = false
    
    private var usesTopTabBarLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    private var searchBarInset: CGFloat {
        usesTopTabBarLayout ? 100 : 50
    }
    
    private var tabBarInset: CGFloat {
        usesTopTabBarLayout ? 0 : 45
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PopupWebView(
                    content: content,
                    position: .zero,
                    clearSelection: clearSelection,
                    dictionaryStyles: dictionaryStyles,
                    lookupEntries: lookupEntries,
                    scanNonJapaneseText: userConfig.scanNonJapaneseText,
                    backTrigger: backTrigger,
                    forwardTrigger: forwardTrigger,
                    onMine: { minedContent in
                        await AnkiManager.shared.addNote(content: minedContent, context: MiningContext(sentence: lastQuery, documentTitle: nil, coverURL: nil))
                    },
                    onTextSelected: {
                        closePopups()
                        return handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: false, isFullWidth: false)
                    },
                    onTapOutside: closePopups,
                    onRedirect: { query in
                        closePopups()
                        let results = LookupEngine.shared.lookup(query, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength)
                        let entries = Self.buildLookupEntries(lookupResults: results)
                        if !entries.isEmpty {
                            backCount += 1
                            forwardCount = 0
                        }
                        return entries
                    }
                )
                .id(lastQuery)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            
                            guard abs(dx) > abs(dy) && abs(dy) < 20 else { return }
                            
                            if dx > 0 {
                                guard backCount > 0 else { return }
                                backTrigger.toggle()
                                backCount -= 1
                                forwardCount += 1
                            } else {
                                guard forwardCount > 0 else { return }
                                forwardTrigger.toggle()
                                forwardCount -= 1
                                backCount += 1
                            }
                        }
                )
                
                ForEach($popups) { $popup in
                    let popupId = popup.id
                    PopupView(
                        userConfig: userConfig,
                        isVisible: $popup.showPopup,
                        selectionData: popup.currentSelection,
                        lookupResults: popup.lookupResults,
                        dictionaryStyles: popup.dictionaryStyles,
                        screenSize: geometry.size,
                        isVertical: popup.isVertical,
                        isFullWidth: popup.isFullWidth,
                        topInset: UIApplication.topSafeArea + searchBarInset,
                        bottomInset: max(UIApplication.bottomSafeArea, 30) + tabBarInset,
                        coverURL: nil,
                        documentTitle: nil,
                        clearSelection: popup.clearSelection,
                        onTextSelected: {
                            if let index = popups.firstIndex(where: { $0.id == popupId }) {
                                closeChildPopups(parent: index)
                            }
                            return handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: false, isFullWidth: false)
                        },
                        onTapOutside: {
                            if let index = popups.firstIndex(where: { $0.id == popupId }) {
                                closeChildPopups(parent: index)
                            }
                        },
                        onSwipeDismiss: {
                            guard let index = popups.firstIndex(where: { $0.id == popupId }),
                                  popups.indices.contains(index) else {
                                return
                            }
                            if index == 0 {
                                clearSelection.toggle()
                                closePopups()
                            } else if popups.indices.contains(index - 1) {
                                popups[index - 1].clearSelection.toggle()
                                closeChildPopups(parent: index - 1)
                            }
                        }
                    )
                    .zIndex(Double(100 + (popups.firstIndex(where: { $0.id == popupId }) ?? 0)))
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color(.systemBackground), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: UIApplication.topSafeArea + 50)
                .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .top) {
            DictionarySearchBar(text: $query, isFocused: $searchFocused) {
                runLookup()
            }
        }
        .onChange(of: shouldFocus) {
            searchFocused = true
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
        backCount = 0
        forwardCount = 0
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSearched = true
        lastQuery = trimmed
        
        guard !trimmed.isEmpty else {
            content = ""
            lookupEntries = []
            dictionaryStyles = [:]
            return
        }
        
        let results = LookupEngine.shared.lookup(trimmed, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength)
        if results.isEmpty {
            content = ""
            lookupEntries = []
            dictionaryStyles = [:]
            return
        }
        
        let styles = LookupEngine.shared.getStyles()
        constructHtml(results: results, styles: styles)
    }
    
    private func handleTextSelection(_ selection: SelectionData, maxResults: Int, scanLength: Int,  isVertical: Bool, isFullWidth: Bool) -> Int? {
        let lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults, scanLength: scanLength)
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
            isFullWidth: isFullWidth,
            clearSelection: false
        )
        popups.append(popup)
        
        if let firstResult = lookupResults.first {
            withAnimation(.default.speed(2.2)) {
                popups = popups.map {
                    var p = $0
                    if p.id == popup.id {
                        p.showPopup = true
                    }
                    return p
                }
            }
            return String(firstResult.matched).count
        }
        return nil
    }
    
    private func closePopups() {
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2.4)) {
            for index in popups.indices {
                popups[index].showPopup = false
            }
        } completion: {
            popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    private func closeChildPopups(parent: Int) {
        var popupIds: Set<UUID> = []
        withAnimation(.default.speed(2.4)) {
            for index in popups.indices.dropFirst(parent + 1) {
                popups[index].showPopup = false
                popupIds.insert(popups[index].id)
            }
        } completion: {
            popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    private func constructHtml(results: [LookupResult], styles: [DictionaryStyle]) {
        dictionaryStyles = [:]
        for style in styles {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        lookupEntries = Self.buildLookupEntries(lookupResults: results)
        
        let collapsedDictionaries = userConfig.collapseMode == .custom
        ? ((try? JSONEncoder().encode(DictionaryManager.shared.collapsedDictionaries))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]") : "[]"
        let audioSources = (try? JSONEncoder().encode(userConfig.enabledAudioSources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let customCSS = (try? JSONSerialization.data(withJSONObject: userConfig.customCSS, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        
        content = """
        <style>.overlay { padding-bottom: 90px; }</style>
        <script>
            window.collapseMode = "\(userConfig.collapseMode.rawValue)";
            window.expandFirstDictionary = \(userConfig.expandFirstDictionary);
            window.collapsedDictionaries = \(collapsedDictionaries);
            window.compactGlossaries = \(userConfig.compactGlossaries);
            window.showExpressionTags = \(userConfig.showExpressionTags);
            window.harmonicFrequency = \(userConfig.harmonicFrequency);
            window.deduplicatePitchAccents = \(userConfig.deduplicatePitchAccents);
            window.compactPitchAccents = \(userConfig.compactPitchAccents);
            window.audioSources = \(audioSources);
            window.audioEnableAutoplay = \(userConfig.audioEnableAutoplay);
            window.audioPlaybackMode = "\(userConfig.audioPlaybackMode.rawValue)";
            window.needsAudio = \(AnkiManager.shared.needsAudio);
            window.allowDupes = \(AnkiManager.shared.allowDupes);
            window.useAnkiConnect = \(AnkiManager.shared.useAnkiConnect);
            window.embedMedia = \(AnkiManager.shared.embedMedia);
            window.compactGlossariesAnki = \(AnkiManager.shared.compactGlossaries);
            window.customCSS = \(customCSS);
        </script>
        <div style="height: 50px;"></div>
        <div id="entries-container" style="min-height: 100vh;"></div>
        """
    }
    
    private static func buildLookupEntries(lookupResults: [LookupResult]) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        for result in lookupResults {
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.reversed().map {
                [
                    "name": String($0.name),
                    "description": String($0.description),
                ]
            }
            
            var glossaries: [[String: Any]] = []
            for glossary in result.term.glossaries {
                glossaries.append([
                    "dictionary": String(glossary.dict_name),
                    "content": String(glossary.glossary),
                    "definitionTags": String(glossary.definition_tags),
                    "termTags": String(glossary.term_tags),
                ])
            }
            
            var frequencies: [[String: Any]] = []
            for frequency in result.term.frequencies {
                var frequencyTags: [[String: Any]] = []
                for frequencyTag in frequency.frequencies {
                    frequencyTags.append([
                        "value": Int(frequencyTag.value),
                        "displayValue": String(frequencyTag.display_value),
                    ])
                }
                frequencies.append([
                    "dictionary": String(frequency.dict_name),
                    "frequencies": frequencyTags,
                ])
            }
            
            var pitches: [[String: Any]] = []
            for pitchEntry in result.term.pitches {
                var pitchPositions: [Int] = []
                for element in pitchEntry.pitch_positions {
                    let position = Int(element)
                    if !pitchPositions.contains(position) {
                        pitchPositions.append(position)
                    }
                }
                pitches.append([
                    "dictionary": String(pitchEntry.dict_name),
                    "pitchPositions": pitchPositions,
                ])
            }
            
            let rules = String(result.term.rules).split(separator: " ").map { String($0) }
            
            entries.append([
                "expression": expression,
                "reading": reading,
                "matched": matched,
                "deinflectionTrace": deinflectionTrace,
                "glossaries": glossaries,
                "frequencies": frequencies,
                "pitches": pitches,
                "rules": rules,
            ])
        }
        return entries
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        else {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                CustomSearchField(searchText: $text, isFocused: $isFocused, onSubmit: onSubmit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
            .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .contentShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
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
