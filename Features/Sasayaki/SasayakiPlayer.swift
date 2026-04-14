//
//  SasayakiPlayer.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import MediaPlayer
import SwiftUI

struct CueTimeline {
    private let cues: [SasayakiMatch]
    
    init(match: SasayakiMatchData? = nil) {
        cues = match?.matches ?? []
    }
    
    func nextCue(after time: Double) -> Double? {
        var index = findCue(time)
        if index < cues.count, cues[index].startTime == time {
            index += 1
        }
        return index < cues.count ? cues[index].startTime : nil
    }
    
    func prevCue(before time: Double) -> Double? {
        let index = findCue(time)
        return index > 0 ? cues[index - 1].startTime : nil
    }
    
    func cue(at time: Double) -> SasayakiMatch? {
        let index = findCue(time)
        if index < cues.count, abs(cues[index].startTime - time) <= 0.01 {
            return cues[index]
        }
        if index == 0 {
            return nil
        }
        let cue = cues[index - 1]
        return time <= cue.endTime ? cue : nil
    }
    
    private func findCue(_ time: Double) -> Int {
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].startTime < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

@Observable
@MainActor
class SasayakiPlayer {
    var errorMessage: String?
    var isRestoring = false
    
    var matchData: SasayakiMatchData?
    var timeline = CueTimeline()
    
    var playback = SasayakiPlaybackData(lastPosition: 0)
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false { didSet { updateIdleTimerDisabled() } }
    var stopPlaybackTime: Double?
    var lastUpdate = -1
    
    var delay: Double = 0 {
        didSet {
            guard !isRestoring else { return }
            savePlayback()
            updateCue(for: currentTime)
        }
    }
    var rate: Float = 1 {
        didSet {
            guard !isRestoring else { return }
            savePlayback()
            player?.defaultRate = rate
            if isPlaying {
                player?.rate = rate
            }
        }
    }
    var autoScroll: Bool { UserDefaults.standard.object(forKey: "sasayakiAutoScroll") as? Bool ?? true }
    
    var currentCue: SasayakiMatch?
    var pendingCue: SasayakiMatch?
    var chapterTransition = false
    var shouldResume = false
    var resumeAfterInterruption = false
    var hasPlayedOnce = false
    var player: AVPlayer?
    var nowPlayingSession: MPNowPlayingSession?
    var timeObserver: Any?
    var endObserver: NSObjectProtocol?
    var interruptionObserver: NSObjectProtocol?
    var audioURL: URL?
    var artwork: MPMediaItemArtwork?
    
    var hasAudio: Bool { player != nil }
    var hasMatch: Bool { matchData != nil }
    
    let bookMetadata: BookMetadata?
    let rootURL: URL
    let bridge: WebViewBridge
    let loadChapter: (Int, Double) -> Void
    let getCurrentIndex: () -> Int
    
    init(rootURL: URL, bridge: WebViewBridge, loadChapter: @escaping (Int, Double) -> Void, getCurrentIndex: @escaping () -> Int) {
        self.rootURL = rootURL
        self.bridge = bridge
        self.loadChapter = loadChapter
        self.getCurrentIndex = getCurrentIndex
        self.bookMetadata = BookStorage.loadMetadata(root: rootURL)
        
        matchData = BookStorage.loadSasayakiMatch(root: rootURL)
        if !hasMatch {
            return
        }
        timeline = CueTimeline(match: matchData)
        
        isRestoring = true
        playback = BookStorage.loadSasayakiPlayback(root: rootURL) ?? SasayakiPlaybackData(lastPosition: 0)
        currentTime = playback.lastPosition
        delay = playback.delay
        rate = playback.rate
        lastUpdate = Int(currentTime.rounded(.down))
        isRestoring = false
    }
    
    func importAudio(from url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        teardown()
        
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        playback.audioBookmark = bookmark
        savePlayback()
        
        audioURL = url
        errorMessage = nil
        setupPlayer(url: url)
    }
    
    func cues(for chapterIndex: Int) -> String {
        let cues = matchData?.matches
            .filter { $0.chapterIndex == chapterIndex }
            .map { SasayakiCueRange(id: $0.id, start: $0.start, length: $0.length) } ?? []
        let data = try? JSONEncoder().encode(cues)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    
    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }
    
    func updateIdleTimerDisabled() {
        UIApplication.shared.isIdleTimerDisabled = isPlaying && autoScroll
    }
    
    func nextCue() {
        stopPlaybackTime = nil
        let next = timeline.nextCue(after: currentCue?.startTime ?? currentTime - delay)
        guard let next else { return }
        seek(seconds: next + delay)
    }
    
