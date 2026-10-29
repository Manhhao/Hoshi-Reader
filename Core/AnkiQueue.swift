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

    // private init() { load() }






}
