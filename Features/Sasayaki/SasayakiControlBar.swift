//
//  SasayakiControlBar.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SasayakiControlBar: View {
    var player: SasayakiPlayer
    let verticalWriting: Bool
    let left: Bool
    @Binding var expanded: Bool
    
    @Namespace private var namespace
    
    private let size: CGFloat = 44
    private let spacing: CGFloat = 10
    
    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: spacing) {
                    buttons
                }
            } else {
                buttons
            }
        }
        .padding(left ? .leading : .trailing, expanded ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left ? .leading : .trailing)
        .animation(.bouncy.speed(1.25), value: expanded)
    }
    
    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: spacing) {
            if expanded {
                controlButton("15.arrow.trianglehead.counterclockwise", 16, "skipBack") {
                    player.skip(forward: verticalWriting)
                }
                controlButton("backward.fill", 18, "prev") {
                    verticalWriting ? player.nextCue() : player.prevCue()
                }
                controlButton(player.isPlaying ? "pause.fill" : "play.fill", 22, "center") {
                    player.togglePlayback()
                }
                controlButton("forward.fill", 18, "next") {
                    verticalWriting ? player.prevCue() : player.nextCue()
                }
                controlButton("15.arrow.trianglehead.clockwise", 16, "skipForward") {
                    player.skip(forward: !verticalWriting)
                }
            } else {
                Button {
                    expanded = true
                } label: {
                    Image(systemName: left ? "chevron.right" : "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 17, height: 68)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .glass(handleShape, id: "center", in: namespace)
            }
        }
    }
    
    private func controlButton(_ icon: String, _ iconSize: CGFloat, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glass(Capsule(), id: id, in: namespace)
    }
    
    private var handleShape: UnevenRoundedRectangle {
        left
        ? UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous)
        : UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
    }
}

private extension View {
    @ViewBuilder
    func glass<S: InsettableShape>(_ shape: S, id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.quaternary, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                .transition(.opacity)
        }
    }
}
