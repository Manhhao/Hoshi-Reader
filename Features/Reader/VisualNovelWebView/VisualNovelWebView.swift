//
//  VisualNovelWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import WebKit
import SwiftUI
import UIKit

struct VisualNovelWebView: UIViewRepresentable {
    let userConfig: UserConfig
    let viewSize: CGSize
    let bridge: WebViewBridge
    let textColor: String?
    let sasayakiTextColor: Color
    let sasayakiBackgroundColor: Color
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onSaveBookmark: (Double) -> Void
    var onInternalLink: (URL) -> Bool
    var onInternalJump: (Double) -> Void
    var onTextSelected: ((SelectionData) -> Int?)
    var onTapOutside: (() -> Void)
    var hasOpenPopups: (() -> Bool)
    var onPageTurn: (() -> Void)
    var onRestoreCompleted: (() -> Void)
    var onHighlightCreated: (HighlightColor, HighlightData) -> Void
    var onImageTapped: (URL) -> Void
    let maxSelectionLength: Int = 16
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "restoreCompleted")
        config.userContentController.add(context.coordinator, name: "selectionState")
        config.userContentController.add(context.coordinator, name: "imageTapped")
        config.userContentController.add(context.coordinator, name: "jsDebugError")
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        
        let webView = HoshiWKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        if UIDevice.current.userInterfaceIdiom == .pad {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        
        let coordinator = context.coordinator
        webView.onHighlightCreated = { [weak coordinator, weak webView] color, creation in
            coordinator?.parent.onHighlightCreated(color, creation)
            // Only this screen's highlights survive a re-render (see
            // reapplyPendingHighlights() in visualnovel.js). Register the new one right
            // away, so navigating away and back does not lose it this session.
            guard let coordinator, let webView else { return }
            let textLiteral = coordinator.javaScriptStringLiteral(creation.text)
            let idLiteral = coordinator.javaScriptStringLiteral(creation.id.uuidString)
            let colorLiteral = coordinator.javaScriptStringLiteral(color.rawValue)
            webView.evaluateJavaScript("window.hoshiReader.registerHighlight({ id: \(idLiteral), color: \(colorLiteral), offset: \(creation.offset), text: \(textLiteral) })") { _, _ in }
        }
        
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        swipeLeft.cancelsTouchesInView = false
        swipeLeft.delaysTouchesEnded = false
        webView.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        swipeRight.cancelsTouchesInView = false
        swipeRight.delaysTouchesEnded = false
        webView.addGestureRecognizer(swipeRight)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.require(toFail: swipeLeft)
        tap.require(toFail: swipeRight)
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        webView.addGestureRecognizer(tap)
        
        context.coordinator.webView = webView
        
        webView.alpha = 0
        
        WebViewPreloader.shared.close()
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        
        if !bridge.pendingCommands.isEmpty {
            let commands = bridge.pendingCommands
            bridge.pendingCommands.removeAll()
            for command in commands {
                switch command {
                case .loadChapter(let url, let progress, let fragment, let sasayakiCues, let highlights):
                    context.coordinator.currentURL = url
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = fragment
                    context.coordinator.pendingSasayakiCues = sasayakiCues
                    context.coordinator.pendingHighlights = highlights
                    if let appDirectory = try? BookStorage.getAppDirectory() {
                        webView.alpha = 0
                        webView.loadFileURL(url, allowingReadAccessTo: appDirectory)
                    }
                case .restoreProgress(let progress):
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = nil
                    context.coordinator.shouldSyncProgressAfterRestore = false
                    webView.evaluateJavaScript("window.hoshiReader.restoreProgress(\(progress))") { _, _ in }
                case .jumpToFragment(let fragment):
                    context.coordinator.jumpToFragment(fragment)
                case .clearSelection:
                    context.coordinator.clearSelection()
                case .updateTextColor(let hex):
                    if let hex {
                        webView.evaluateJavaScript("document.documentElement.style.setProperty('--hoshi-text-color', '\(hex)')") { _, _ in }
                    } else {
                        webView.evaluateJavaScript("document.documentElement.style.removeProperty('--hoshi-text-color')") { _, _ in }
                    }
                case .updateSasayakiColors(let textHex, let backgroundHex):
                    webView.evaluateJavaScript("""
                        document.documentElement.style.setProperty('--hoshi-sasayaki-text-color', '\(textHex)');
                        document.documentElement.style.setProperty('--hoshi-sasayaki-background-color', '\(backgroundHex)');
                    """) { _, _ in }
                case .applySasayakiCues(let cues, let completion):
                    webView.evaluateJavaScript("window.hoshiReader.applySasayakiCues(\(cues))") { _, _ in completion?() }
                case .highlightSasayakiCue(let id, let reveal):
                    let revealFlag = reveal ? "true" : "false"
                    let cue = context.coordinator.javaScriptStringLiteral(id)
                    webView.evaluateJavaScript("window.hoshiReader.highlightSasayakiCue(\(cue), \(revealFlag))") { result, _ in
                        if let progress = result as? Double {
                            onPageTurn()
                            onSaveBookmark(progress)
                        }
                    }
                case .clearSasayakiCue:
                    webView.evaluateJavaScript("window.hoshiReader.clearSasayakiCue()") { _, _ in }
                case .removeHighlight(let id):
                    let literal = context.coordinator.javaScriptStringLiteral(id)
                    webView.evaluateJavaScript("window.hoshiHighlights.removeHighlight(\(literal)); window.hoshiReader.unregisterHighlight(\(literal));") { _, _ in }
                }
            }
            return
        }
        
        if context.coordinator.currentURL == nil, let url = bridge.chapterURL {
            context.coordinator.currentURL = url
            context.coordinator.pendingProgress = bridge.progress
            context.coordinator.pendingFragment = nil
            context.coordinator.pendingSasayakiCues = bridge.sasayakiCues
            context.coordinator.pendingHighlights = bridge.highlights
            guard let appDirectory = try? BookStorage.getAppDirectory() else { return }
            webView.alpha = 0
            webView.loadFileURL(url, allowingReadAccessTo: appDirectory)
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "restoreCompleted")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "selectionState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageTapped")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "jsDebugError")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
        var parent: VisualNovelWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        var pendingProgress: Double = 0
        var pendingFragment: String?
        var pendingSasayakiCues: String?
        var pendingHighlights: String?
        var shouldSyncProgressAfterRestore = false
        
        init(_ parent: VisualNovelWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "jsDebugError" {
                NSLog("[HoshiVNDebug] JS error: %@", "\(message.body)")
                return
            }
            if message.name == "selectionState" {
                if let hasSelection = message.body as? Bool, let hv = message.webView as? HoshiWKWebView {
                    hv.hasSelection = hasSelection
                }
                return
            }
            if message.name == "imageTapped" {
                if let src = message.body as? String, let url = URL(string: src) {
                    parent.onImageTapped(url)
                }
                return
            }
            if message.name == "restoreCompleted" {
                if shouldSyncProgressAfterRestore {
                    shouldSyncProgressAfterRestore = false
                    syncLinkJumpProgress()
                }
                UIView.animate(withDuration: 0.25) {
                    message.webView?.alpha = 1
                }
                parent.onRestoreCompleted()
            }
            if message.name == "textSelected" {
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String,
                      let sentence = body["sentence"] as? String,
                      let rectData = body["rect"] as? [String: Any],
                      let x = rectData["x"] as? CGFloat,
                      let y = rectData["y"] as? CGFloat,
                      let w = rectData["width"] as? CGFloat,
                      let h = rectData["height"] as? CGFloat else {
                    return
                }
                let rect = CGRect(x: x, y: y, width: w, height: h)
                let normalizedOffset = body["normalizedOffset"] as? Int
                let selectionData = SelectionData(text: text, sentence: sentence, rect: rect, normalizedOffset: normalizedOffset)
                
                if let highlightCount = parent.onTextSelected(selectionData) {
                    highlightSelection(count: highlightCount)
                }
            }
        }
        
        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            if handleInternalLink(url: url) {
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        private var selectionJs: String {
            guard let url = Bundle.main.url(forResource: "selection", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        private var visualNovelJs: String {
            guard let url = Bundle.main.url(forResource: "visualnovel", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        private var highlightsJs: String {
            guard let url = Bundle.main.url(forResource: "highlights", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pageHeight = Int(parent.viewSize.height)
            let pageWidth = Int(parent.viewSize.width)
            
            let verticalPadding = Double(parent.userConfig.verticalPadding)
            let horizontalPadding = Double(parent.userConfig.horizontalPadding)
            
            let writingMode = parent.userConfig.verticalWriting ? "vertical-rl" : "horizontal-tb"
            
            let imgWidth = "calc(\(100 - horizontalPadding)vw - 1px)"
            let imgHeight = "\(100 - verticalPadding)vh"
            
            // VN always shows a single screen flush against the container edges (unlike
            // a full chapter, where only its very first/last line is at this edge), so
            // reserve room for vertical-writing furigana overhang on both the leading and
            // trailing side rather than just the trailing side like the other two modes do.
            let verticalFuriganaReserve = parent.userConfig.verticalWriting ? parent.userConfig.fontSize / 2 : 0
            let furiganaReserveCss = verticalFuriganaReserve > 0
            ? "padding-top: calc(\(verticalPadding / 2)vh + \(verticalFuriganaReserve)px) !important; padding-bottom: calc(\(verticalPadding / 2)vh + \(verticalFuriganaReserve)px) !important;"
            : ""
            
            let textColorCss = """
            @media (prefers-color-scheme: light) { :root { --hoshi-text-color: #000; } }
            @media (prefers-color-scheme: dark) { :root { --hoshi-text-color: #fff; } }
            html, body { color: var(--hoshi-text-color) !important; }
            """
            
            let textColorOverrideJs: String = {
                guard let hex = parent.textColor else { return "" }
                return "document.documentElement.style.setProperty('--hoshi-text-color', '\(hex)');"
            }()
            
            var fontFaceCss = ""
            if let fontURL = try? FontManager.shared.fontUrl(name: parent.userConfig.selectedFont, verticalWriting: parent.userConfig.verticalWriting) {
                fontFaceCss = """
                @font-face {
                    font-family: \(parent.userConfig.selectedFont);
                    src: url('\(fontURL.absoluteString)');
                }
                """
            }
            
            var textSpacingCss = ""
            var paragraphSpacingCss = ""
            if parent.userConfig.layoutAdvanced {
                textSpacingCss = """
                line-height: \(parent.userConfig.lineHeight) !important;
                letter-spacing: \((parent.userConfig.characterSpacing / 100.0))em !important;
                """
                if parent.userConfig.verticalWriting {
                    paragraphSpacingCss = """
                    p {
                        margin-right: \(parent.userConfig.paragraphSpacing)em !important;
                        margin-left: \(parent.userConfig.paragraphSpacing)em !important;
                    }
                    """
                } else {
                    paragraphSpacingCss = """
                    p {
                        margin-top: \(parent.userConfig.paragraphSpacing)em !important;
                        margin-bottom: \(parent.userConfig.paragraphSpacing)em !important;
                    }
                    """
                }
            }
            
            var gridCss = ""
            if !parent.userConfig.justifyText {
                gridCss = """
                text-align: start !important;
                hanging-punctuation: allow-end !important;
                line-break: strict !important;
                """
            }
            
            let css = """
            \(fontFaceCss)
            :root {
                --hoshi-sasayaki-text-color: \(UIColor(parent.sasayakiTextColor).hexString);
                --hoshi-sasayaki-background-color: \(UIColor(parent.sasayakiBackgroundColor).hexString);
            }
            html {
                overflow: hidden !important;
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                margin: 0 !important;
                padding: 0 !important;
                writing-mode: \(writingMode) !important;
            }
            body {
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                margin: 0 !important;
                padding: 0 !important;
                writing-mode: \(writingMode) !important;
                /* A screen's content can be taller/wider than the viewport, so scroll
                   instead of clipping with overflow:hidden, or text is lost off-screen. */
                overflow-y: \(parent.userConfig.verticalWriting ? "hidden" : "auto") !important;
                overflow-x: \(parent.userConfig.verticalWriting ? "auto" : "hidden") !important;
                font-family: \(parent.userConfig.selectedFont), serif !important;
                font-size: \(parent.userConfig.fontSize)px !important;
                -webkit-text-size-adjust: none !important;
                \(textSpacingCss)
                box-sizing: border-box !important;
                padding: \(verticalPadding / 2)vh \(horizontalPadding / 2)vw !important;
                \(furiganaReserveCss)
                display: flex !important;
                align-items: center !important;
                /* justify-content:center is left out on purpose: centering a flex item
                   on an overflowing scroll axis clips its ends instead of letting them
                   stay reachable by scrolling. */
                \(gridCss)
            }
            /* Matches Android's reader.css: the stage gets its height/width from the same
               CSS custom properties as html/body above, an absolute value rather than a
               percentage of its flex parent, which turned out unreliable under
               vertical-writing-mode. justify-content:center only turns on through
               .hoshi-vn-media-screen (set by renderScreen() for a media-only screen),
               since a text screen must stay reachable by scrolling, per the comment on
               body above. */
            .hoshi-vn-stage {
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                box-sizing: border-box !important;
                display: flex !important;
                align-items: center !important;
            }
            .hoshi-vn-stage.hoshi-vn-media-screen {
                justify-content: center !important;
            }
            img.block-img {
                max-width: \(imgWidth) !important;
                max-height: \(imgHeight) !important;
                width: auto !important;
                height: auto !important;
                display: block !important;
                margin: auto !important;
                object-fit: contain !important;
            }
            svg {
                max-width: \(imgWidth) !important;
                max-height: \(imgHeight) !important;
                width: 100% !important;
                height: 100% !important;
                display: block !important;
                margin: auto !important;
            }
            .blur-wrapper {
                display: table;
                margin: auto;
                line-height: 0;
                overflow: hidden;
            }
            img.block-img.blurred,
            svg.blurred {
                filter: blur(24px) !important;
                clip-path: inset(0);
            }
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            a {
                color: rgba(66, 108, 245, 1) !important;
            }
            ruby > rt, ruby > rp {
                -webkit-user-select: none;
            }
            .hoshi-sasayaki-cue.hoshi-sasayaki-active {
                color: var(--hoshi-sasayaki-text-color) !important;
                background-color: var(--hoshi-sasayaki-background-color) !important;
            }
            \(HighlightColor.css)
            \(paragraphSpacingCss)
            \(textColorCss)
            """
            
            let sasayakiSetupScript: String = {
                if let cues = pendingSasayakiCues {
                    return "window.hoshiReader.applySasayakiCues(\(cues));"
                }
                return ""
            }()
            pendingSasayakiCues = nil
            
            let highlightsSetupScript: String = {
                if let highlights = pendingHighlights {
                    // Also stashed on window.hoshiReader: renderScreen() re-applies this
                    // list on every screen switch, since only one screen's content is
                    // ever on the stage for applyHighlights() to find at a time.
                    return "window.hoshiReader.pendingHighlights = \(highlights); window.hoshiHighlights.applyHighlights(\(highlights));"
                }
                return ""
            }()
            pendingHighlights = nil
            
            let initialRestoreScript: String = {
                if let fragment = pendingFragment {
                    shouldSyncProgressAfterRestore = true
                    return "window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)));"
                }
                shouldSyncProgressAfterRestore = false
                return "window.hoshiReader.restoreProgress(\(self.pendingProgress));"
            }()
            pendingFragment = nil
            
            let vnSettings = """
            {
                screenMode: '\(parent.userConfig.visualNovelScreenMode.rawValue)',
                sentencesPerScreen: \(parent.userConfig.visualNovelSentencesPerScreen),
                preserveDialogueBubbles: \(parent.userConfig.visualNovelPreserveDialogueBubbles),
                revealSpeed: \(parent.userConfig.visualNovelRevealSpeed),
                clickAdvance: \(parent.userConfig.visualNovelClickAdvance),
                mergeCrossScreenSasayakiCues: \(parent.userConfig.visualNovelMergeCrossScreenSasayakiCues)
            }
            """
            
            let script = """
            (function() {
              try {
                const viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }

                const newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);
                
                document.documentElement.style.setProperty('--page-height', '\(pageHeight)px');
                document.documentElement.style.setProperty('--page-width', '\(pageWidth)px');
                
                const style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);
                \(textColorOverrideJs)
                
                window.scanNonJapaneseText = \(parent.userConfig.scanNonJapaneseText);
                \(selectionJs)
                \(visualNovelJs)
                \(highlightsJs)
                window.hoshiReader.registerCopyText();
                
                if (\(parent.userConfig.readerHideFurigana)) {
                    document.querySelectorAll('rt').forEach(rt => rt.remove());
                }
                
                // wrap text not in spans inside ruby elements in spans to fix highlighting
                document.querySelectorAll('ruby').forEach(ruby => {
                    [...ruby.childNodes].forEach(node => {
                        if (node.nodeType !== Node.TEXT_NODE) {
                            return;
                        }
                        if (node.textContent.trim()) {
                            const span = document.createElement('span');
                            span.textContent = node.textContent;
                            node.replaceWith(span);
                        } else {
                            node.remove();
                        }
                    });
                });
                
                function setupImage(element, src, wrap, blurElement = element) {
                    let target = element;
                    if (\(parent.userConfig.blurImages)) {
                        blurElement.classList.add('blurred');
                        if (wrap) {
                            target = document.createElement('div');
                            target.className = 'blur-wrapper';
                            blurElement.before(target);
                            target.append(blurElement);
                        }
                    }
                    // No target.onclick here on purpose. VN mode clones every media element
                    // fresh on each screen render, and cloneNode does not copy an .onclick
                    // handler, only attributes and classes. The delegated listener below on
                    // body keeps working no matter how many times its target gets cloned.
                }
                
                document.body.addEventListener('click', function(event) {
                    const svg = event.target.closest('svg');
                    const img = !svg ? event.target.closest('img.block-img') : null;
                    const target = svg || img;
                    if (!target) {
                        return;
                    }
                    if (target.classList.contains('blurred')) {
                        event.preventDefault();
                        event.stopPropagation();
                        target.classList.remove('blurred');
                        return;
                    }
                    const svgImage = svg ? svg.querySelector('image') : null;
                    const src = svg ? (svgImage ? svgImage.href.baseVal : null) : img.src;
                    if (!src) {
                        return;
                    }
                    event.preventDefault();
                    event.stopPropagation();
                    webkit.messageHandlers.imageTapped.postMessage(new URL(src, document.baseURI).href);
                });
                
                document.querySelectorAll('svg[preserveAspectRatio="none"]').forEach(svg => svg.removeAttribute('preserveAspectRatio'));
                document.querySelectorAll('svg').forEach(svg => {
                    const svgImage = svg.querySelector('image');
                    if (!svgImage) {
                        return;
                    }
                    setupImage(svgImage, svgImage.href.baseVal, false, svg);
                });
                
                const images = document.querySelectorAll('img');
                const imagePromises = Array.from(images).map(img => {
                    return new Promise(resolve => {
                        function processImg() {
                            const isGaiji = img.classList.contains('gaiji') || img.classList.contains('gaiji-line');
                            if (!isGaiji && (img.naturalWidth > 256 || img.naturalHeight > 256)) {
                                img.classList.add('block-img');
                                setupImage(img, img.src, true);
                            }
                            resolve();
                        }
                        if (img.complete && img.naturalWidth > 0) {
                            processImg();
                        } else {
                            img.onload = processImg;
                            img.onerror = () => resolve();
                        }
                    });
                });
                
                // If even one <img> never fires load or error, Promise.all would hang
                // forever and the loading spinner would stay stuck. Racing against a
                // timeout means one stuck image just misses sizing/blurring, instead
                // of blocking the whole chapter from rendering.
                Promise.race([
                    Promise.all(imagePromises),
                    new Promise(resolve => setTimeout(resolve, 4000))
                ]).then(() => {
                    return new Promise(resolve => setTimeout(resolve, 50));
                }).then(() => {
                    window.hoshiReader.buildScreens(\(vnSettings));
                    window.hoshiReader.buildNodeOffsets();
                    \(sasayakiSetupScript)
                    \(highlightsSetupScript)
                    \(initialRestoreScript)
                }).catch(function(e) {
                    webkit.messageHandlers.jsDebugError.postMessage('async: ' + (e && e.stack ? e.stack : String(e)));
                });
              } catch (e) {
                webkit.messageHandlers.jsDebugError.postMessage('sync: ' + (e && e.stack ? e.stack : String(e)));
              }
            })();
            """
            
            // A JS syntax error stops the whole script, including the try/catch whose
            // only job is reporting through jsDebugError. A discarded completionHandler
            // would swallow that case silently. NSLog here does not depend on the
            // page's own error path, which could be the broken part.
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    NSLog("[HoshiVNDebug] evaluateJavaScript failed: %@", "\(error)")
                }
            }
        }
        
        private func navigate(_ direction: NavigationDirection) {
            guard let webView = webView else { return }
            
            clearSelection()
            parent.onPageTurn()
            
            let script = "window.hoshiReader.paginate('\(direction == .forward ? "forward" : "backward")')"
            
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self = self else { return }
                
                if let res = result as? String, res == "scrolled" {
                    self.saveBookmark()
                } else {
                    let chapterChanged = direction == .forward ? self.parent.onNextChapter() : self.parent.onPreviousChapter()
                    if chapterChanged {
                        webView.alpha = 0
                    }
                }
            }
        }
        
        @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
            navigate(parent.userConfig.verticalWriting ? .backward : .forward)
        }
        
        @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
            navigate(parent.userConfig.verticalWriting ? .forward : .backward)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let webView = webView else {
                return
            }
            
            if (webView as? HoshiWKWebView)?.hasSelection == true {
                return
            }
            
            let point = gesture.location(in: webView)
            let maxLength = parent.maxSelectionLength
            
            // A tap always finishes an in-progress reveal first (never runs a lookup
            // against a screen that's still mid-reveal); only a tap once revealed
            // falls through to normal selection/tap-outside/click-advance handling.
            let script = """
            (function() {
                if (window.hoshiReader.completeRevealIfActive && window.hoshiReader.completeRevealIfActive()) {
                    return 'revealed';
                }
                return window.hoshiSelection.selectText(\(point.x), \(point.y), \(maxLength));
            })()
            """
            
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                if let status = result as? String, status == "revealed" {
                    return
                }
                if result is NSNull || result == nil {
                    // A tap with nothing selected could mean "advance the page" or "close
                    // the popup I just opened". Check for an open popup first, or click
                    // advance would turn the page instead of closing it.
                    if self.parent.hasOpenPopups() {
                        self.parent.onTapOutside()
                    } else if self.parent.userConfig.visualNovelClickAdvance {
                        self.navigate(.forward)
                    } else {
                        self.parent.onTapOutside()
                    }
                }
            }
        }
        
        func saveBookmark() {
            fetchCurrentProgress { [weak self] progress in
                guard let self else { return }
                self.parent.onSaveBookmark(progress)
            }
        }
        
        func jumpToFragment(_ fragment: String) {
            guard let webView = webView else {
                return
            }
            shouldSyncProgressAfterRestore = true
            let script = "window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)))"
            webView.evaluateJavaScript(script) { _, _ in }
        }
        
        private func syncLinkJumpProgress() {
            fetchCurrentProgress { [weak self] progress in
                guard let self else { return }
                self.parent.onInternalJump(progress)
            }
        }
        
        private func fetchCurrentProgress(_ completion: @escaping (Double) -> Void) {
            guard let webView = webView else {
                return
            }
            
            webView.evaluateJavaScript("window.hoshiReader.calculateProgress()") { result, _ in
                guard let progress = result as? Double else {
                    return
                }
                completion(progress)
            }
        }
        
        func javaScriptStringLiteral(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "'\(escaped)'"
        }
        
        @discardableResult
        private func handleInternalLink(url: URL) -> Bool {
            if url.isFileURL {
                return parent.onInternalLink(url)
            }
            
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }
            if scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                return true
            }
            return false
        }
        
        func highlightSelection(count: Int) {
            guard let webView = webView else {
                return
            }
            
            webView.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(count))") { _, _ in }
        }
        
        func clearSelection() {
            guard let webView = webView else {
                return
            }
            webView.evaluateJavaScript("window.hoshiSelection.clearSelection()") { _, _ in }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if otherGestureRecognizer is UILongPressGestureRecognizer {
                return false
            }
            return true
        }
    }
}
