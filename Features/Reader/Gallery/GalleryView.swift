//
//  GalleryView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct GalleryView: View {
    let images: [URL]
    let onSelect: (URL) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(images, id: \.self) { url in
                    Button {
                        onSelect(url)
                    } label: {
                        CoverImage(url: url, maxPixelSize: 1600) {
                            $0.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.secondary.opacity(0.1))
                                .aspectRatio(0.7, contentMode: .fit)
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .overlay {
            if images.isEmpty {
                ContentUnavailableView("No Images", systemImage: "photo.on.rectangle")
            }
        }
    }
}
