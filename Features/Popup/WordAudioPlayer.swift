//
//  WordAudioPlayer.swift
//  Hoshi Reader
//
//  Copyright © 2026 HuangAntimony.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AVFoundation

actor WordAudioPlayer {
    static let shared = WordAudioPlayer()
    
    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var id: UUID?
    private var otherAudioActive = false
    
    private init() {}
    
    func setOtherAudioActive(_ active: Bool) {
        otherAudioActive = active
    }
    
    func stop(id: UUID? = nil) {
        if let id, id != self.id {
            return
        }
        cleanupPlayback()
    }
    
    func play(urlString: String, requestedMode: AudioPlaybackMode, id: UUID) {
        guard let url = URL(string: urlString) else {
            return
        }
        
        stopPlayer()
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: categoryOptions(for: requestedMode))
            if !otherAudioActive {
                try session.setActive(true, options: [])
            }
        } catch {
            return
        }
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.id = id
        
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.cleanupPlayback()
            }
        }
        
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.cleanupPlayback()
            }
        }
        
        player.play()
    }
    
    private func cleanupPlayback() {
        stopPlayer()
        if !otherAudioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
    
    private func stopPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        id = nil
        
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
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
