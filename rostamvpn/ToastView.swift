// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// A transient message that slides in over the top of whatever is on screen.
private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Double

    /// What is currently on screen. Separate from `message` so the exit animation
    /// can finish after the binding has already been cleared.
    @State private var shown: String?

    /// Bumped on every new message. Drives `.task(id:)`, so a replacement cancels
    /// the previous auto-dismiss timer instead of racing it.
    @State private var generation = 0

    private let tealDark = Deep.ground
    private let tealLight = Deep.top

    func body(content: Content) -> some View {
        content

            .overlay(alignment: .top) {
                if let text = shown {
                    card(text)
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .onAppear { adopt(message) }
            .onChange(of: message) { adopt($0) }
            .task(id: generation) {
                guard generation > 0, shown != nil else { return }
                let ns = UInt64(max(0.5, duration) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }

    private func card(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\u{2139}")
                .font(.subheadline)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [tealDark, tealLight],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)

        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isStaticText, .isButton])
        .accessibilityHint(Text("Double tap to dismiss"))
    }

    private func adopt(_ new: String?) {
        guard let new, !new.isEmpty else {
            if shown != nil { withAnimation(.easeIn(duration: 0.2)) { shown = nil } }
            return
        }
        withAnimation(.easeOut(duration: 0.25)) { shown = new }
        generation &+= 1
        announce(new)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) { shown = nil }
        if message != nil { message = nil }
    }

    /// A purely visual transient message does not exist for a VoiceOver user: it
    /// appears and disappears without ever taking focus, so nothing reads it. Post
    /// it explicitly.
    private func announce(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}

extension View {
    /// Show a transient message over this view.
    func toast(message: Binding<String?>, duration: Double = 4) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}