    func prevCue() {
        stopPlaybackTime = nil
        let previous = timeline.prevCue(before: currentCue?.startTime ?? max(0, currentTime - delay)) ?? 0
        seek(seconds: previous + delay)
    }
    
    func handleRestoreCompleted(currentIndex: Int) {
        guard hasMatch, chapterTransition else { return }
        
        let cue: SasayakiMatch?
        if let pendingCue, pendingCue.chapterIndex == currentIndex {
            cue = pendingCue
        } else if let active = timeline.cue(at: currentTime - delay), active.chapterIndex == currentIndex {
            cue = active
        } else {
            cue = nil
        }
        
        let resume = shouldResume
        chapterTransition = false
        shouldResume = false
        pendingCue = nil
        
        if let cue {
            displayCue(cue, reveal: autoScroll && hasPlayedOnce)
        } else {
            clearDisplayedCue()
        }
        
        if resume {
            startPlayback()
        }
    }
    
    func prepareTransition() {
        shouldResume = isPlaying
        chapterTransition = true
        stopPlaybackTime = nil
        clearDisplayedCue()
        if isPlaying {
            pausePlayback()
        }
    }
    
    func findCue(chapterIndex: Int, offset: Int) -> SasayakiMatch? {
        guard let matches = matchData?.matches else { return nil }
        var low = 0
        var high = matches.count
        while low < high {
            let mid = (low + high) / 2
            let m = matches[mid]
            if m.chapterIndex < chapterIndex || (m.chapterIndex == chapterIndex && m.start + m.length <= offset) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return (low < matches.count && matches[low].chapterIndex == chapterIndex && matches[low].start <= offset) ? matches[low] : nil
    }
    
    func playCue(from cue: SasayakiMatch, stop: Bool) {
        stopPlaybackTime = nil
        if isPlaying {
            pausePlayback()
        }
        seek(
            seconds: cue.startTime + delay,
            startPlayback: true,
            updateCue: false,
            stopPlaybackTime: stop ? cue.endTime + delay : nil
        )
    }
    
    func teardown() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        if let token = timeObserver, let player {
            player.removeTimeObserver(token)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        player = nil
        timeObserver = nil
        endObserver = nil
        interruptionObserver = nil
        isPlaying = false
        Task { await WordAudioPlayer.shared.setOtherAudioActive(false) }
        duration = 0
        stopPlaybackTime = nil
        artwork = nil
        
        clearDisplayedCue()
        if let center = nowPlayingSession?.remoteCommandCenter {
            center.playCommand.removeTarget(nil)
            center.pauseCommand.removeTarget(nil)
            center.togglePlayPauseCommand.removeTarget(nil)
            center.previousTrackCommand.removeTarget(nil)
            center.nextTrackCommand.removeTarget(nil)
            center.changePlaybackPositionCommand.removeTarget(nil)
        }
        nowPlayingSession = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        
        if let url = audioURL {
            url.stopAccessingSecurityScopedResource()
            audioURL = nil
        }
    }
    
    func cueSentenceAudio(_ cue: SasayakiMatch, sentence: String) async -> Data? {
        guard let url = audioURL else {
            return nil
        }
        
        let range = expandCue(cue, sentence: sentence)
        let asset = AVURLAsset(url: url)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sasayaki_audio.m4a")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        
        let start = max(0, range.start + delay)
        let end = max(start, range.end + delay)
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        try? await session.export(to: output, as: .m4a)
        return try? Data(contentsOf: output)
    }
    
    private func expandCue(_ cue: SasayakiMatch, sentence: String) -> (start: Double, end: Double) {
        guard let cues = matchData?.matches.filter({ $0.chapterIndex == cue.chapterIndex }),
              let index = cues.firstIndex(where: { $0.id == cue.id }) else {
            return (cue.startTime, cue.endTime)
        }
        
        var start = index
        var end = index
        let filteredSentence = sentence.filtered()
        while start > cues.startIndex, filteredSentence.contains(cues[start - 1].text.filtered()) { start -= 1 }
        while end < cues.index(before: cues.endIndex), filteredSentence.contains(cues[end + 1].text.filtered()) { end += 1 }
        return (cues[start].startTime, cues[end].endTime)
    }
    
    private func startPlayback() {
        guard let player else { return }
        setupNowPlayingSession()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        player.play()
        isPlaying = true
        hasPlayedOnce = true
        Task { await WordAudioPlayer.shared.setOtherAudioActive(true) }
    }
    
    private func pausePlayback() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }
    
