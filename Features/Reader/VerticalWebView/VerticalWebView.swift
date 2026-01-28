//
//  VerticalWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import WebKit
import SwiftUI

struct SelectionData {
    let text: String
    let sentence: String?
    let rect: CGRect
}

struct VerticalWebView: UIViewRepresentable {
    let fileURL: URL?
    let contentURL: URL
    let userConfig: UserConfig
    let viewSize: CGSize
    
    let currentProgress: Double
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onSaveBookmark: (Double) -> Void
    var onTextSelected: ((SelectionData) -> Int?)?
    var onTapOutside: (() -> Void)?
    let maxSelectionLength: Int = 16
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelected")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        webView.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        webView.addGestureRecognizer(swipeRight)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.require(toFail: swipeLeft)
        tap.require(toFail: swipeRight)
        webView.addGestureRecognizer(tap)
        
        context.coordinator.webView = webView
        
        webView.alpha = 0
        
        WebViewPreloader.shared.close()
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let url = fileURL else {
            return
        }
        
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.loadFileURL(url, allowingReadAccessTo: contentURL)
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
        var parent: VerticalWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        
        init(_ parent: VerticalWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "textSelected",
                  let body = message.body as? [String: Any] else {
                return
            }
            guard let text = body["text"] as? String,
                  let rectData = body["rect"] as? [String: Any],
                  let x = rectData["x"] as? CGFloat,
                  let y = rectData["y"] as? CGFloat,
                  let w = rectData["width"] as? CGFloat,
                  let h = rectData["height"] as? CGFloat else {
                return
            }
            let sentence = body["sentence"] as? String
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let selectionData = SelectionData(text: text, sentence: sentence, rect: rect)
            
            if let highlightCount = parent.onTextSelected?(selectionData) {
                highlightSelection(count: highlightCount)
            }
        }
        
        private var readerJS: String {
            guard let url = Bundle.main.url(forResource: "reader", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pageHeight = Int(parent.viewSize.height)
            let pageWidth = Int(parent.viewSize.width)
            
            let css = """
            html, body { 
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                margin: 0 !important;
                padding: 0 !important; 
            }
            body {
                writing-mode: vertical-rl !important;
                font-family: "Hiragino Mincho ProN", serif !important;
                font-size: \(parent.userConfig.fontSize)px !important;
                box-sizing: border-box !important;
                column-width: var(--page-height, 100vh) !important;
                column-height: var(--page-width, 100vw) !important;
                column-gap: \(parent.userConfig.verticalPadding * 2)px;
                padding: \(parent.userConfig.verticalPadding)px \(parent.userConfig.horizontalPadding)px !important;
            }
            img.block-img {
                max-width: calc(100vw - \(parent.userConfig.horizontalPadding * 2)px) !important;
                max-height: calc(100vh - \(parent.userConfig.verticalPadding * 2)px) !important;
                width: auto !important;
                height: auto !important;
                display: block !important;
                margin: auto !important;
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
                object-fit: contain !important;
            }
            svg {
                max-width: calc(100vw - \(parent.userConfig.horizontalPadding * 2)px) !important;
                max-height: calc(100vh - \(parent.userConfig.verticalPadding * 2)px) !important;
                width: 100% !important;
                height: 100% !important;
                display: block !important;
                margin: auto !important;
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
            }
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            @media (prefers-color-scheme: light) { html, body { background-color: #fff !important; color: #000 !important; } }
            @media (prefers-color-scheme: dark) { html, body { background-color: #000 !important; color: #fff !important; } }
            """
            
            let script = """
            (function() {
                var viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }
                
                var newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);
                
                document.documentElement.style.setProperty('--page-height', '\(pageHeight)px');
                document.documentElement.style.setProperty('--page-width', '\(pageWidth)px');
                
                var style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);
                
                // this is to add vertical spacing at the end if vertical padding > 0
                // this seems to create a full page
                if (\(parent.userConfig.verticalPadding) > 0) {
                    var spacer = document.createElement('div');
                    spacer.style.height = '\(parent.userConfig.verticalPadding)px';
                    spacer.style.width = '100%';
                    spacer.style.display = 'block';
                    spacer.style.breakInside = 'avoid';
                    document.body.appendChild(spacer);
                }
                \(readerJS)

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
                            if (img.naturalWidth > 100 || img.naturalHeight > 100) {
                                img.classList.add('block-img');
                            }
                            resolve();
                        } else {
                            img.onload = () => {
                                if (img.naturalWidth > 100 || img.naturalHeight > 100) {
                                    img.classList.add('block-img');
                                }
                                resolve();
                            };
                            img.onerror = () => resolve();
                        }
                    });
                });
                
                // wait for all images to load before scrolling to bookmark
                Promise.all(imagePromises).then(() => {
                    window.hoshiReader.restoreProgress(\(self.parent.currentProgress));
                });
            })();
            """
            
            webView.evaluateJavaScript(script) { _, _ in
                UIView.animate(withDuration: 0.25) {
                    webView.alpha = 1
                }
            }
        }
        
        @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
            guard let webView = webView else {
                return
            }
            
            clearHighlight()
            parent.onTapOutside?()
            
            let script = """
                (function() {
                    var pageHeight = \(Int(self.parent.viewSize.height));
                    if (window.scrollY > 0) {
                        window.scrollBy(0, -pageHeight);
                        return "scrolled";
                    }
                    return "limit";
                })()
                """
            
            webView.evaluateJavaScript(script) { (result, _) in
                if let res = result as? String, res == "scrolled" {
                    self.saveBookmark()
                }
                else {
                    if self.parent.onPreviousChapter() {
                        webView.alpha = 0
                    }
                }
            }
        }
        
        @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
            guard let webView = webView else {
                return
            }
            
            clearHighlight()
            parent.onTapOutside?()
            
            let script = """
                (function() {
                    var pageHeight = \(Int(self.parent.viewSize.height));
                    var maxScroll = (\(parent.userConfig.verticalPadding) === 0) ? document.body.scrollHeight : document.body.scrollHeight - pageHeight;
                    if ((window.scrollY + pageHeight) <= (maxScroll - 1)) {
                        window.scrollBy(0, pageHeight);
                        return "scrolled";
                    }
                    return "limit";
                })()
                """
            
            webView.evaluateJavaScript(script) { result, _ in
                if let res = result as? String, res == "scrolled" {
                    self.saveBookmark();
                }
                else {
                    if self.parent.onNextChapter() {
                        webView.alpha = 0
                    }
                }
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let webView = webView else {
                return
            }
            
            let point = gesture.location(in: webView)
            let maxLength = parent.maxSelectionLength
            
            let script = "window.hoshiReader.selectText(\(point.x), \(point.y), \(maxLength))"
            
            webView.evaluateJavaScript(script) { result, _ in
                if result is NSNull || result == nil {
                    self.parent.onTapOutside?()
                }
            }
        }
        
        func saveBookmark() {
            guard let webView = webView else {
                return
            }
            
            let script = "window.hoshiReader.calculateProgress()"
            
            webView.evaluateJavaScript(script) { (result, _) in
                if let progress = result as? Double {
                    self.parent.onSaveBookmark(progress)
                }
            }
        }
        
        func highlightSelection(count: Int) {
            guard let webView = webView else {
                return
            }
            
            webView.evaluateJavaScript("window.hoshiReader.highlightSelection(\(count))") { _, _ in }
        }
        
        func clearHighlight() {
            guard let webView = webView else {
                return
            }
            webView.evaluateJavaScript("window.hoshiReader.clearHighlight()") { _, _ in }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
