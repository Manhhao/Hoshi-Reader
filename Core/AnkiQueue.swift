//
//  AnkiQueue.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Observation

@Observable
@MainActor
final class AnkiQueue {
    static let shared = AnkiQueue()

    private(set) var items: [QueuedAnkiNote] = []
    private static let queuedWords = "queued_words.json"
    private(set) var isFlushing = false

    private init() { load() }

    public func enqueue(item: QueuedAnkiNote) {
        items.append(item)
        guard presist() else {
            print("[ANKI_QUEUE] Failed to presist")
            return
        }
    }

    // returns the number of notes that reached Anki
    public func flush(send: ([String: Any]) async throws -> Void) async -> Int {
        guard !isFlushing, !items.isEmpty else { return 0 }
        isFlushing =  true
        defer { isFlushing = false; _ = presist() }

        var sent = 0
        var i = 0
        while i < items.count {
            // notes that keep failing stay queued with their error so nothing is lost,
            // they can be removed from the queue list in the AnkiConnect settings
            guard let action = (try? JSONSerialization.jsonObject(with: items[i].actions)) as? [String: Any] else {
                print("Data wasn't a valid JSON object or wasn't typed [String: Any]")
                remove(id: items[i].id)
                continue
            }

            do {
                try await send(action)
                print("Just flushed \(items[i].word)")
                remove(id: items[i].id)
                sent += 1
            } catch let ankiConnectError as AnkiManager.AnkiConnectError {
                items[i].attempts += 1
                items[i].lastError = ankiConnectError.localizedDescription
                print(items[i].lastError ?? "Error print lastError")
                i += 1
            } catch {
                print("[ANKI_QUEUE] Flush stopped at \(items[i].word): \(error)")
                return sent
            }
        }
        return sent
    }

    public func contains(word: String) -> Bool {
        items.contains { $0.word == word }
    }

    // removes a note from outside a flush, e.g. from the settings list
    public func delete(id: UUID) {
        guard !isFlushing else { return }
        remove(id: id)
        _ = presist()
    }

    public func remove(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
        }
    }

    // load all the notes from BookStorage
    private func load() {
        guard let file =  try? BookStorage.getAppDirectory().appending(path: AnkiQueue.queuedWords)  else { return }

        let notes = BookStorage.load([QueuedAnkiNote].self, from: file)
        if let notes = notes {
            items.append(contentsOf: notes)
        } else {
            print("[ANKI_QUEUE] File is empty/courrupt") // TODO: replace with better error handling
        }
    }

    private func presist() -> Bool {
        guard ((try? BookStorage.save(items, inside: BookStorage.getAppDirectory(), as: AnkiQueue.queuedWords)) != nil) else {
            return false
        }

        return true
    }







}
