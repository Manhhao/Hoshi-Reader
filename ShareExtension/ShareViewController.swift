//
//  ShareViewController.swift
//  ShareExtension
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            finish()
            return
        }
        
        provider.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] item, _ in
            guard let self,
                  let text = item as? String,
                  var components = URLComponents(string: "hoshi://search") else {
                DispatchQueue.main.async { self?.finish() }
                return
            }
            components.queryItems = [URLQueryItem(name: "text", value: text)]
            guard let url = components.url else {
                DispatchQueue.main.async { self.finish() }
                return
            }
            
            DispatchQueue.main.async {
                var responder: UIResponder? = self
                while responder != nil {
                    if let application = responder as? UIApplication {
                        application.open(url, options: [:], completionHandler: nil)
                        break
                    }
                    responder = responder?.next
                }
                self.finish()
            }
        }
    }
    
    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
