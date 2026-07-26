//
//  CoverImage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import ImageIO
import UIKit

struct CoverImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: Int
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: CoverImageKey(url: url, maxPixelSize: maxPixelSize)) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ThumbnailDecoder.shared.thumbnail(url: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else {
                return
            }
            image = loaded
        }
    }
}

private struct CoverImageKey: Hashable {
    let path: String?
    let maxPixelSize: Int
    
    init(url: URL?, maxPixelSize: Int) {
        self.path = url?.path(percentEncoded: false)
        self.maxPixelSize = maxPixelSize
    }
}

private actor ThumbnailDecoder {
    static let shared = ThumbnailDecoder()
    
    func thumbnail(url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct CoverFallback: View {
    let title: String
    var author: String? = nil
    var aspectRatio: CGFloat = 0.709
    var cornerRadius: CGFloat = 6
    
    private var gradient: LinearGradient {
        let hash = title.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        let hue = Double(hash % 3600) / 3600
        let brightness = 0.6
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.42, brightness: brightness),
                Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.58, brightness: brightness * 0.61)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 150
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .lineLimit(5)
                
                Spacer(minLength: 12 * scale)
                
                if let author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 12 * scale, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .padding([.horizontal, .bottom], 12 * scale)
            .padding(.top, 20 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(gradient)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
