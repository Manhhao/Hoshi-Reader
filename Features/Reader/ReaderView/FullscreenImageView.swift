//
//  FullscreenImageView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct FullscreenImageView: View {
    let url: URL
    let backgroundColor: Color
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ZoomableImage(url: url)
                .ignoresSafeArea()
                .background(backgroundColor.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                    
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                        }
                    }
                }
        }
        .persistentSystemOverlays(.hidden)
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> ImageScrollView {
        ImageScrollView(url: url)
    }
    
    func updateUIView(_ uiView: ImageScrollView, context: Context) {}
}

private final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    
    init(url: URL) {
        super.init(frame: .zero)
        imageView.image = UIImage(contentsOfFile: url.path)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale,
           let size = imageView.image?.size, size.width > 0, size.height > 0 {
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerImage()
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    
    private func centerImage() {
        let horizontalOffset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalOffset = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(
            x: contentSize.width / 2 + horizontalOffset,
            y: contentSize.height / 2 + verticalOffset
        )
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            // about 3x zoom
            let point = gesture.location(in: imageView)
            let size = bounds.size
            zoom(to: CGRect(
                x: point.x - size.width / 6,
                y: point.y - size.height / 6,
                width: size.width / 3,
                height: size.height / 3
            ), animated: true)
        }
    }
}
