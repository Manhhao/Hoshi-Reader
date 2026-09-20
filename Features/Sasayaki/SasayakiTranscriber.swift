//
//  SasayakiTranscriber.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, *)
struct SasayakiTranscriber {
    enum TranscriptionError: Error {
        case localeUnavailable
    }
    
    static func transcribe(
        file: AVAudioFile,
        from startTime: Double,
        onDownload: @escaping @MainActor (Double) -> Void,
        onTokens: ([SasayakiToken], Double) -> Void
    ) async throws {
        guard let locale = await SpeechTranscriber.supportedLocales.first(where: {
            $0.identifier(.bcp47).lowercased().hasPrefix("ja")
        }) else {
            throw TranscriptionError.localeUnavailable
        }
        file.framePosition = AVAudioFramePosition(startTime * file.processingFormat.sampleRate)
        
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        var analyzer: SpeechAnalyzer?
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in onDownload(fraction) }
                }
                defer { observation.invalidate() }
                try await request.downloadAndInstall()
            }
            analyzer = try await SpeechAnalyzer(
                inputAudioFile: file,
                modules: [transcriber],
                finishAfterFile: true
            )
            for try await result in transcriber.results {
                try Task.checkCancellation()
                guard result.isFinal else {
                    continue
                }
                let tokens = result.text.runs.compactMap { run -> SasayakiToken? in
                    guard let range = run.audioTimeRange else {
                        return nil
                    }
                    return SasayakiToken(
                        text: String(result.text.characters[run.range]),
                        start: startTime + range.start.seconds,
                        end: startTime + range.end.seconds
                    )
                }
                onTokens(tokens, startTime + result.range.end.seconds)
            }
        } catch {
            await analyzer?.cancelAndFinishNow()
            await AssetInventory.release(reservedLocale: locale)
            throw error
        }
        await analyzer?.cancelAndFinishNow()
        await AssetInventory.release(reservedLocale: locale)
    }
}
