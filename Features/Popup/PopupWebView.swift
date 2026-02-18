//
//  PopupWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WebKit

class ProxyHandler: NSObject, WKURLSchemeHandler {
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
    var onMine: (([String: String]) -> Void)? = nil
    
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
        Coordinator(onMine: onMine)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mineEntry")
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "speakText")
        config.setURLSchemeHandler(ProxyHandler(), forURLScheme: "proxy")
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMine = onMine
        if context.coordinator.currentContent != content {
            context.coordinator.currentContent = content
            let html = buildHTML(content: content)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript("stopAudio()")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "speakText")
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var onMine: (([String: String]) -> Void)?
        var currentContent: String = ""
        
        init(onMine: (([String: String]) -> Void)?) {
            self.onMine = onMine
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mineEntry", let content = message.body as? [String: String] {
                onMine?(content)
            }
            if message.name == "openLink", let urlString = message.body as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            if message.name == "speakText", let urlString = message.body as? String,
               let url = URL(string: urlString) {
                TTSManager.shared.speak(url: url)
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
