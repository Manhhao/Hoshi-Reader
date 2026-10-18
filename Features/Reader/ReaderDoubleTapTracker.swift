//
//  ReaderDoubleTapTracker.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CoreGraphics

@MainActor
final class ReaderDoubleTapTracker {
    enum Tap {
        case single(id: Int)
        case double
    }

    static let timeout: TimeInterval = 0.25
    static let slop: CGFloat = 36

    private var lastTap: (id: Int, time: TimeInterval, point: CGPoint)?
    private var nextID = 0
    private var pendingSingleTap: DispatchWorkItem?

    func registerTap(at point: CGPoint) -> Tap {
        let now = ProcessInfo.processInfo.systemUptime
        cancelPendingSingleTap()
        if let lastTap,
           now - lastTap.time <= Self.timeout,
           abs(point.x - lastTap.point.x) <= Self.slop,
           abs(point.y - lastTap.point.y) <= Self.slop {
            self.lastTap = nil
            return .double
        }

        nextID += 1
        lastTap = (nextID, now, point)
        return .single(id: nextID)
    }

    func resolveSingleTap(id: Int, deferred: Bool, action: @escaping () -> Void) {
        guard let lastTap, lastTap.id == id else { return }
        guard deferred else {
            self.lastTap = nil
            action()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lastTap?.id == id else { return }
            self.lastTap = nil
            self.pendingSingleTap = nil
            action()
        }
        pendingSingleTap = work
        let remaining = max(0, Self.timeout - (ProcessInfo.processInfo.systemUptime - lastTap.time))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func cancelPendingSingleTap() {
        pendingSingleTap?.cancel()
        pendingSingleTap = nil
    }
}
