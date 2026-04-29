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
            BookCover(
                book: book,
                progress: progress,
                isSelected: isSelected
            )
            
            Text(book.title ?? "")
                .font(.system(size: 16))
                .lineLimit(2)
                .frame(height: 40, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BookCover: View {
    let book: BookMetadata
    var progress: Double? = nil
    var isSelected: Bool = false
    
    private let coverAspectRatio: CGFloat = 0.709
    private let innerCornerRadius: CGFloat = 6
    private let outerCornerRadius: CGFloat = 7
    
    var body: some View {
        if #available(iOS 26, *) {
            cover
                .padding(3)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        } else {
            cover
                .padding(3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
        }
    }
    
    private var cover: some View {
        VStack(spacing: progress == nil ? 0 : 3) {
            CoverImage(url: book.coverURL, maxPixelSize: 768) { image in
                image
                    .resizable()
                    .aspectRatio(coverAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
            } placeholder: {
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(coverAspectRatio, contentMode: .fit)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    checkmark(color: .blue)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isSelected, let progress, progress >= 0.999 {
                    checkmark(color: .gray)
                        .padding(6)
                }
            }
            
            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.secondary.opacity(0.4))
                    Text(String(format: "%.1f%%", progress * 100))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    private func checkmark(color: Color) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white, color)
    }
}
