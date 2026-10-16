// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// Terms of Use (EULA).
struct TermsOfUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Effective date: 27 August 2026")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                section("Agreement",
                        "By downloading or using \(BrandRuntime.displayName), you agree to these terms. "
                        + "If you do not agree, do not use the app.")

                section("What the app does",
                        "\(BrandRuntime.displayName) routes your internet traffic through an encrypted "
                        + "connection to a server we operate, so that the network you are on cannot "
                        + "read it. We do not keep a record of the sites you visit.")

                section("Subscriptions",
                        "Premium is an auto-renewable subscription. Payment is charged to your Apple "
                        + "ID at confirmation of purchase. The subscription renews automatically for "
                        + "the same period unless auto-renew is turned off at least 24 hours before "
                        + "the end of the current period. Your account is charged for renewal within "
                        + "24 hours of the end of the period. You can manage and cancel your "
                        + "subscription in your Apple ID account settings after purchase. "
                        + "Any unused portion of a free trial is forfeited when you buy a subscription.")

                section("Free access",
                        "In some regions the app is funded by donors and costs nothing. Where that is "
                        + "the case the app does not ask you to pay and no subscription is offered.")

                section("Acceptable use",
                        "Do not use the app to break the law of a country you are actually subject "
                        + "to, to attack or disrupt other systems, or to send bulk unsolicited "
                        + "messages. We may end access that is used this way.")

                section("No warranty",
                        "The app is provided as is. Connectivity depends on networks we do not "
                        + "control, and we cannot guarantee that it is available at all times or in "
                        + "all places.")

                section("Changes",
                        "We may update these terms. Continuing to use the app after an update means "
                        + "you accept the revised terms.")

                Text("Apple's standard licence terms also apply: "
                     + "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundColor(.secondary)
        }
    }
}
