//
//  PopupWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
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
            guard !data.isEmpty else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            
            let response = URLResponse(
                url: requestUrl,
                mimeType: mimeType(for: mediaPath),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
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

struct PopupWebView: UIViewRepresentable {
    let content: String
    let position: CGPoint
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
    
    private static let selectionJs: String = {
        guard let url = Bundle.main.url(forResource: "selection", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()
    
    private static let popupJs: String = {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return js
    }()
    
    private static let popupCss: String = {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }()
    
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
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "mineEntry")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "duplicateCheck")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "getEntry")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "lookupRedirect")
        config.setURLSchemeHandler(AudioHandler(), forURLScheme: "audio")
        config.setURLSchemeHandler(ImageHandler(), forURLScheme: "image")
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.wasLoaded {
            context.coordinator.currentContent = content
            context.coordinator.wasLoaded = true
            let html = constructHtml(content: content)
            webView.loadHTMLString(html, baseURL: nil)
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "duplicateCheck", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "getEntry", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupRedirect", contentWorld: .page)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        var parent: PopupWebView
        var currentContent: String = ""
        var wasLoaded: Bool = false
        var clearSelection: Bool = false
        var lastBackTrigger: Bool = false
        var lastForwardTrigger: Bool = false
        var entries: [[String: Any]] = []
        let id = UUID()
        
        init(parent: PopupWebView) {
            self.parent = parent
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
            if message.name == "getEntry", let index = message.body as? Int {
                return (entries[index], nil)
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
            <style>\(Self.popupCss)</style>
            <script>window.scanNonJapaneseText = \(scanNonJapaneseText);</script>
            <script>\(Self.selectionJs)</script>
            <script>\(Self.popupJs)</script>
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
