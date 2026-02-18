//
//  TTSManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 liulifox233.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation

class TTSManager: NSObject {
    static let shared = TTSManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        // Ensure audio session is active for playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
    
    func speak(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        
        let queryVoiceId = components.queryItems?.first(where: { $0.name == "voiceId" })?.value
        let hostVoiceId = url.host
        let voiceId = queryVoiceId ?? hostVoiceId
        
        let term = components.queryItems?.first(where: { $0.name == "term" })?.value
        let reading = components.queryItems?.first(where: { $0.name == "reading" })?.value
        
        let textToSpeak = term ?? reading
        
        guard let textToSpeak else { return }
        
        stop()
        
        let ssml: String
        if let reading = reading, !reading.isEmpty, reading != textToSpeak {
            let escapedTerm = escapeXML(textToSpeak)
            let escapedReading = escapeXML(reading)
            ssml = "<speak><sub alias=\"\(escapedReading)\">\(escapedTerm)</sub></speak>"
        } else {
            ssml = "<speak>\(escapeXML(textToSpeak))</speak>"
        }
        
        if let utterance = AVSpeechUtterance(ssmlRepresentation: ssml) {
            if let voiceId, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                utterance.voice = voice
            } else {
                 // Fallback to Japanese if no voice specified, or use default
                if let defaultVoice = AVSpeechSynthesisVoice(language: "ja-JP") {
                    utterance.voice = defaultVoice
                }
            }
            synthesizer.speak(utterance)
        } else {
            // Fallback if SSML fails for some reason
            let utterance = AVSpeechUtterance(string: textToSpeak)
             if let voiceId, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                utterance.voice = voice
            } else if let defaultVoice = AVSpeechSynthesisVoice(language: "ja-JP") {
                utterance.voice = defaultVoice
            }
            synthesizer.speak(utterance)
        }
    }
    
    func preview(voice: AVSpeechSynthesisVoice) {
        stop()
        let utterance = AVSpeechUtterance(string: "こんにちは")
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    func getAvailableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "ja") } 
    }
    
    private func escapeXML(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }
}