    private func tick(_ seconds: Double) {
        currentTime = seconds
        
        if let duration = player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            self.duration = duration
        }
        
        if let stopTime = stopPlaybackTime, seconds >= stopTime {
            stopPlaybackTime = nil
            if isPlaying {
                pausePlayback()
            }
        }
        
        let second = Int(seconds.rounded(.down))
        if second != lastUpdate {
            lastUpdate = second
            playback.lastPosition = seconds
            savePlayback()
        }
        
        updateCue(for: seconds)
    }
    
    private func seek(seconds: Double, startPlayback: Bool = false, updateCue: Bool = true, stopPlaybackTime: Double? = nil) {
        guard let player else { return }
        
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopPlaybackTime = stopPlaybackTime
                if updateCue {
                    self.tick(seconds)
                } else {
                    self.currentTime = seconds
                }
                
                if startPlayback {
                    self.startPlayback()
                }
            }
        }
    }
    
    private func setupPlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.defaultRate = rate
        player?.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.125, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in self?.tick(time.seconds) }
        }
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopPlaybackTime = nil
                self.isPlaying = false
            }
        }
        
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleInterruption(type, options: options)
            }
        }
        
        setupArtwork(from: item.asset)
    }
    
    private func setupNowPlayingSession() {
        guard let player, nowPlayingSession == nil else { return }
        let item = player.currentItem
        player.replaceCurrentItem(with: nil)
        nowPlayingSession = MPNowPlayingSession(players: [player])
        nowPlayingSession?.automaticallyPublishesNowPlayingInfo = true
        configureRemoteCommandCenter(nowPlayingSession!.remoteCommandCenter)
        player.replaceCurrentItem(with: item)
        nowPlayingSession?.becomeActiveIfPossible()
    }
    
    func restoreAudio() {
        guard let bookmark = playback.audioBookmark else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        if isStale {
            playback.audioBookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            savePlayback()
        }
        audioURL = url
        setupPlayer(url: url)
    }
    
    private func savePlayback() {
        playback.delay = delay
        playback.rate = rate
        try? BookStorage.save(playback, inside: rootURL, as: FileNames.sasayakiPlayback)
    }
    
    private func updateCue(for time: Double) {
        guard hasAudio, hasMatch, !chapterTransition else { return }
        
        let lookupTime = time - delay
        guard let cue = timeline.cue(at: lookupTime) else {
            clearDisplayedCue()
            return
        }
        
        if cue.id == currentCue?.id {
            return
        }
        
        let currentIndex = getCurrentIndex()
        if cue.chapterIndex == currentIndex {
            displayCue(cue, reveal: autoScroll && hasPlayedOnce)
        } else if autoScroll, hasPlayedOnce {
            currentCue = cue
            pendingCue = cue
            loadChapter(cue.chapterIndex, 0)
        } else {
            clearDisplayedCue()
        }
    }
    
    private func displayCue(_ cue: SasayakiMatch, reveal: Bool) {
        currentCue = cue
        bridge.send(.highlightSasayakiCue(id: cue.id, reveal: reveal))
    }
    
    private func clearDisplayedCue() {
        guard currentCue != nil else { return }
        currentCue = nil
        bridge.send(.clearSasayakiCue)
    }
    
    private func handleInterruption(_ type: AVAudioSession.InterruptionType, options: UInt) {
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            pausePlayback()
        case .ended:
            if resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                resumeAfterInterruption = false
                startPlayback()
            }
        @unknown default:
            break
        }
    }
    
    private func configureRemoteCommandCenter(_ center: MPRemoteCommandCenter) {
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.startPlayback() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.prevCue() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextCue() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(seconds: event.positionTime) }
            return .success
        }
    }
    
    private func setupArtwork(from asset: AVAsset) {
        Task {
            let metadata = try? await asset.load(.metadata)
            let artworkItem = AVMetadataItem
                .metadataItems(from: metadata ?? [], filteredByIdentifier: .commonIdentifierArtwork)
                .first
            let artworkData = try? await artworkItem?.load(.dataValue)
            
            let image =
            artworkData.flatMap(UIImage.init(data:)) ??
            bookMetadata?.coverURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(UIImage.init(data:))
            
            guard let image else { return }
            
            await MainActor.run {
                artwork = Self.makeArtwork(from: image)
                updateNowPlayingInfo()
            }
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let item = player?.currentItem else { return }
        
        var info: [String: Any] = [:]
        
        if let title = bookMetadata?.title, !title.isEmpty {
            info[MPMediaItemPropertyTitle] = title
        }
        if let artwork = artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        item.nowPlayingInfo = info
    }
    
    private static nonisolated func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
