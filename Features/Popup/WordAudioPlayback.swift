//
//  WordAudioPlayback.swift
//  Hoshi Reader
//
//  Copyright © 2026 HuangAntimony.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AVFoundation

@MainActor
final class AppAudioSessionController {
    static let shared = AppAudioSessionController()

    private var configuredMode: AudioPlaybackMode?
    private var isSessionActive = false

    private init() {}

    func configureForWordPlayback(mode: AudioPlaybackMode) -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            if configuredMode != mode {
                try session.setCategory(.playback, mode: .default, options: categoryOptions(for: mode))
                configuredMode = mode
            }
            if !isSessionActive {
                try session.setActive(true, options: [])
                isSessionActive = true
            }
            return true
        } catch {
            configuredMode = nil
            isSessionActive = false
            #if DEBUG
            print("Failed to configure AVAudioSession for word playback: \(error)")
            #endif
            return false
        }
    }

    func deactivateAfterWordPlayback() {
        guard isSessionActive else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
        } catch {
            isSessionActive = false
            #if DEBUG
            print("Failed to deactivate AVAudioSession after word playback: \(error)")
            #endif
        }
    }

    private func categoryOptions(for mode: AudioPlaybackMode) -> AVAudioSession.CategoryOptions {
        switch mode {
        case .interrupt:
            return []
        case .duck:
            return [.mixWithOthers, .duckOthers]
        case .mix:
            return [.mixWithOthers]
        }
    }
}

@MainActor
final class WordAudioPlayer {
    static let shared = WordAudioPlayer()
    
    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var loadRequestToken = UUID()
    private var hasActiveWordSession = false
    
    private init() {}
    
    func stop() {
        loadRequestToken = UUID()
        
        player?.pause()
        player = nil
        
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        
        if hasActiveWordSession {
            AppAudioSessionController.shared.deactivateAfterWordPlayback()
            hasActiveWordSession = false
        }
    }
    
    func play(urlString: String, requestedMode: AudioPlaybackMode) async -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        
        stop()
        let requestToken = UUID()
        loadRequestToken = requestToken
        
        let asset = AVURLAsset(url: url)
        let isPlayable: Bool
        
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            #if DEBUG
            print("Failed to load word audio asset: \(error)")
            #endif
            return false
        }
        
        guard loadRequestToken == requestToken, isPlayable else {
            return false
        }
        
        guard AppAudioSessionController.shared.configureForWordPlayback(mode: requestedMode) else {
            return false
        }
        hasActiveWordSession = true
        
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        
        player.play()
        return true
    }
}
