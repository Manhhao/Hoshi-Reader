//
//  Extensions.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CryptoKit
import Foundation
import SwiftUI

extension String {
    func filtered() -> String {
        var text = self
        if let bodyRange = text.range(of: "(?s)<body.*?</body>", options: .regularExpression) {
            text = String(text[bodyRange])
        }
        text = text.replacingOccurrences(of: "(?s)<rt>.*?</rt>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(
            of: "[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\\p{Radical}\\p{Unified_Ideograph}]",
            with: "",
            options: .regularExpression
        )
        return text
    }
}

extension BookMetadata {
    var coverURL: URL? {
        guard let coverPath = self.cover,
              let appDir = try? BookStorage.getAppDirectory() else {
            return nil
        }
        return appDir.appendingPathComponent(coverPath)
    }
}

extension Data {
    var sha1: String {
        Insecure.SHA1.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    mutating func excludeFromBackup() throws {
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try self.setResourceValues(resource)
    }
}

extension UIApplication {
    static var topSafeArea: CGFloat {
        (shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?
            .safeAreaInsets.top ?? 0
    }
    
    static var bottomSafeArea: CGFloat {
        (shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?
            .safeAreaInsets.bottom ?? 0
    }
}

struct LoadingOverlay: View {
    let message: String
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            Group {
                if #available(iOS 26, *) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message)
                            .lineLimit(1)
                    }
                    .padding(24)
                    .glassEffect()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message)
                            .lineLimit(1)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
    }
}

// https://stackoverflow.com/questions/26341008/how-to-convert-uicolor-to-hex-and-display-in-nslog
extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let multiplier: CGFloat = 255.9999999
        
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        if alpha == 1.0 {
            return String(
                format: "#%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier)
            )
        }
        else {
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier),
                Int(alpha * multiplier)
            )
        }
    }
}
