//
//  PopupWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit
import WebKit

class AudioHandler: NSObject, WKURLSchemeHandler {
    private var tasks = Set<ObjectIdentifier>()
    
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestUrl = task.request.url,
              let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
              let targetUrlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let targetUrl = URL(string: targetUrlString) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        
        let taskId = ObjectIdentifier(task)
        tasks.insert(taskId)
        
        Task {
            do {
                let request = URLRequest(url: targetUrl, timeoutInterval: 4)
                let (data, _) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    guard self.tasks.contains(taskId) else { return }
                    
                    let response = HTTPURLResponse(
                        url: requestUrl,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Access-Control-Allow-Origin": "*",
                            "Content-Type": "application/json"
                        ]
                    )!
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                }
            } catch {
                await MainActor.run {
                    guard self.tasks.contains(taskId) else { return }
                    task.didFailWithError(error)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        tasks.remove(ObjectIdentifier(task))
    }
}

class ImageHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestUrl = task.request.url,
              let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
              let dictionary = components.queryItems?.first(where: { $0.name == "dictionary" })?.value,
              let mediaPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        
        LookupEngine.shared.withMediaFile(dictName: dictionary, mediaPath: mediaPath) { data in
            let mime = mimeType(for: mediaPath)
            Task { @MainActor in
                guard !data.isEmpty else {
                    task.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                
                let response = URLResponse(
                    url: requestUrl,
                    mimeType: mime,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }
    
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    
    private func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}

class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        do {
            guard let fontFile = try FontManager.shared.fontUrl(name: fileName, verticalWriting: false) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            
            let data = try Data(contentsOf: fontFile, options: .mappedIfSafe)
            let response = URLResponse(
                url: url,
                mimeType: mimeType(for: fontFile),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
    
    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "font/ttf"
        }
    }
}

struct PopupWebView: UIViewRepresentable {
    let content: String
    let position: CGPoint
    var scale: CGFloat = 1.0
    var clearSelection: Bool
    var dictionaryStyles: [String: String] = [:]
    var lookupEntries: [[String: Any]] = []
    var scanNonJapaneseText: Bool = true
    var backTrigger: Bool = false
    var forwardTrigger: Bool = false
    var onMine: (([String: String]) async -> Bool)? = nil
    var onTextSelected: ((SelectionData) -> Int?)? = nil
    var onTapOutside: (() -> Void)? = nil
    var onSwipeDismiss: (() -> Void)? = nil
    var onRedirect: ((String) -> [[String: Any]])? = nil
    var scrollViewBounces: Bool = false
    var onScrollViewOffsetChanged: ((CGFloat) -> Void)? = nil
    var onScrollViewWillBeginDragging: (() -> Void)? = nil
    var onScrollViewDidEndDragging: (() -> Void)? = nil
    var onScrollViewDidEndDecelerating: (() -> Void)? = nil
    
    private static let swipeDismissJs = """
    (function() {
        if (!window.swipeThreshold) {
            return;
        }
        var startX, startY;
        document.addEventListener('touchstart', function(e) {
            startX = e.touches[0].clientX;
            startY = e.touches[0].clientY;
        });
        document.addEventListener('touchend', function(e) {
            var dx = e.changedTouches[0].clientX - startX;
            var dy = e.changedTouches[0].clientY - startY;
            var hasSelection = window.getSelection().toString();
            
            if (Math.abs(dx) > window.swipeThreshold && Math.abs(dy) < 20 && !hasSelection) {
                webkit.messageHandlers.swipeDismiss.postMessage(null);
            }
        });
    })();
    """
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "tapOutside")
        config.userContentController.add(context.coordinator, name: "swipeDismiss")
        config.userContentController.add(context.coordinator, name: "playWordAudio")
        config.userContentController.add(context.coordinator, name: "buttonFrames")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "mineEntry")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "duplicateCheck")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "getEntries")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "lookupRedirect")
        config.setURLSchemeHandler(AudioHandler(), forURLScheme: "audio")
        config.setURLSchemeHandler(ImageHandler(), forURLScheme: "image")
        config.setURLSchemeHandler(DocumentResourceHandler(), forURLScheme: "local-resources")
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = scrollViewBounces
        webView.scrollView.keyboardDismissMode = .onDrag
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.wasLoaded {
            context.coordinator.currentContent = content
            context.coordinator.wasLoaded = true
            context.coordinator.scale = scale
            let html = constructHtml(content: content)
            webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        }
        
        if context.coordinator.scale != scale {
            context.coordinator.scale = scale
            webView.evaluateJavaScript("document.documentElement.style.zoom = '\(scale)'; if (typeof syncButtonFrames === 'function') requestAnimationFrame(syncButtonFrames)")
        }
        
        if context.coordinator.clearSelection != clearSelection {
            context.coordinator.clearSelection = clearSelection
            webView.evaluateJavaScript("window.hoshiSelection.clearSelection()")
        }
        
        if context.coordinator.lastBackTrigger != backTrigger {
            context.coordinator.lastBackTrigger = backTrigger
            webView.evaluateJavaScript("window.navigateBack()")
        }
        
        if context.coordinator.lastForwardTrigger != forwardTrigger {
            context.coordinator.lastForwardTrigger = forwardTrigger
            webView.evaluateJavaScript("window.navigateForward()")
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        Task {
            await WordAudioPlayer.shared.stop(id: coordinator.id)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "swipeDismiss")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playWordAudio")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "buttonFrames")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "duplicateCheck", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "getEntries", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupRedirect", contentWorld: .page)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, UIScrollViewDelegate {
        var parent: PopupWebView
        var currentContent: String = ""
        var wasLoaded: Bool = false
        var clearSelection: Bool = false
        var lastBackTrigger: Bool = false
        var lastForwardTrigger: Bool = false
        var scale: CGFloat = 1.0
        var entries: [[String: Any]] = []
        weak var webView: WKWebView?
        private var buttons: [String: UIButton] = [:]
        let id = UUID()
        
        init(parent: PopupWebView) {
            self.parent = parent
        }
        
        private func updateButtons(_ frames: [[String: Any]], in webView: WKWebView) {
            var activeKeys = Set<String>()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 13 * scale, weight: .medium)
            
            for frame in frames {
                guard let kind = frame["kind"] as? String,
                      let entryIndex = frame["entryIndex"] as? Int,
                      let x = frame["x"] as? CGFloat,
                      let y = frame["y"] as? CGFloat,
                      let width = frame["width"] as? CGFloat,
                      let height = frame["height"] as? CGFloat,
                      width > 0, height > 0 else {
                    continue
                }
                
                let key = "\(kind)-\(entryIndex)"
                activeKeys.insert(key)
                
                let button: UIButton
                if let existing = buttons[key] {
                    button = existing
                } else {
                    button = UIButton(type: .system)
                    button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
                    button.tintColor = .secondaryLabel
                    buttons[key] = button
                    webView.scrollView.addSubview(button)
                }
                
                button.tag = entryIndex * 2 + (kind == "audio" ? 0 : 1)
                button.frame = CGRect(x: x, y: y, width: width, height: height)
                let state = frame["state"] as? String ?? "default"
                button.setImage(UIImage(systemName: symbolName(kind: kind, state: state), withConfiguration: symbolConfig), for: .normal)
                button.isEnabled = frame["enabled"] as? Bool ?? true
                button.alpha = button.isEnabled ? 0.85 : 0.55
            }
            
            for key in buttons.keys.filter({ !activeKeys.contains($0) }) {
                buttons.removeValue(forKey: key)?.removeFromSuperview()
            }
        }
        
        private func symbolName(kind: String, state: String) -> String {
            if kind == "audio" {
                return state == "error" ? "speaker.slash" : "speaker.wave.2"
            }
            return state == "duplicate" ? "plus.square.on.square" : "plus.square"
        }
        
        @objc private func buttonTapped(_ sender: UIButton) {
            let action = sender.tag % 2 == 0 ? "playEntryAudio" : "mineEntryAtIndex"
            webView?.evaluateJavaScript("\(action)(\(sender.tag / 2))")
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScrollViewOffsetChanged?(scrollView.contentOffset.y)
            guard scrollView.contentOffset.x != 0 else { return }
            scrollView.contentOffset.x = 0
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onScrollViewWillBeginDragging?()
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            parent.onScrollViewDidEndDragging?()
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onScrollViewDidEndDecelerating?()
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            entries = parent.lookupEntries
            webView.callAsyncJavaScript(
                """
                window.dictionaryStyles = dictionaryStyles;
                window.entryCount = entryCount;
                window.renderPopup();
                """,
                arguments: [
                    "dictionaryStyles": parent.dictionaryStyles,
                    "entryCount": entries.count,
                ],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
            if message.name == "mineEntry", let content = message.body as? [String: String] {
                return (await parent.onMine?(content) ?? false, nil)
            }
            if message.name == "duplicateCheck", let word = message.body as? String {
                return (await AnkiManager.shared.checkDuplicate(word: word), nil)
            }
            if message.name == "getEntries", let body = message.body as? [String: Any] {
                let start = body["start"] as? Int ?? 0
                let count = body["count"] as? Int ?? 0
                return (Array(entries[start..<start + count]), nil)
            }
            if message.name == "lookupRedirect", let query = message.body as? String {
                entries = parent.onRedirect?(query) ?? []
                return (entries.count, nil)
            }
            return (nil, nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "openLink", let urlString = message.body as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            else if message.name == "tapOutside" {
                parent.onTapOutside?()
                message.webView?.evaluateJavaScript("window.hoshiSelection.clearSelection()")
            }
            else if message.name == "swipeDismiss" {
                parent.onSwipeDismiss?()
            }
            else if message.name == "buttonFrames",
                    let frames = message.body as? [[String: Any]] {
                guard let webView = message.webView else { return }
                updateButtons(frames, in: webView)
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
                let adjustedInset = message.webView?.scrollView.adjustedContentInset ?? .zero
                let rect = CGRect(
                    x: parent.position.x + x + adjustedInset.left,
                    y: parent.position.y + y + adjustedInset.top,
                    width: w,
                    height: h
                )
                let selectionData = SelectionData(text: text, sentence: sentence, rect: rect)
                
                if let highlightCount = parent.onTextSelected?(selectionData) {
                    message.webView?.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(highlightCount))")
                }
            }
            else if message.name == "playWordAudio",
                    let content = message.body as? [String: Any],
                    let urlString = content["url"] as? String {
                let requestedMode = (content["mode"] as? String).flatMap(AudioPlaybackMode.init) ?? .interrupt
                Task(priority: .userInitiated) {
                    await WordAudioPlayer.shared.play(urlString: urlString, requestedMode: requestedMode, id: self.id)
                }
            }
        }
    }
    
    private func constructHtml(content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <link rel="stylesheet" href="popup.css">
            <style>
                \(FontManager.shared.fontfaceCSS)
                html { zoom: \(scale); }
            </style>
            <script>window.scanNonJapaneseText = \(scanNonJapaneseText);</script>
            <script src="selection.js"></script>
            <script src="popup.js"></script>
        </head>
        <body>
            \(content)
            <script>\(Self.swipeDismissJs)</script>
            <div class="overlay">
                <div class="overlay-close" onclick="closeOverlay()">×</div>
                <div class="overlay-content"></div>
            </div>
        </body>
        </html>
        """
    }
}
