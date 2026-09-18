//
//  ReaderViewController.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

final class ReaderNavigationBar: UINavigationBar {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

final class ReaderToolbar: UIToolbar {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

private let secondaryLabel = UIColor { UIColor.secondaryLabel.resolvedColor(with: $0) }

@MainActor
final class ReaderViewController: UIViewController {
    private let host: UIViewController
    private let onClose: () -> Void
    private var viewModel: ReaderViewModel?
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let infoLabel = UILabel()
    private let titleView = UIStackView()
    private let infoItem = UIBarButtonItem()
    private let closeItem = UIBarButtonItem()
    private let optionsItem = UIBarButtonItem()
    private var verticalBar = false
    
    init(host: UIViewController, onClose: @escaping () -> Void) {
        self.host = host
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var childForStatusBarHidden: UIViewController? { host }
    override var childForStatusBarStyle: UIViewController? { host }
    override var childForHomeIndicatorAutoHidden: UIViewController? { host }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.8
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center
        
        titleView.axis = .vertical
        titleView.alignment = .center
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.addArrangedSubview(titleLabel)
        titleView.addArrangedSubview(subtitleLabel)
        
        infoItem.customView = infoLabel
        if #available(iOS 26.0, *) {
            infoItem.hidesSharedBackground = true
        }
        
        closeItem.primaryAction = UIAction(image: UIImage(systemName: "chevron.left")) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
        
        optionsItem.image = UIImage(systemName: "slider.horizontal.3")
        optionsItem.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                let elements = MainActor.assumeIsolated { self?.menuElements() ?? [] }
                completion(elements)
            }
        ])
        
        registerForTraitChanges([UITraitUserInterfaceIdiom.self]) { (self: Self, _) in
            self.updateSafeArea()
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeArea()
    }
    
    @available(iOS 26.0, *)
    override func updateProperties() {
        super.updateProperties()
        guard #available(iOS 27.1, *) else {
            return
        }
        
        let unfolded = traitCollection.horizontalSizeClass == .regular
        let regions: SafeAreaRegions = unfolded ? [] : .all
        if let host = host as? UIHostingController<AnyView>, host.safeAreaRegions != regions {
            host.safeAreaRegions = regions
        }
        
        let vertical = traitCollection.verticalBarEdge != .unspecified
        guard vertical != verticalBar else {
            return
        }
        
        verticalBar = vertical
        updateBars()
        navigationItem.leadingItemGroups = vertical ? [closeItem.creatingFixedGroup()] : []
    }
    
    func attach(_ viewModel: ReaderViewModel) {
        guard self.viewModel !== viewModel else { return }
        self.viewModel = viewModel
        updateSafeArea()
        observeBars()
    }
    
    func detach() {
        viewModel = nil
    }
    
    private func updateSafeArea() {
        guard let viewModel else {
            return
        }
        
        let top: CGFloat
        let bottom: CGFloat
        if traitCollection.userInterfaceIdiom == .pad {
            top = 32
            bottom = 32
        } else {
            guard let insets = view.window?.safeAreaInsets else {
                return
            }
            top = insets.top
            bottom = insets.bottom
        }
        
        if viewModel.topSafeArea != top {
            viewModel.topSafeArea = top
        }
        if viewModel.bottomSafeArea != bottom {
            viewModel.bottomSafeArea = bottom
        }
    }
    
    private func close() {
        if viewModel?.isTracking == true {
            viewModel?.stopTracking()
        }
        onClose()
    }
    
    private func menuElements() -> [UIMenuElement] {
        guard let viewModel else { return [] }
        var sheets: [(String, String, ActiveSheet)] = [
            (String(localized: "Appearance"), "paintpalette", .appearance),
            (String(localized: "Contents"), "list.bullet", .contents),
            (String(localized: "Statistics"), "chart.bar.xaxis", .statistics),
        ]
        if UserConfig.shared.enableSasayaki && viewModel.sasayakiPlayer.hasMatch {
            sheets.append((String(localized: "Sasayaki"), "waveform", .sasayaki))
        }
        return sheets.map { title, image, sheet in
            UIAction(title: title, image: UIImage(systemName: image)) { _ in
                MainActor.assumeIsolated {
                    viewModel.activeSheet = sheet
                }
            }
        }
    }
    
    private func observeBars() {
        withObservationTracking {
            updateBars()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeBars()
            }
        }
    }
    
    private func updateBars() {
        guard let viewModel else { return }
        let config = UserConfig.shared
        let infoColor = config.theme == .custom ? UIColor(config.customInfoColor) : nil
        let progress = config.readerAlwaysShowProgress ? "" : viewModel.progressString
        applyTitle(
            config.readerShowTitle ? viewModel.book.displayTitle : nil,
            subtitle: config.readerShowProgressTop && !progress.isEmpty ? progress : nil,
            infoColor: infoColor
        )
        
        let info = [viewModel.statisticsString, config.readerShowProgressTop ? "" : progress]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        infoLabel.text = info
        infoLabel.textColor = infoColor ?? secondaryLabel
        infoLabel.sizeToFit()
        
        let leading: [UIBarButtonItem] = verticalBar ? [] : [closeItem]
        let items: [UIBarButtonItem] = info.isEmpty
            ? leading + [.flexibleSpace(), optionsItem]
            : leading + [.flexibleSpace(), infoItem, .flexibleSpace(), optionsItem]
        if toolbarItems?.count != items.count {
            setToolbarItems(items, animated: false)
        }
        
        setBarsHidden(viewModel.focusMode)
    }
    
    private func applyTitle(_ title: String?, subtitle: String?, infoColor: UIColor?) {
        titleLabel.text = title
        titleLabel.isHidden = title == nil
        titleLabel.textColor = infoColor ?? .label
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.textColor = infoColor ?? .secondaryLabel
        navigationItem.titleView = title == nil && subtitle == nil ? nil : titleView
    }
    
    private func setBarsHidden(_ hidden: Bool) {
        guard let nav = navigationController, nav.isNavigationBarHidden != hidden else { return }
        nav.setNavigationBarHidden(hidden, animated: true)
        nav.setToolbarHidden(hidden, animated: true)
    }
}
