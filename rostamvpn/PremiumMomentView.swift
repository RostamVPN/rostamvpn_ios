// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// The three seconds after someone pays.
struct PremiumMomentView: View {
    let onDone: () -> Void

    @State private var appeared = false

    private let perks = ["Unlimited data", "Full speed, always", "Every region"]

    var body: some View {
        ZStack {
            Color.adaptiveBg.opacity(0.97).ignoresSafeArea()

            VStack(spacing: 0) {
                Image(systemName: "star.fill")
                    .font(.system(size: 64))

                    .foregroundColor(.brandGraphicOnBg)
                Spacer().frame(height: 20)
                Text("Premium is active")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 10)

                Text("Full speed, every region.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 28)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(perks, id: \.self) { perk in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.brandGraphicOnBg)
                            Text(LocalizedStringKey(perk))
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            .scaleEffect(appeared ? 1 : 0.88)
            .opacity(appeared ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { onDone() }
        }
    }
}
