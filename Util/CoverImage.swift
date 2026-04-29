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
            let max = maxPixelSize
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                loadThumbnail(url: url, maxPixelSize: max)
            }.value
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

private nonisolated func loadThumbnail(url: URL, maxPixelSize: Int) -> UIImage? {
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
