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
                let (data, _) = try await URLSession.shared.data(from: targetUrl)
                
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

struct PopupWebView: UIViewRepresentable {
    let content: String
    let position: CGPoint
    var clearHighlight: Bool
    var onMine: (([String: String]) -> Void)? = nil
    var onTextSelected: ((SelectionData) -> Int?)? = nil
    var onTapOutside: (() -> Void)? = nil
    
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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mineEntry")
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "tapOutside")
        config.userContentController.add(context.coordinator, name: "playWordAudio")
        config.setURLSchemeHandler(AudioHandler(), forURLScheme: "audio")
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.wasLoaded {
            context.coordinator.currentContent = content
            context.coordinator.wasLoaded = true
            let html = buildHTML(content: content)
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        if context.coordinator.clearHighlight != clearHighlight {
            context.coordinator.clearHighlight = clearHighlight
            webView.evaluateJavaScript("window.hoshiSelection.clearHighlight()")
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        WordAudioPlayer.shared.stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playWordAudio")
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: PopupWebView
        var currentContent: String = ""
        var wasLoaded: Bool = false
        var clearHighlight: Bool = false
        
        init(parent: PopupWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mineEntry", let content = message.body as? [String: String] {
                parent.onMine?(content)
            }
            else if message.name == "openLink", let urlString = message.body as? String,
                    let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            else if message.name == "tapOutside" {
                parent.onTapOutside?()
                message.webView?.evaluateJavaScript("window.hoshiSelection.clearHighlight()")
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
                WordAudioPlayer.shared.play(urlString: urlString, requestedMode: requestedMode)
            }
        }
    }
    
    private func buildHTML(content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>\(Self.popupCss)</style>
            <script>\(Self.selectionJs)</script>
            <script>\(Self.popupJs)</script>
        </head>
        <body>
            \(content)
            <div class="overlay">
                <div class="overlay-close" onclick="closeOverlay()">×</div>
                <div class="overlay-content"></div>
            </div>
        </body>
        </html>
        """
    }
}
