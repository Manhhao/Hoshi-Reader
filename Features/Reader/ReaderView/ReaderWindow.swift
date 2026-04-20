//
//  ReaderWindow.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

private struct DismissReaderKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var dismissReader: (() -> Void)? {
        get { self[DismissReaderKey.self] }
        set { self[DismissReaderKey.self] = newValue }
    }
}

@MainActor
final class ReaderWindow {
    private weak var hostController: UIViewController?
    
    func present<Content: View>(@ViewBuilder content: () -> Content, onDismiss: @escaping () -> Void) {
        guard hostController == nil,
              let presenter = topPresenter() else { return }
        
        let dismiss: () -> Void = { [weak self] in self?.dismiss(onDismiss: onDismiss) }
        let host = UIHostingController(rootView: AnyView(content().environment(\.dismissReader, dismiss)))
        host.modalPresentationStyle = .overFullScreen
        host.modalPresentationCapturesStatusBarAppearance = true
        host.view.alpha = 0
        self.hostController = host
        
        presenter.present(host, animated: false) {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                host.view.alpha = 1
            }
        }
    }
    
    func dismiss(onDismiss: (() -> Void)? = nil) {
        guard let host = hostController else { return }
        self.hostController = nil
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            host.view.alpha = 0
        } completion: { _ in
            host.dismiss(animated: false) {
                onDismiss?()
            }
        }
    }
    
    private func topPresenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let root = window.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
