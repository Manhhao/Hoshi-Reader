//
//  Extensions.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

extension String {
    func characterCount() -> Int {
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
        return text.count
    }
}

extension BookMetadata {
    var coverURL: URL? {
        guard let coverPath = self.cover,
              let documentsDir = try? BookStorage.getDocumentsDirectory() else {
            return nil
        }
        return documentsDir.appendingPathComponent(coverPath)
    }
}

extension UIApplication {
    static var topSafeArea: CGFloat {
        (shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?
            .safeAreaInsets.top ?? 0
    }
}
