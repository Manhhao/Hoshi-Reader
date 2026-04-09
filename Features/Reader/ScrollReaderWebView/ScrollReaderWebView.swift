//
//  ScrollReaderWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import WebKit
import SwiftUI
import UIKit

struct ScrollReaderWebView: UIViewRepresentable {
    let userConfig: UserConfig
    let bridge: WebViewBridge
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onSaveBookmark: (Double) -> Void
    var onInternalLink: (URL) -> Bool
    var onInternalJump: (Double) -> Void
    var onTextSelected: ((SelectionData) -> Int?)?
    var onTapOutside: (() -> Void)?
    var onScroll: (() -> Void)?
    var onRestoreCompleted: (() -> Void)?
    let maxSelectionLength: Int = 16
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "restoreCompleted")
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.alwaysBounceVertical = !userConfig.verticalWriting
        webView.scrollView.alwaysBounceHorizontal = userConfig.verticalWriting
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
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
                case .loadChapter(let url, let progress, let fragment, let sasayakiCues):
                    context.coordinator.currentURL = url
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = fragment
                    context.coordinator.pendingSasayakiCues = sasayakiCues
                    if let appDirectory = try? BookStorage.getAppDirectory() {
                        webView.scrollView.delegate = nil
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
                case .clearHighlight:
                    context.coordinator.clearHighlight()
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
                            context.coordinator.parent.onSaveBookmark(progress)
                        }
                    }
                case .clearSasayakiCue:
                    webView.evaluateJavaScript("window.hoshiReader.clearSasayakiCue()") { _, _ in }
                }
            }
            return
        }
        
        if context.coordinator.currentURL == nil, let url = bridge.chapterURL {
            context.coordinator.currentURL = url
            context.coordinator.pendingProgress = bridge.progress
            context.coordinator.pendingFragment = nil
            context.coordinator.pendingSasayakiCues = bridge.sasayakiCues
            guard let appDirectory = try? BookStorage.getAppDirectory() else { return }
            webView.scrollView.delegate = nil
            webView.alpha = 0
            webView.loadFileURL(url, allowingReadAccessTo: appDirectory)
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "restoreCompleted")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: ScrollReaderWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        var pendingProgress: Double = 0
        var pendingFragment: String?
        var pendingSasayakiCues: String?
        var shouldSyncProgressAfterRestore = false
        
        init(_ parent: ScrollReaderWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "restoreCompleted" {
                webView?.scrollView.delegate = self
                if shouldSyncProgressAfterRestore {
                    shouldSyncProgressAfterRestore = false
                    syncLinkJumpProgress()
                }
                UIView.animate(withDuration: 0.25) {
                    message.webView?.alpha = 1
                }
                parent.onRestoreCompleted?()
            }
            else if message.name == "textSelected" {
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
                
                if let highlightCount = parent.onTextSelected?(selectionData) {
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
        
        private var readerJs: String {
            guard let url = Bundle.main.url(forResource: "scrollreader", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.subviews.forEach { subview in
                subview.gestureRecognizers?.forEach { recognizer in
                    if let tapRecognizer = recognizer as? UITapGestureRecognizer,
                       tapRecognizer.numberOfTapsRequired == 2,
                       tapRecognizer.numberOfTouchesRequired == 1 {
                        subview.removeGestureRecognizer(recognizer)
                    }
                }
            }
            
            let writingMode = parent.userConfig.verticalWriting ? "vertical-rl" : "horizontal-tb"
            
            let textColorCss = """
            @media (prefers-color-scheme: light) { :root { --hoshi-text-color: #000; } }
            @media (prefers-color-scheme: dark) { :root { --hoshi-text-color: #fff; } }
            html, body { color: var(--hoshi-text-color) !important; }
            """
            
            let textColorOverrideJs: String = {
                guard parent.userConfig.theme == .custom else { return "" }
                let hex = UIColor(parent.userConfig.customTextColor).hexString
                return "document.documentElement.style.setProperty('--hoshi-text-color', '\(hex)');"
            }()
            
            var fontFaceCss = ""
            if !FontManager.shared.isDefaultFont(name: parent.userConfig.selectedFont) {
                if let fontURL = try? FontManager.shared.getFontUrl(name: parent.userConfig.selectedFont) {
                    let fontType = fontURL.pathExtension.lowercased()
                    fontFaceCss = """
                    @font-face {
                        font-family: '\(parent.userConfig.selectedFont)';
                        src: url('\(fontURL.absoluteString)') format('\(fontType == "otf" ? "opentype" : "truetype")');
                    }
                    """
                }
            }
            
            var textSpacingCss = ""
            if parent.userConfig.layoutAdvanced {
                textSpacingCss = """
                line-height: \(parent.userConfig.lineHeight) !important;
                letter-spacing: \((parent.userConfig.characterSpacing / 100.0))em !important;
                """
            }
            
            var verticalPadding = Double(parent.userConfig.verticalPadding)
            if !parent.userConfig.justifyText && parent.userConfig.verticalWriting {
                verticalPadding = verticalPadding + (parent.userConfig.fontSize % 2 == 0 ? 1 : 2)
            }
            let horizontalPadding = Double(parent.userConfig.horizontalPadding)
            
            let imgWidth = parent.userConfig.verticalWriting ? "none" : "\(100 - horizontalPadding)vw"
            let imgHeight = parent.userConfig.verticalWriting ? "\(100 - verticalPadding)vh" : "none"
            
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
                --hoshi-sasayaki-text-color: \(UIColor(parent.userConfig.sasayakiTextColor).hexString);
                --hoshi-sasayaki-background-color: \(UIColor(parent.userConfig.sasayakiBackgroundColor).hexString);
            }
            html, body {
                margin: 0 !important;
                padding: 0 !important;
                writing-mode: \(writingMode) !important;
                \(parent.userConfig.verticalWriting ? "overflow-y: hidden" : "overflow-x: hidden") !important;
            }
            body {
                font-family: \(parent.userConfig.selectedFont), serif !important;
                font-size: \(parent.userConfig.fontSize)px !important;
                \(textSpacingCss)
                box-sizing: border-box !important;
                padding: \(verticalPadding / 2)vh \(horizontalPadding / 2)vw !important;
                \(gridCss)
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
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            a {
                color: rgba(66, 108, 245, 1) !important;
            }
            .hoshi-sasayaki-cue.hoshi-sasayaki-active {
                color: var(--hoshi-sasayaki-text-color) !important;
                background-color: var(--hoshi-sasayaki-background-color) !important;
            }
            \(textColorCss)
            """
            
            let sasayakiSetupScript: String = {
                if let cues = pendingSasayakiCues {
                    return """
                    window.hoshiReader.applySasayakiCues(\(cues));
                    """
                }
                return ""
            }()
            pendingSasayakiCues = nil
            
            let initialRestoreScript: String = {
                if let fragment = pendingFragment {
                    shouldSyncProgressAfterRestore = true
                    return "window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)));"
                }
                shouldSyncProgressAfterRestore = false
                return "window.hoshiReader.restoreProgress(\(self.pendingProgress));"
            }()
            pendingFragment = nil
            
            let script = """
            (function() {
                var viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }
                
                var newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);
                
                var style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);
                \(textColorOverrideJs)
            
                \(selectionJs)
                \(readerJs)
                window.hoshiReader.registerCopyText();
                
                if (\(parent.userConfig.readerHideFurigana)) {
                    document.querySelectorAll('rt').forEach(rt => rt.remove());
                }
            
                // wrap text not in spans inside ruby elements in spans to fix highlighting
                document.querySelectorAll('ruby').forEach(ruby => {
                    ruby.childNodes.forEach(node => {
                        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                            const span = document.createElement('span');
                            span.textContent = node.textContent;
                            node.replaceWith(span);
                        }
                    });
                });
                
                // apply style to big images only, some epubs have inline pictures as "text"
                var images = document.querySelectorAll('img');
                var imagePromises = Array.from(images).map(img => {
                    return new Promise(resolve => {
                        if (img.complete && img.naturalWidth > 0) {
                            if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                img.classList.add('block-img');
                            }
                            resolve();
                        } else {
                            img.onload = () => {
                                if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                    img.classList.add('block-img');
                                }
                                resolve();
                            };
                            img.onerror = () => resolve();
                        }
                    });
                });
                
                Promise.all(imagePromises).then(() => {
                    return document.fonts.ready;
                }).then(() => {
                    return new Promise(resolve => setTimeout(resolve, 50));
                }).then(() => {
                    window.hoshiReader.buildNodeOffsets();
                    \(sasayakiSetupScript)
                    \(initialRestoreScript)
                });
            })();
            """
            
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let webView = webView, !webView.scrollView.isDecelerating else {
                return
            }
            
            let point = gesture.location(in: webView)
            let maxLength = parent.maxSelectionLength
            
            let script = "window.hoshiSelection.selectText(\(point.x), \(point.y), \(maxLength))"
            
            webView.evaluateJavaScript(script) { result, _ in
                if result is NSNull || result == nil {
                    self.parent.onTapOutside?()
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
        
        func clearHighlight() {
            guard let webView = webView else {
                return
            }
            webView.evaluateJavaScript("window.hoshiSelection.clearHighlight()") { _, _ in }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let vertical = parent.userConfig.verticalWriting
            let offset = vertical ? scrollView.contentOffset.x : scrollView.contentOffset.y
            let contentSize = vertical ? scrollView.contentSize.width : scrollView.contentSize.height
            let viewSize = vertical ? scrollView.bounds.width : scrollView.bounds.height
            let maxOffset = max(contentSize - viewSize, 0)
            let threshold = CGFloat(parent.userConfig.chapterSwipeDistance)
            
            let scrolledPastEnd = vertical ? offset < -threshold : offset > maxOffset + threshold
            let scrolledPastStart = vertical ? offset > maxOffset + threshold : offset < -threshold
            
            if scrolledPastEnd {
                webView?.scrollView.delegate = nil
                if parent.onNextChapter() {
                    webView?.alpha = 0
                } else {
                    webView?.scrollView.delegate = self
                }
            } else if scrolledPastStart {
                webView?.scrollView.delegate = nil
                if parent.onPreviousChapter() {
                    webView?.alpha = 0
                } else {
                    webView?.scrollView.delegate = self
                }
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            saveBookmark()
            clearHighlight()
            parent.onScroll?()
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                saveBookmark()
                clearHighlight()
                parent.onScroll?()
            }
        }
    }
}
