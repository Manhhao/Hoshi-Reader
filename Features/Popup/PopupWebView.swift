//
//  PopupWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WebKit

struct PopupWebView: UIViewRepresentable {
    let content: String
    var onMine: (([String: String]) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onMine: onMine)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mineEntry")
        config.userContentController.add(context.coordinator, name: "openLink")
        
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
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var onMine: (([String: String]) -> Void)?
        var currentContent: String = ""
        
        // refresh onMine otherwise we have stale sentence data
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
        }
    }
    
    private var popupJs: String {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return js
    }
    
    private var popupCss: String {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }
    
    private func buildHTML(content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>\(popupCss)</style>
            <script>\(popupJs)</script>
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
