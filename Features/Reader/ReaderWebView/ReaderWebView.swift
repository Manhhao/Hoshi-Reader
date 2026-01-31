//
//  ReaderWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import WebKit
import SwiftUI

private enum NavigationDirection {
    case forward
    case backward
}

struct SelectionData {
    let text: String
    let sentence: String?
    let rect: CGRect
}

struct ReaderWebView: UIViewRepresentable {
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
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
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
            webView.loadFileURL(url, allowingReadAccessTo: try! BookStorage.getDocumentsDirectory())
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
        var parent: ReaderWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        
        init(_ parent: ReaderWebView) {
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
        
        private var readerJs: String {
            guard let url = Bundle.main.url(forResource: "reader", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: String.Encoding.utf8) else {
                return ""
            }
            return js
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pageHeight = Int(parent.viewSize.height)
            let pageWidth = Int(parent.viewSize.width)
            let writingMode = parent.userConfig.verticalWriting ? "vertical-rl" : "horizontal-tb"
            let columnGap = parent.userConfig.verticalWriting ? parent.userConfig.verticalPadding * 2 : parent.userConfig.horizontalPadding * 2
            
            let textColorCss: String = {
                if parent.userConfig.theme == .custom {
                    let hex = UIColor(parent.userConfig.customTextColor).hexString
                    return """
                    html, body { color: \(hex) !important; }
                    """
                } else {
                    guard parent.userConfig.horizontalPadding > 0 else { return "" }
                    return """
                    @media (prefers-color-scheme: light) { html, body { color: #000 !important; } }
                    @media (prefers-color-scheme: dark) { html, body { color: #fff !important; } }
                    """
                }
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
            
            
            let css = """
            \(fontFaceCss)
            html, body { 
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                margin: 0 !important;
                padding: 0 !important; 
            }
            body {
                writing-mode: \(writingMode) !important;
                font-family: \(parent.userConfig.selectedFont), serif !important;
                font-size: \(parent.userConfig.fontSize)px !important;
                box-sizing: border-box !important;
                column-width: var(--page-height, 100vh) !important;
                column-height: var(--page-width, 100vw) !important;
                column-gap: \(columnGap)px;
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
            \(textColorCss)
            """
            
            let spacerJs: String = {
                if parent.userConfig.verticalWriting {
                    guard parent.userConfig.verticalPadding > 0 else { return "" }
                    return """
                    var spacer = document.createElement('div');
                    spacer.style.height = '\(parent.userConfig.verticalPadding)px';
                    spacer.style.width = '100%';
                    spacer.style.display = 'block';
                    spacer.style.breakInside = 'avoid';
                    document.body.appendChild(spacer);
                    """
                } else {
                    guard parent.userConfig.horizontalPadding > 0 else { return "" }
                    return """
                    var spacer = document.createElement('div');
                    spacer.style.height = '100%';
                    spacer.style.width = '\(parent.userConfig.horizontalPadding)px';
                    spacer.style.display = 'block';
                    spacer.style.breakInside = 'avoid';
                    document.body.appendChild(spacer);
                    """
                }
            }()
            
            let snapScrollJs: String = {
                if parent.userConfig.verticalWriting {
                    return """
                    var lastPageScroll = 0;
                    window.addEventListener('scroll', function() {
                        var pageHeight = window.innerHeight;
                        var snappedScroll = Math.round(window.scrollY / pageHeight) * pageHeight;
                        if (Math.abs(window.scrollY - snappedScroll) > 1) {
                            window.scrollTo(0, lastPageScroll);
                        } else {
                            lastPageScroll = snappedScroll;
                        }
                    }, { passive: true });
                    """
                } else {
                    return """
                    var lastPageScroll = 0;
                    window.addEventListener('scroll', function() {
                        var pageWidth = window.innerWidth;
                        var snappedScroll = Math.round(window.scrollX / pageWidth) * pageWidth;
                        if (Math.abs(window.scrollX - snappedScroll) > 1) {
                            window.scrollTo(lastPageScroll, 0);
                        } else {
                            lastPageScroll = snappedScroll;
                        }
                    }, { passive: true });
                    """
                }
            }()
            
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
                
                \(spacerJs)
                \(readerJs)
            
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
                
                \(snapScrollJs)
                
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
                    window.hoshiReader.restoreProgress(\(self.parent.currentProgress));
                });
            })();
            """
            
            webView.evaluateJavaScript(script) { _, _ in
                UIView.animate(withDuration: 0.3) {
                    webView.alpha = 1
                }
            }
        }
        
        private func navigate(_ direction: NavigationDirection) {
            guard let webView = webView else { return }
            
            clearHighlight()
            parent.onTapOutside?()
            
            let isVertical = parent.userConfig.verticalWriting
            let script = paginationScript(direction: direction, isVertical: isVertical)
            
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
        
        private func paginationScript(direction: NavigationDirection, isVertical: Bool) -> String {
            if isVertical {
                let pageHeight = Int(parent.viewSize.height)
                if direction == .forward {
                    let padding = parent.userConfig.verticalPadding
                    return """
                    (function() {
                        var pageHeight = \(pageHeight);
                        var maxScroll = (\(padding) === 0) ? document.body.scrollHeight : document.body.scrollHeight - pageHeight;
                        if ((window.scrollY + pageHeight) <= (maxScroll - 1)) {
                            window.scrollBy(0, pageHeight);
                            return "scrolled";
                        }
                        return "limit";
                    })()
                    """
                } else {
                    return """
                    (function() {
                        var pageHeight = \(pageHeight);
                        if (window.scrollY > 0) {
                            window.scrollBy(0, -pageHeight);
                            return "scrolled";
                        }
                        return "limit";
                    })()
                    """
                }
            } else {
                let pageWidth = Int(parent.viewSize.width)
                if direction == .forward {
                    let padding = parent.userConfig.horizontalPadding
                    return """
                    (function() {
                        var pageWidth = \(pageWidth);
                        var maxScroll = (\(padding) === 0) ? document.body.scrollWidth : document.body.scrollWidth - pageWidth;
                        if ((window.scrollX + pageWidth) <= (maxScroll - 1)) {
                            window.scrollBy(pageWidth, 0);
                            return "scrolled";
                        }
                        return "limit";
                    })()
                    """
                } else {
                    return """
                    (function() {
                        var pageWidth = \(pageWidth);
                        if (window.scrollX > 0) {
                            window.scrollBy(-pageWidth, 0);
                            return "scrolled";
                        }
                        return "limit";
                    })()
                    """
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
