// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import RostamKit

/// The `tabs` treatment's root: Connect · Account. Selected by the manifest's
/// `branding.style`, never by brand id. The last tab is remembered.
struct IPTabsRoot: View {
    /// Type-erased: it carries ContentView's Guardian sheet and poll task.
    let connect: AnyView
    let account: IPAccountTab
    @AppStorage("ipTab", store: BrandRuntime.defaults) private var tab = "connect"

    init<C: View>(connect: C, account: IPAccountTab) {
        self.connect = AnyView(connect)
        self.account = account
        Self.styleTabBar()
    }

    var body: some View {
        TabView(selection: $tab) {
            connect
                .tabItem { Label("Connect", systemImage: "dot.radiowaves.left.and.right") }
                .tag("connect")
            account
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag("account")
        }
        .tint(IPTheme.accent)
    }

    /// The design's bar: the page ground with a hairline, in both modes. On iOS 15
    /// the scroll-edge appearance must be set too, or the bar turns transparent
    /// over scrolled content. Only this treatment calls it.
    private static var styled = false
    private static func styleTabBar() {
        guard !styled else { return }
        styled = true
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(IPTheme.bg)
        a.shadowColor = UIColor(IPTheme.hairline)
        let normal = UIColor(IPTheme.dim)
        for item in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }
}
