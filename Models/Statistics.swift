//
//  Statistics.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// ttu format
struct Statistics: Codable {
    let title: String
    let dateKey: String
    var charactersRead: Int
    var readingTime: Int
    var minReadingSpeed: Int
    var altMinReadingSpeed: Int
    var lastReadingSpeed: Int
    var maxReadingSpeed: Int
    var lastStatisticModified: Int
}
