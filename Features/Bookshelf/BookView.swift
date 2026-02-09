//
//  BookView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct BookView: View {
    let book: BookMetadata
    let progress: Double
    var isSelected: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            if let coverURL = book.coverURL,
               let image = UIImage(contentsOfFile: coverURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(0.709, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .primary.opacity(0.3), radius: 5)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .blue)
                                .padding(6)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(0.709, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .blue)
                                .padding(6)
                        }
                    }
            }
            
            HStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.primary.opacity(0.4))
                Text(String(format: "%.1f%%", progress * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(book.title ?? "")
                .font(.system(size: 16))
                .lineLimit(2)
                .frame(height: 40, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
