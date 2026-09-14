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

private struct ReaderViewControllerKey: EnvironmentKey {
    @MainActor static let defaultValue: ReaderViewController? = nil
}

extension EnvironmentValues {
    var dismissReader: (() -> Void)? {
        get { self[DismissReaderKey.self] }
        set { self[DismissReaderKey.self] = newValue }
    }
    
    var readerViewController: ReaderViewController? {
        get { self[ReaderViewControllerKey.self] }
        set { self[ReaderViewControllerKey.self] = newValue }
    }
}

@MainActor
final class ReaderWindow {
    private weak var hostController: UIViewController?
    
    @discardableResult
    func present<Content: View>(@ViewBuilder content: () -> Content, onDismiss: @escaping () -> Void) -> Bool {
        guard hostController == nil,
              let presenter = topPresenter() else { return false }
        
        let dismiss: () -> Void = { [weak self] in self?.dismiss(onDismiss: onDismiss) }
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        let container = ReaderViewController(host: host, onClose: dismiss)
        host.rootView = AnyView(
            content()
                .environment(\.dismissReader, dismiss)
                .environment(\.readerViewController, container)
        )
        
        let nav = UINavigationController(
            navigationBarClass: ReaderNavigationBar.self,
            toolbarClass: ReaderToolbar.self
        )
        nav.setViewControllers([container], animated: false)
        nav.isToolbarHidden = false
        nav.modalPresentationStyle = .overFullScreen
        nav.modalPresentationCapturesStatusBarAppearance = true
        nav.view.alpha = 0
        
        let navAppearance = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        if #available(iOS 26.0, *) {
            navAppearance.configureWithTransparentBackground()
            toolbarAppearance.configureWithTransparentBackground()
        } else {
            navAppearance.configureWithDefaultBackground()
            toolbarAppearance.configureWithDefaultBackground()
        }
        nav.navigationBar.standardAppearance = navAppearance
        nav.navigationBar.scrollEdgeAppearance = navAppearance
        nav.navigationBar.tintColor = .label
        nav.toolbar.tintColor = .label
        nav.toolbar.standardAppearance = toolbarAppearance
        nav.toolbar.scrollEdgeAppearance = toolbarAppearance
        
        self.hostController = nav
        
        presenter.present(nav, animated: false) {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                nav.view.alpha = 1
            }
        }
        return true
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
            if presented.isBeingDismissed { return nil }
            top = presented
        }
        return top
    }
}
