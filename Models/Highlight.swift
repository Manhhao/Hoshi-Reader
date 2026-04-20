//
//  Highlight.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum HighlightColor: String, CaseIterable, Codable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case purple
    
    var id: String { rawValue }
    
    var rgba: (r: Int, g: Int, b: Int, a: Double) {
        switch self {
        case .yellow:
            return (239, 209, 56, 0.35)
        case .green:
            return (152, 220, 129, 0.35)
        case .blue:
            return (149, 185, 255, 0.35)
        case .pink:
            return (255, 155, 180, 0.35)
        case .purple:
            return (197, 175, 251, 0.35)
        }
    }
    
    var swatch: Color {
        let c = rgba
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
    
    static var css: String {
        allCases.map {
            let c = $0.rgba
            return ".hoshi-highlight-\($0.rawValue) { background-color: rgba(\(c.r), \(c.g), \(c.b), \(c.a)) !important; }"
        }.joined(separator: "\n")
    }
}

struct Highlight: Codable, Identifiable, Hashable {
    let id: UUID
    let character: Int
    let offset: Int
    let text: String
    let color: HighlightColor
    let createdAt: Date
}
