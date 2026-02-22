//
//  WordAudioPlayer.swift
//  Hoshi Reader
//
//  Copyright © 2026 HuangAntimony.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AVFoundation

@MainActor
final class WordAudioPlayer {
    static let shared = WordAudioPlayer()
    
    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    
    private init() {}
    
    func stop() {
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
        
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    
    func play(urlString: String, requestedMode: AudioPlaybackMode) {
        guard let url = URL(string: urlString) else {
            return
        }
        
        stop()
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playback, mode: .default, options: categoryOptions(for: requestedMode))
            try session.setActive(true, options: [])
        } catch {
            return
        }
        
        let item = AVPlayerItem(url: url)
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
