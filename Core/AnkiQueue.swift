//
//  AnkiQueue.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class AnkiQueue {
    static let shared = AnkiQueue()

    private(set) var items: [QueuedAnkiNote] = []
    private static let queuedWords = "queued_words.json"
    private var isFlusing = false

    private init() { load() }

    public func enqueue(item: QueuedAnkiNote) {
        items.append(item)
    }

    public func flush(send: ([[String: Any]]) async throws -> Void) async -> Bool {
        guard !isFlusing, !items.isEmpty else { return false }
        isFlusing =  true
        defer { isFlusing = false }


        for i in 0..<items.count {
            if items[i].attempts >= 3 {
                remove(id: items[i].id)
                continue
            }

            guard let action = (try? JSONSerialization.jsonObject(with: items[i].actions)) as? [[String: Any]] else {
                print("Data wasn't a valid JSON object or wasn't typed [String: Any]")
                return false
            }

            do {
                try await send(action)
                remove(id: items[i].id)
            } catch is URLError {
                return false
            } catch let ankiConnectError as AnkiManager.AnkiConnectError {
                items[i].attempts += 1
                items[i].lastError = ankiConnectError.localizedDescription
            } catch {
                return false
            }
        }
        return true
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
            for note in notes {
                enqueue(item: note)
            }
        } else {
            print("[ANKI_QUEUE] File is empty/courrupt") // TODO: replace with better error handling
        }
    }

    func presist(queuedNote: QueuedAnkiNote) -> Bool {
        guard ((try? BookStorage.save(queuedNote, inside: BookStorage.getAppDirectory(), as: AnkiQueue.queuedWords)) != nil) else {
            return false
        }

        return true
    }







}
