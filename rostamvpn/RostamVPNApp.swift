// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NetworkExtension
import BackgroundTasks
import Combine
import RostamKit
import os.log

/// The ONE network-extension provider this app drives.
enum TunnelProfile {
    static var provider: String { BrandRuntime.tunnelBundleID }

    static var legacyProviders: [String] { BrandRuntime.legacyTunnelIDs }

    private static func providerID(_ manager: NEVPNManager) -> String? {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerBundleIdentifier
    }

    static func isOurs(_ manager: NEVPNManager) -> Bool {
        providerID(manager) == provider
    }

    /// A profile THIS brand installed in an earlier version and no longer uses.
    /// Never true for another app's profile: only ids this build declares.
    static func isStaleOurs(_ manager: NEVPNManager) -> Bool {
        guard let id = providerID(manager), id != provider else { return false }
        return legacyProviders.contains(id)
    }

    /// Remove the profiles above. Called once at launch. Best effort and silent: a
    /// device that never had one is the common case, and a removal that fails is
    /// not worth telling a user about.
    static func removeStaleProfiles() {
        guard !legacyProviders.isEmpty else { return }
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            for m in (managers ?? []) where isStaleOurs(m) {
                m.removeFromPreferences { _ in }
            }
        }
    }
}

@main
struct RostamVPNApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("theme", store: BrandRuntime.defaults)
    private var themeSetting: String = "auto"

    /// The UI language override. "auto" follows the device, exactly as Android's
    /// `language_auto` does, and every other value is a BCP-47 code from the same
    /// six the Android sheet offers.
    @AppStorage("language", store: BrandRuntime.defaults)
    private var languageSetting: String = "auto"

    /// TRUE on every launch, unconditionally.
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(splashDone: !showSplash)
                    .preferredColorScheme(colorSchemeFor(themeSetting))
                    .environment(\.locale, localeFor(languageSetting))

                if showSplash {
                    RostamSplash { showSplash = false }
                        .transition(.identity)
                        .zIndex(1)
                }
            }
        }
    }
}

/// "auto" follows the device; anything else pins the catalog lookup.
private func localeFor(_ code: String) -> Locale {
    code == "auto" ? Locale.autoupdatingCurrent : Locale(identifier: code)
}

/// Convert theme string to optional ColorScheme (nil = follow system).
private func colorSchemeFor(_ theme: String) -> ColorScheme? {
    switch theme {
    case "light": return .light
    case "dark": return .dark
    default: return BrandRuntime.style.forcesDark ? .dark : nil
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    private let suiteName = BrandRuntime.appGroup
    /// Derived from the BUILD, not written out: a literal here is one brand's id
    /// inside every brand's binary.
    private let bgTaskId = BrandRuntime.appBundleID + ".configRefresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()

        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            self?.handleConfigRefresh(task: task as! BGAppRefreshTask)
        }
        scheduleConfigRefresh()

        DispatchQueue.global(qos: .utility).async {
            self.fetchAndApplyDnsConfig()
        }

        TunnelProfile.removeStaleProfiles()

        return true
    }

    /// Notification posted after DNS config is fetched so UI can reload dynamic
    /// data.
    static let configDidUpdateNotification = Notification.Name("RostamConfigDidUpdate")

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NSLog("[Push] Device token: \(token)")
        UserDefaults(suiteName: suiteName)?.set(token, forKey: "apnsDeviceToken")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("[Push] Registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NSLog("[Push] Silent notification received")

        DispatchQueue.global(qos: .utility).async {
            let updated = self.fetchAndApplyDnsConfig()
            DispatchQueue.main.async {
                if updated {
                    self.notifyExtensionOfUpdate()
                    completionHandler(.newData)
                } else {
                    completionHandler(.noData)
                }
            }
        }
    }

    private func scheduleConfigRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("[BG] Schedule failed: \(error.localizedDescription)")
        }
    }

    private func handleConfigRefresh(task: BGAppRefreshTask) {
        scheduleConfigRefresh()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        DispatchQueue.global(qos: .utility).async {
            let updated = self.fetchAndApplyDnsConfig()
            if updated { self.notifyExtensionOfUpdate() }
            task.setTaskCompleted(success: updated)
        }
    }

    /// Fetch the SEALED config and hand it to the tunnel through the App Group.
    /// RemoteConfig discards anything that does not verify -- this file decides
    /// which servers users connect to.
    @discardableResult
    private func fetchAndApplyDnsConfig() -> Bool {
        RemoteConfig.refresh { updated in
            guard updated else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: AppDelegate.configDidUpdateNotification, object: nil)
            }
        }
        return true
    }

    private func notifyExtensionOfUpdate() {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in

            guard let manager = (managers ?? []).first(where: { TunnelProfile.isOurs($0) }),
                  let session = manager.connection as? NETunnelProviderSession,
                  session.status == .connected else { return }

            let msg = "config-updated".data(using: .utf8)!
            try? session.sendProviderMessage(msg) { _ in
                NSLog("[Config] Extension notified of config update")
            }
        }
    }
}

extension Color {
    static let brand1 = BrandTheme.primary
    static let brand2 = BrandTheme.secondary
    static let dangerRed = BrandTheme.danger
    static let bannerTeal = BrandTheme.secondary

    static let sidebarTop = Surface.sheetTop
    static let sidebarBot = Surface.sheetBottom

    static let adaptiveBg = Color(UIColor { t in
        UIColor(t.userInterfaceStyle == .dark ? Surface.bgDark : Surface.bgLight)
    })
    static let adaptiveSurface = Color(UIColor { t in
        UIColor(t.userInterfaceStyle == .dark ? Surface.surfaceDark : Surface.cardLight)
    })
    static let adaptiveCard = Color(UIColor { t in
        UIColor(t.userInterfaceStyle == .dark ? Surface.cardDark : Surface.cardLight)
    })
    static let adaptiveScrim = Color(UIColor { t in
        UIColor(t.userInterfaceStyle == .dark ? Surface.bgDark : Surface.cardLight)
    })
}

private let suiteName = BrandRuntime.appGroup

enum VpnState {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}

/// Generates random start/end parameters for a single Ken Burns cycle.
private struct KenBurnsKeyframe {
    let startScale: CGFloat
    let endScale: CGFloat
    let startX: CGFloat
    let endX: CGFloat
    let startY: CGFloat
    let endY: CGFloat

    static func random(screenWidth: CGFloat, screenHeight: CGFloat) -> KenBurnsKeyframe {
        let maxPanX = screenWidth * 0.4
        let maxPanY = screenHeight * 0.04
        return KenBurnsKeyframe(
            startScale: .random(in: 1.10...1.30),
            endScale: .random(in: 1.10...1.30),
            startX: .random(in: -maxPanX...maxPanX),
            endX: .random(in: -maxPanX...maxPanX),
            startY: .random(in: -maxPanY...maxPanY),
            endY: .random(in: -maxPanY...maxPanY)
        )
    }
}

struct ConnectedBannerView: View {
    let show: Bool
    let onDismiss: () -> Void

    var body: some View {
        if show {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                Text("Connected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
            }

            .foregroundColor(Color.mostLegibleOn(.bannerTeal, .white, Surface.bgDark))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.bannerTeal)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The app background: a two-stop vertical gradient that warms when connected.
struct ConnectionGradientBackground: View {
    let isConnected: Bool
    @Environment(\.colorScheme) private var scheme

    /// The connected wash, DERIVED.
    private func wash(_ amount: Double) -> Color {
        guard isConnected else { return Color.adaptiveBg }
        return Surface.connectedWash(amount, dark: scheme == .dark)
    }
    private var top: Color { wash(0.055) }
    private var bottom: Color { wash(0.105) }

    var body: some View {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.9), value: isConnected)
    }
}

struct ConnectShockwaveView: View {
    let fired: Bool

    @State private var fireTime: Date? = nil

    private struct BurstDot {
        let angle: CGFloat
        let speed: CGFloat
        let size: CGFloat
        let useBrand1: Bool
    }

    private let dots: [BurstDot] = (0..<24).map { i in
        BurstDot(
            angle: CGFloat(i) * 15.0 + CGFloat.random(in: 0...10),
            speed: 0.6 + CGFloat.random(in: 0...0.4),
            size: 2.0 + CGFloat.random(in: 0...4),
            useBrand1: Bool.random()
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: fireTime == nil)) { timeline in
            Canvas { context, size in
                guard let ft = fireTime else { return }
                let elapsed = CGFloat(timeline.date.timeIntervalSince(ft))
                guard elapsed < 1.2 else { return }

                let cx = size.width / 2
                let cy = size.height * 0.45
                let maxR = size.width * 0.7

                for (delay, strokeW): (CGFloat, CGFloat) in [(0, 3), (0.1, 2), (0.2, 1.5)] {
                    let t = max(0, elapsed - delay)
                    let dur: CGFloat = 0.8 + delay * 2
                    let p = min(t / dur, 1.0)
                    let eased = 1.0 - pow(1.0 - p, 3)
                    guard eased > 0 else { continue }
                    let r = maxR * eased
                    let a = max(0, (1.0 - eased) * 0.6)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .color(Color.brand2.opacity(a)),
                        lineWidth: strokeW * (1.0 - eased * 0.5)
                    )
                }

                let bp = min(elapsed / 0.7, 1.0)
                let bEased = 1.0 - pow(1.0 - bp, 3)
                if bEased > 0 {
                    for d in dots {
                        let rad = d.angle * .pi / 180
                        let dist = maxR * 0.8 * bEased * d.speed
                        let px = cx + cos(rad) * dist
                        let py = cy + sin(rad) * dist
                        let a = max(0, (1.0 - bEased) * 0.8)
                        let ps = d.size * (1.0 - bEased * 0.5)
                        let c: Color = d.useBrand1 ? .brand1 : .brand2
                        context.fill(
                            Path(ellipseIn: CGRect(x: px - ps, y: py - ps, width: ps * 2, height: ps * 2)),
                            with: .color(c.opacity(a))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: fired) { fire in
            if fire {
                fireTime = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { fireTime = nil }
            }
        }
    }
}

struct ContentView: View {
    /// False while RostamSplash is on screen, true once it has left.
    let splashDone: Bool

    @State private var vpnState: VpnState = .disconnected
    @State private var showSidebar = false
    @State private var probeEnabled = true
    @State private var buttonPressScale: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0
    @State private var statusTextId: String = UUID().uuidString
    @State private var showBanner = false
    @State private var bannerDismissed = false
    @State private var shockwaveFired = false
    @State private var wasConnecting = false
    @State private var connectionGeneration: Int = 0
    @State private var activeManager: NETunnelProviderManager?

    private static func isOurTunnel(_ conn: NEVPNConnection) -> Bool {
        TunnelProfile.isOurs(conn.manager)
    }
    /// Which line of the connect narrative is showing. Advances on a schedule
    /// because there IS no progress signal.
    @State private var connectPhase: Int = 0
    /// Reactive, unlike UserDefaults.standard.bool(...) read inline.
    @AppStorage("isPaid", store: Store.entitlementDefaults) private var isPaidNow = false
    @State private var tunnelStarted = false
    @State private var animatedBackground: Bool
    @State private var trafficTxRate: String = ""
    @State private var trafficRxRate: String = ""
    @State private var trafficTotalTx: String = ""
    @State private var trafficTotalRx: String = ""
    @State private var lastTx: UInt64 = 0
    @State private var lastRx: UInt64 = 0
    @State private var baseTx: UInt64 = 0
    @State private var baseRx: UInt64 = 0
    @State private var trafficTimer: Timer?
    @AppStorage("theme", store: BrandRuntime.defaults)
    private var themeSetting: String = "auto"
    @AppStorage("language", store: BrandRuntime.defaults)
    private var languageSetting: String = "auto"
    /// "auto" | "redsocket" | "wgtcp". In the APP GROUP, not standard defaults: the
    /// extension reads it too, and it is the fallback when the choice did not make
    /// it into providerConfiguration.
    @State private var showPaywallSheet = false
    /// The post-purchase moment. An overlay, never a sheet — this view already
    /// carries two and SwiftUI honours only one.
    @State private var showPremiumMoment = false
    /// Starts false even on a fresh install, and is raised in the `splashDone`
    /// handler below.
    @State private var showWelcome = false
    @State private var toastMessage: String?
    /// Why the upgrade banner is not on screen, or nil when it is.
    private var premiumHiddenReason: String? {
        if RegionPolicy.isFreedomRegion {
            let why = ConfigPolicy.devRegionOverride.map { "dev override=\($0)" }
                ?? "detected region \(ConfigPolicy.country)"
            return "hidden: freedom region (\(why))"
        }
        if usage?.paid == true { return "hidden: server says paid" }
        if usage?.unlimited == true { return "hidden: server says unlimited" }
        if isPaidNow { return "hidden: local isPaid flag" }
        return nil
    }

    /// Paid users pick a region; so do freedom regions, which get the full product
    /// free by policy — and so does anyone the cashier's `region_select` opens it
    /// to. See RegionGate.
    private var mayPickRegion: Bool { RegionGate.allows(usage) }

    /// Is this user being SLOWED right now — as opposed to stopped?
    private var reducedSpeed: Bool {
        (usage?.overQuota ?? false)
            && ConfigPolicy.throttleEnabled
            && !ConfigPolicy.quotaHardStop
    }

    /// "auto", or a region id from the config ("fra", "lax", ...).
    @AppStorage("selectedRegion", store: BrandRuntime.defaults)
    private var selectedRegion: String = "auto"

    @State private var usage: CashierApi.UsageStatus?
    @State private var paidUntilTimer: Timer?
    /// tabs: when the tunnel came up, for the Elapsed card.
    @State private var connectedSince: Date?
    @State private var showGuardian = false
    /// The Guardian's local store and control-stream notes (tabs treatment).
    @ObservedObject private var guardian = GuardianCenter.shared

    init(splashDone: Bool) {
        self.splashDone = splashDone

        let store = UserDefaults(suiteName: suiteName)
        let probe = (store?.object(forKey: "probeEnabled") as? Bool) ?? false
        _probeEnabled = State(initialValue: probe)
        let animBg = UserDefaults(suiteName: suiteName)?.object(forKey: "animatedBackground") as? Bool ?? true
        _animatedBackground = State(initialValue: animBg)
    }

    private var isConnected: Bool {
        if case .connected = vpnState { return true }
        return false
    }

    private var isConnecting: Bool {
        if case .connecting = vpnState { return true }
        return false
    }

    private var isDisconnecting: Bool {
        if case .disconnecting = vpnState { return true }
        return false
    }

    private var showVideo: Bool { isConnected && animatedBackground }

    var body: some View {
        Group {
        if BrandRuntime.style == .tabs {
            tabsRoot
        } else {
        ZStack {
            Color.adaptiveBg
                .ignoresSafeArea()

            if animatedBackground {
                ConnectionGradientBackground(isConnected: isConnected)
                    .ignoresSafeArea()
                    .opacity(isConnected ? 0.28 : 0.0)
                    .animation(.easeInOut(duration: 2.0), value: isConnected)
            }

            if showVideo {
                VStack {
                    LinearGradient(
                        colors: [Color.adaptiveScrim.opacity(0.7), Color.adaptiveScrim.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)
                    Spacer()
                    LinearGradient(
                        colors: [Color.adaptiveScrim.opacity(0.0), Color.adaptiveScrim.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 2.0), value: isConnected)
            }

            ConnectShockwaveView(fired: shockwaveFired)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ConnectedBannerView(show: showBanner && !bannerDismissed, onDismiss: {
                    withAnimation { bannerDismissed = true }
                })
                .padding(.top, 8)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showBanner)

                    .padding(.horizontal, 20)

                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 20)

                            Spacer(minLength: 0)

                            if case .error(let msg) = vpnState {
                                VStack(spacing: 12) {
                                    Text("Connection Failed")
                                        .font(.headline)
                                        .foregroundColor(.dangerRed)

                                    Text(msg.isEmpty
                                         ? "Try again or check your network."
                                         : msg)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)

                                    Button(action: { toggleVPN() }) {
                                        Text("Try Again")
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 32)
                                            .padding(.vertical, 12)
                                            .background(Color.brand1)
                                            .cornerRadius(12)
                                    }
                                    .padding(.top, 4)
                                }
                                .transition(.opacity)
                            } else {
                                powerButton

                                Spacer()
                                    .frame(height: 16)

                                statusSection
                                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vpnStateKey)

                                Spacer()
                                    .frame(height: 8)

                                Text(helperText)
                                    .font(.subheadline)
                                    .foregroundColor(helperColor)

                                Spacer()
                                    .frame(height: 4)

                                trafficMeter
                            }
                            Spacer(minLength: 16)

                            VStack(spacing: 12) {
                                if mayPickRegion, !Store.shared.isPaid, !ConfigPolicy.paidOnly,
                                   let u = usage, !u.paid, !u.unlimited, u.freeQuotaMB > 0 {
                                    DataUsageBar(usedMB: u.usedMB, quotaMB: u.freeQuotaMB,
                                                 overQuota: u.overQuota,
                                                 reducedSpeed: reducedSpeed,
                                                 onUpgrade: { ReviewPrompt.recordPaywallShown(); showPaywallSheet = true })
                                        .padding(.horizontal, 20)
                                }

                                if !RegionPolicy.isFreedomRegion,
                                   !(usage?.paid ?? false), !(usage?.unlimited ?? false),
                                   !isPaidNow {
                                    PremiumBanner(reducedSpeed: reducedSpeed,
                                                  onUpgrade: { ReviewPrompt.recordPaywallShown(); showPaywallSheet = true })
                                        .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 4)
                        }

                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    }
                }

                VStack(spacing: 12) {
                    RegionCard(selectedRegion: $selectedRegion,
                               regions: ConfigPolicy.serverRegions(),
                               mayPick: mayPickRegion,
                               usage: usage,
                               reducedSpeed: reducedSpeed,
                               onUpgrade: { ReviewPrompt.recordPaywallShown(); showPaywallSheet = true },
                               onPicked: { _ in
                                   guard isConnected || isConnecting else { return }
                                   disconnect()

                                   DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { connect() }
                               })
                        .padding(.horizontal, 20)

                    taglineView

                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)

                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { notification in
            guard let conn = notification.object as? NEVPNConnection else { return }

            guard Self.isOurTunnel(conn) else { return }
            handleVPNStatusChange(conn.status, from: conn)

            if conn.status == .disconnected || conn.status == .invalid { showPaywallIfTunnelRefused() }
        }
        .onAppear {
            loadStatus {
                UsageReporter.shared.report()
                CashierApi.usage { u in
                    DispatchQueue.main.async { usage = u }
                }
                Task { await Store.shared.reconcileEntitlementAtLaunch() }
            }

            RemoteConfig.refresh()

            vpnLog("[region] \(RegionPolicy.describe())")
            vpnLog("[premium] \(premiumHiddenReason ?? "visible")")

            let group = UserDefaults(suiteName: suiteName)
            group?.set(CashierIdentity.current, forKey: "cid")
            group?.set(RegionPolicy.isFreedomRegion, forKey: "isFreedomRegion")

            group?.set(ConfigPolicy.freeKbps, forKey: "freeKbps")

            group?.set(ConfigPolicy.quotaHardStop, forKey: "quotaHardStop")

            PeerActivation.captureDeviceSignals()

            if !RegionPolicy.isFreedomRegion {
                Task { await Store.shared.load() }
            }
        }

        .onChange(of: splashDone) { done in
            guard done else { return }

            if WelcomeView.shouldShow, BrandRuntime.style != .tabs { showWelcome = true }
        }

        .task(id: vpnStateKey) {
            guard isConnecting else { connectPhase = 0; return }
            let start = Date()
            while !Task.isCancelled {
                let p = ConnectPhase.index(elapsed: Date().timeIntervalSince(start))
                if p != connectPhase {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        connectPhase = p
                    }

                    UIAccessibility.post(notification: .announcement,
                                         argument: ConnectPhase.spoken(p))
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Store.shared.reloadFromGroup()
            showPaywallIfTunnelRefused()
        }
        .onReceive(NotificationCenter.default.publisher(for: .entitlementDidChange)) { _ in

            if ConfigPolicy.paidOnly, !Store.shared.isPaid, isConnected || isConnecting {
                vpnLog("[paid_only] entitlement ended while connected — disconnecting")
                disconnect()
                showPaywallSheet = true
            }
            armPaidUntilTimer()

            CashierApi.usage { u in
                DispatchQueue.main.async {
                    usage = u
                    guard isPaidNow else { return }
                    shockwaveFired = true
                    toastMessage = String(localized: "premium_active_toast",
                                          defaultValue: "Premium is active. Full speed, every region.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        shockwaveFired = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .usageDidChange)) { _ in
            CashierApi.usage { u in
                DispatchQueue.main.async {
                    let crossed = (usage?.overQuota == false) && (u?.overQuota == true)
                        && !ConfigPolicy.paidOnly
                    usage = u

                    if crossed && ConfigPolicy.quotaHardStop {
                        toastMessage = String(localized: "Free data used up — upgrade for more")
                    } else if crossed && ConfigPolicy.throttleEnabled {
                        toastMessage = String(
                            format: NSLocalizedString(
                                "quota_reached_toast",
                                value: "Free full-speed data used. Your connection keeps working at up to %@.",
                                comment: "%@ is a speed, e.g. 2 Mbps"),
                            ConfigPolicy.freeSpeedLabel)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.configDidUpdateNotification)) { _ in
        }
        .onChange(of: vpnStateKey) { newState in

            if newState == "on" && wasConnecting {
                shockwaveFired = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    shockwaveFired = false
                }
            }
            wasConnecting = (newState == "connecting")
        }

        .fullScreenCover(isPresented: $showPaywallSheet) { PaywallView() }

        .onReceive(Store.shared.$justPurchased) { fired in
            guard fired else { return }
            Store.shared.justPurchased = false
            showPaywallSheet = false

            showPremiumMoment = BrandRuntime.style != .tabs
            switch vpnState {
            case .connected, .connecting: break
            default:
                vpnLog("[pay] premium activated — connecting")
                connect()
            }
        }
        .overlay {
            if showPremiumMoment {
                PremiumMomentView { showPremiumMoment = false }
                    .transition(.opacity)
            }
        }

        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                showWelcome = false
                connect()
            }
        }
        .toast(message: $toastMessage)
        .sheet(isPresented: $showSidebar) {
            SidebarMenuView(
                sessionRx: trafficTotalRx,
                sessionTx: trafficTotalTx,
                onRate: {
                    showSidebar = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        ReviewPrompt.askNow()
                    }
                },
                probeEnabled: $probeEnabled,
                animatedBackground: $animatedBackground,
                themeSetting: $themeSetting,
                languageSetting: $languageSetting,
                onProbeToggle: { enabled in
                    probeEnabled = enabled
                    UserDefaults(suiteName: suiteName)?.set(enabled, forKey: "probeEnabled")
                },
                onAnimatedBgToggle: { enabled in
                    animatedBackground = enabled
                    UserDefaults(suiteName: suiteName)?.set(enabled, forKey: "animatedBackground")
                },
                onRegionPicked: { _ in

                    if isConnected || isConnecting {
                        disconnect()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { connect() }
                    } else {
                        connect()
                    }
                },
            )
        }
        .onChange(of: isConnected) { connected in

            armPaidUntilTimer()
            connectedSince = connected ? (connectedSince ?? Date()) : nil

            GuardianCenter.shared.resetSession()
            if connected {
                bannerDismissed = false
                withAnimation { showBanner = true }

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { showBanner = false }
                }
                startTrafficMonitor()

                UsageReporter.shared.start()

                ReviewPrompt.recordSuccessfulConnection(
                    since: activeManager?.connection.connectedDate)
            } else {
                withAnimation { showBanner = false }
                stopTrafficMonitor()

                UsageReporter.shared.stop()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard case .disconnected = vpnState else { return }
                    ReviewPrompt.maybeAsk()
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { showSidebar = true }) {
                VStack(spacing: 4.5) {
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 22, height: 2.5)
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 22, height: 2.5)
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 16, height: 2.5)
                        .frame(width: 22, alignment: .leading)
                }

                .foregroundColor(.brandGraphicOnBg)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Menu")

            Spacer()

            Text(BrandRuntime.displayName)
                .font(.title3)
                .fontWeight(.bold)

                .foregroundColor(.brandOnBg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var statusSection: some View {
        Text(statusTitle)
            .font(.system(.largeTitle).weight(.bold))

            .foregroundStyle(statusFill)
            .accessibilityAddTraits(.isHeader)
            .id(statusTextId)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .multilineTextAlignment(.center)
    }

    private var statusTitle: LocalizedStringKey {
        switch vpnState {
        case .connected: return "VPN On"
        case .connecting: return connectPhase >= 2 ? "Still working" : "Connecting"
        case .disconnecting: return "Disconnecting"
        case .error: return "Connection Failed"
        case .disconnected: return "VPN Off"
        }
    }

    /// The largest word on the home screen, and it sits on the CONNECTED WASH at
    /// exactly the moment it says "VPN On". Raw `primary` there, and raw
    /// `secondary` for CONNECTING on the resting page, can both fall under 2:1 on
    /// a palette, so each goes through its lifted role.
    private var statusColor: Color {
        if BrandRuntime.style == .rings {
            if case .error = vpnState { return .dangerRed }

            if case .disconnected = vpnState { return Deep.ringsStatusRest }
            return Deep.ringsPageInk
        }
        switch vpnState {
        case .connected: return .brandOnBg
        case .connecting: return .accentOnBg
        case .error: return .dangerRed

        case .disconnected: return Color.mix(.primary, .black, 0.25)
        default: return .secondary
        }
    }

    /// The line under the status word. Same reasoning as `statusColor`.
    private var helperColor: Color {
        BrandRuntime.style == .rings ? Deep.ringsPageMuted : .secondary
    }

    /// `statusColor` for every state and every classic brand; the two-stop gradient
    /// for a `rings` brand that is CONNECTED.
    private var statusFill: AnyShapeStyle {
        guard BrandRuntime.style == .rings, isConnected else {
            return AnyShapeStyle(statusColor)
        }
        return AnyShapeStyle(LinearGradient(
            colors: [.statusGradientTop, .statusGradientBottom],
            startPoint: .top, endPoint: .bottom))
    }

    private var helperText: LocalizedStringKey {
        switch vpnState {
        case .connected: return "Tap to disconnect"
        case .disconnecting: return "Stopping…"
        case .connecting: return ConnectPhase.helper(connectPhase)
        case .error: return ""
        default: return "Tap to connect"
        }
    }

    private func startTrafficMonitor() {
        stopTrafficMonitor()
        baseTx = 0; baseRx = 0
        lastTx = 0; lastRx = 0
        trafficTxRate = ""; trafficRxRate = ""
        trafficTotalTx = ""; trafficTotalRx = ""

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            pollTrafficStats()
        }
        trafficTimer = timer
    }

    private func stopTrafficMonitor() {
        trafficTimer?.invalidate()
        trafficTimer = nil
        trafficTxRate = ""; trafficRxRate = ""
        trafficTotalTx = ""; trafficTotalRx = ""
    }

    private func pollTrafficStats() {
        guard let manager = activeManager,
              let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected else { return }

        let msg = "get-stats".data(using: .utf8)!
        do {
            try session.sendProviderMessage(msg) { [self] response in
                guard let data = response,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let txNum = json["tx"] as? NSNumber,
                      let rxNum = json["rx"] as? NSNumber else { return }
                let tx = txNum.uint64Value
                let rx = rxNum.uint64Value

                if baseTx == 0 && baseRx == 0 && (tx > 0 || rx > 0) {
                    baseTx = tx; baseRx = rx
                    lastTx = tx; lastRx = rx
                    return
                }

                let txDelta = tx >= lastTx ? tx - lastTx : 0
                let rxDelta = rx >= lastRx ? rx - lastRx : 0
                lastTx = tx; lastRx = rx

                DispatchQueue.main.async {
                    self.trafficTxRate = self.formatRate(txDelta)
                    self.trafficRxRate = self.formatRate(rxDelta)
                    self.trafficTotalTx = self.formatBytes(tx >= self.baseTx ? tx - self.baseTx : tx)
                    self.trafficTotalRx = self.formatBytes(rx >= self.baseRx ? rx - self.baseRx : rx)
                }
            }
        } catch {
        }
    }

    private func formatRate(_ bytesPerSec: UInt64) -> String {
        switch bytesPerSec {
        case 0..<1024: return "\(bytesPerSec) B/s"
        case 1024..<(1024 * 1024): return "\(bytesPerSec / 1024) KB/s"
        default: return String(format: "%.1f MB/s", Double(bytesPerSec) / (1024.0 * 1024.0))
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        switch bytes {
        case 0..<1024: return "\(bytes) B"
        case 1024..<(1024 * 1024): return "\(bytes / 1024) KB"
        case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        default: return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }

    private var powerButton: some View {
        Group {
            if BrandRuntime.style == .rings {
                RingsDial(state: vpnState, action: onDialTap)
            } else {
                ConnectDial(state: vpnState, connectPhase: connectPhase, action: onDialTap)
            }
        }
        .disabled(isDisconnecting)
        .scaleEffect(buttonPressScale)
        .offset(x: shakeOffset, y: 0)
        .accessibilityLabel(isConnected ? "Disconnect VPN" : "Connect VPN")
        .accessibilityHint(isConnected ? "Double tap to disconnect" : "Double tap to connect")
    }

    /// Lifted out of the `ConnectDial` closure so BOTH dials run the identical
    /// press polish and the identical toggle. Two copies of this would be two
    /// connect paths, which is the one thing a second dial must not introduce.
    private func onDialTap() {
        withAnimation(.easeOut(duration: 0.1)) { buttonPressScale = 0.94 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.15)) { buttonPressScale = 1.0 }
        }
        toggleVPN()
    }

    private func celebratoryPulse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            buttonPressScale = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                buttonPressScale = 1.0
            }
        }
    }

    private var vpnStateKey: String {
        switch vpnState {
        case .disconnected: return "off"
        case .connecting: return "ing"
        case .connected: return "on"
        case .disconnecting: return "ding"
        case .error: return "err"
        }
    }

    private func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func mediumHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func errorHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func shakeButton() {
        let sequence: [CGFloat] = [0, -10, 10, -8, 8, -4, 4, 0]
        for (index, offset) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                withAnimation(.easeInOut(duration: 0.06)) {
                    shakeOffset = offset
                }
            }
        }
    }

    /// Reserves its height whether or not it has figures to show.
    private var trafficMeter: some View {
        let show = isConnected && !trafficRxRate.isEmpty
        return Group {
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text(trafficRxRate)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.brandOnBg)
                    Text("\u{2193} \(trafficTotalRx)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(spacing: 2) {
                    Text(trafficTxRate)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.brandOnBg)
                    Text("\u{2191} \(trafficTotalTx)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .opacity(show ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: show)
        }
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(!show)
        .accessibilityLabel(Text("Traffic"))
        .accessibilityValue(Text("Download \(trafficRxRate), \(trafficTotalRx) total. "
                                 + "Upload \(trafficTxRate), \(trafficTotalTx) total."))
    }

    /// "v6.0.0", plus " · cfg 12" when an OTA config is in force.
    private var versionFooter: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let cfg = ConfigPolicy.configVersion
        return cfg.isEmpty ? "v\(v)" : "v\(v) · cfg \(cfg)"
    }

    private var taglineView: some View {
        VStack(spacing: 2) {
            if !BrandRuntime.tagline.isEmpty {
                Text(LocalizedStringKey(BrandRuntime.tagline))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !BrandRuntime.provenance.isEmpty {
                Text(LocalizedStringKey(BrandRuntime.provenance))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(versionFooter)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    private func toggleVPN() {
        mediumHaptic()
        if isConnected {
            disconnect()
        } else if isConnecting {
            vpnLog("user cancelled connect")
            disconnect()
        } else {
            connect()
        }
    }

    /// Always `auto`. The transport is chosen by `transport_order` in the OTA
    /// config, per region, and a device-local override could only ever disagree
    /// with policy.
    private static let transport = "auto"

    /// Allowance gone, and this brand does not keep serving afterwards.
    private var quotaHardStopped: Bool {
        guard ConfigPolicy.quotaHardStop else { return false }
        if Store.shared.isPaid || RegionPolicy.isFreedomRegion { return false }
        guard let u = usage else { return false }
        return u.overQuota && !u.paid
    }

    private var tabsPhase: IPRingPhase {
        #if DEBUG

        switch BrandRuntime.defaults?.string(forKey: "debugPhase") {
        case "connecting": return .connecting
        case "on": return .on
        default: break
        }
        #endif
        if isConnected { return .on }
        if isConnecting || isDisconnecting { return .connecting }
        return .off
    }

    private var tabsIsPro: Bool { isPaidNow || Store.shared.isPaid || usage?.paid == true }

    private var tabsRouteLabel: String {
        if selectedRegion == "auto" { return String(localized: "Auto · Fastest") }
        return ConfigPolicy.serverRegions().first { $0.0 == selectedRegion }?.1 ?? selectedRegion.uppercased()
    }

    private var tabsRoot: some View {
        IPTabsRoot(
            connect: IPConnectTab(
                phase: tabsPhase,
                errorText: { if case .error = vpnState { return String(localized: "Couldn't connect. Tap to try again.") }; return nil }(),
                isPro: tabsIsPro,
                connectedSince: connectedSince,
                downRate: trafficRxRate,
                upRate: trafficTxRate,
                routeLabel: tabsRouteLabel,
                blockedToday: guardian.blockedToday,
                protectionAcknowledged: tabsPhase == .on && guardian.acknowledged,
                notice: guardian.notice,
                onDismissNotice: { guardian.notice = nil },
                onToggle: toggleVPN,
                onGoPro: { ReviewPrompt.recordPaywallShown(); showPaywallSheet = true },
                onStatusTap: { showGuardian = true })
                .sheet(isPresented: $showGuardian) { IPGuardianSheet(source: GuardianSources.current) }
                #if DEBUG

                .task {
                    if GuardianSources.isFixture {
                        await guardian.poll(GuardianSources.current)
                        Task {
                            try? await Task.sleep(nanoseconds: 6_000_000_000)
                            await guardian.poll(GuardianSources.current)
                        }
                    }
                    guard let tap = BrandRuntime.defaults?.string(forKey: "debugTap") else { return }
                    BrandRuntime.defaults?.removeObject(forKey: "debugTap")
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if tap == "connect" { toggleVPN() }
                    if tap == "guardian" { showGuardian = true }
                }
                #endif

                .task(id: isConnected) {
                    guard isConnected else { return }
                    await guardian.run(source: GuardianSources.current, stillConnected: { isConnected })
                },
            account: IPAccountTab(
                isPro: tabsIsPro,
                onGoPro: { ReviewPrompt.recordPaywallShown(); showPaywallSheet = true },
                probeEnabled: $probeEnabled,
                onProbeToggle: { enabled in
                    probeEnabled = enabled
                    UserDefaults(suiteName: suiteName)?.set(enabled, forKey: "probeEnabled")
                },
                themeSetting: $themeSetting))
    }

    /// The extension refused (or ended) a session the app did not start, e.g.
    private func showPaywallIfTunnelRefused() {
        guard let d = BrandRuntime.defaults,
              let r = d.dictionary(forKey: GuardianMessage.lastRefusalKey) else { return }
        d.removeObject(forKey: GuardianMessage.lastRefusalKey)
        let kind = r["kind"] as? String ?? ""
        let at = r["at"] as? Double ?? 0
        vpnLog("[tunnel] last refusal: \(kind) \(r["reason"] as? String ?? "")")
        guard kind == "entitlement" || kind == "allowance",
              Date().timeIntervalSince1970 - at < 3600, !showPaywallSheet else { return }
        Store.shared.reloadFromGroup()
        ReviewPrompt.recordPaywallShown()
        showPaywallSheet = true
    }

    /// `paid_only`: nothing is free, so connecting needs a positive answer.
    private var paidOnlyBlocked: Bool {
        guard ConfigPolicy.paidOnly else { return false }

        let entitled = Store.shared.isPaid || isPaidNow || usage?.paid == true
        if !entitled { return true }

        if usage?.paid != true, Store.shared.lapsedBeyondGrace {
            vpnLog("[paid_only] paid_until is more than 3 days past and StoreKit holds nothing")
            return true
        }
        return false
    }

    /// Fires at the cashier's `paid_until` while a `paid_only` tunnel is up and
    /// asks again. The reconcile's write rule decides.
    private func armPaidUntilTimer() {
        paidUntilTimer?.invalidate()
        paidUntilTimer = nil
        guard ConfigPolicy.paidOnly, isConnected || isConnecting,
              let until = Store.shared.paidUntil else { return }
        let fire = max(until, Date().addingTimeInterval(1))
        let t = Timer(fire: fire, interval: 0, repeats: false) { _ in
            Task { @MainActor in
                vpnLog("[paid_only] paid_until reached; re-checking entitlement")
                await Store.shared.reconcileEntitlementAtLaunch()
                if !Store.shared.isPaid { return }
                if let next = Store.shared.paidUntil, next > Date() {
                    armPaidUntilTimer()
                } else {
                    vpnLog("[paid_only] lapse not confirmed (cashier silent); retry in 5 min")
                    paidUntilTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
                        Task { @MainActor in armPaidUntilTimer() }
                    }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        paidUntilTimer = t
    }

    private func connect() {
        if paidOnlyBlocked {
            vpnLog("[paid_only] not entitled — refusing connect, opening paywall")
            ReviewPrompt.recordPaywallShown()
            showPaywallSheet = true
            return
        }

        if ConfigPolicy.paidOnly, usage?.paid != true, Store.shared.staleUnanswered {
            vpnLog("[paid_only] stored paid_until is stale and unconfirmed — asking the cashier")
            Task {
                await Store.shared.reconcileEntitlementAtLaunch()
                if paidOnlyBlocked || Store.shared.staleUnanswered {
                    vpnLog("[paid_only] cashier \(Store.shared.cashierUnreachable ? "unreachable" : "says not paid") — paywall")
                    ReviewPrompt.recordPaywallShown()
                    showPaywallSheet = true
                } else {
                    connect()
                }
            }
            return
        }

        if ConfigPolicy.paidOnly, usage?.paid == true { Store.shared.adoptServerPaid() }

        if quotaHardStopped {
            vpnLog("[quota] hard stop — refusing connect, opening paywall")
            ReviewPrompt.recordPaywallShown()
            showPaywallSheet = true
            return
        }

        ensureProfileInstalled { installed in
            guard installed else { return }
            self.beginConnect()
        }
    }

    /// Put the VPN profile on the device if it is not there yet, and report whether
    /// we may proceed.
    private func ensureProfileInstalled(_ done: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                self.vpnLog("profile preflight read failed: \(error.localizedDescription)")
                done(true)
                return
            }
            if (managers ?? []).contains(where: { TunnelProfile.isOurs($0) }) {
                done(true)
                return
            }
            self.vpnLog("installing VPN profile")
            let manager = self.newConfiguredManager(
                transport: Self.transport, region: "")
            manager.saveToPreferences { error in
                if let error = error {
                    self.vpnLog("profile install failed/declined: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        errorHaptic()
                        shakeButton()
                        self.statusTextId = UUID().uuidString
                        self.vpnState = .error(error.localizedDescription)
                        ReviewPrompt.recordConnectionFailure()
                    }
                    done(false)
                    return
                }
                done(true)
            }
        }
    }

    /// A fully configured, unsaved profile.
    private func newConfiguredManager(transport: String, region: String) -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = TunnelProfile.provider
        proto.serverAddress = BrandRuntime.displayName
        proto.providerConfiguration = [
            "transport": transport as NSObject,
            "region": region as NSObject,
            "probeEnabled": (probeEnabled ? "true" : "false") as NSObject,
            "protocol": transport as NSObject,
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = BrandRuntime.displayName
        manager.isEnabled = true
        return manager
    }

    private func beginConnect() {
        connectionGeneration += 1
        tunnelStarted = false
        vpnState = .connecting

        let transport = Self.transport
        let region = ""

        vpnLog("connect() transport=\(transport)")

        let mayPick = RegionGate.allows(usage)
        let entitled = (mayPick && selectedRegion != "auto") ? selectedRegion : ""
        UserDefaults(suiteName: suiteName)?.set(entitled, forKey: "entitledRegion")
        vpnLog("region: picked=\(selectedRegion) entitled=\(entitled.isEmpty ? "auto" : entitled)")

        let wgtcpAllowed = ConfigPolicy.transportOrder.contains("wgtcp")
        UserDefaults(suiteName: suiteName)?.set(wgtcpAllowed, forKey: "wgtcpAllowed")
        if wgtcpAllowed {
            DispatchQueue.global(qos: .userInitiated).async {
                if let cfg = WgtcpProvisioner.config() {
                    UserDefaults(suiteName: suiteName)?.set(cfg, forKey: "wgtcpConfig")
                    self.vpnLog("wgtcp provisioned")
                } else {
                    UserDefaults(suiteName: suiteName)?.removeObject(forKey: "wgtcpConfig")
                    self.vpnLog("wgtcp not provisioned; RedSocket only")
                }
            }
        } else {
            UserDefaults(suiteName: suiteName)?.removeObject(forKey: "wgtcpConfig")
            vpnLog("wgtcp not in transport_order; stale profile cleared")
        }

        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                self.vpnLog("loadAll error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorHaptic()
                    self.shakeButton()
                    self.statusTextId = UUID().uuidString
                    self.vpnState = .error(error.localizedDescription)
                    ReviewPrompt.recordConnectionFailure()
                }
                return
            }

            let existing = (managers ?? []).first(where: { TunnelProfile.isOurs($0) })

            if let conn = existing?.connection,
               conn.status == .disconnecting || conn.status == .connected {
                self.vpnLog("Waiting for previous tunnel to stop...")
                if conn.status == .connected {
                    conn.stopVPNTunnel()
                }
                DispatchQueue.global().async {
                    for _ in 0..<16 {
                        Thread.sleep(forTimeInterval: 0.5)
                        if conn.status == .disconnected || conn.status == .invalid { break }
                    }
                    self.vpnLog("Previous tunnel state: \(conn.status.rawValue)")
                    DispatchQueue.main.async {
                        if let mgr = existing {
                            self.vpnLog("Reusing existing VPN profile")
                            self.updateAndStart(mgr, transport: transport, region: region)
                        } else {
                            self.vpnLog("Creating new VPN config")
                            self.createAndStartVPN(transport: transport, region: region)
                        }
                    }
                }
                return
            }

            if let mgr = existing {
                self.vpnLog("Reusing existing VPN profile")
                self.updateAndStart(mgr, transport: transport, region: region)
            } else {
                self.vpnLog("Creating new VPN config")
                self.createAndStartVPN(transport: transport, region: region)
            }
        }
    }

    private func updateAndStart(_ manager: NETunnelProviderManager, transport: String, region: String) {
        manager.isEnabled = true
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto.providerConfiguration = [
                "transport": transport as NSObject,
                "region": region as NSObject,
                "probeEnabled": (probeEnabled ? "true" : "false") as NSObject,
                "protocol": transport as NSObject,
            ]
        }
        manager.saveToPreferences { error in
            if let error = error {
                self.vpnLog("Re-save error: \(error.localizedDescription)")
            }
            manager.loadFromPreferences { _ in
                self.startTunnel(manager)
            }
        }
    }

    private func createAndStartVPN(transport: String, region: String) {
        let manager = newConfiguredManager(transport: transport, region: region)

        manager.saveToPreferences { error in
            if let error = error {
                vpnLog("Save error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorHaptic()
                    shakeButton()
                    statusTextId = UUID().uuidString
                    vpnState = .error(error.localizedDescription)
                    ReviewPrompt.recordConnectionFailure()
                }
                return
            }
            manager.loadFromPreferences { error in
                if let error = error {
                    vpnLog("Load error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        errorHaptic()
                        shakeButton()
                        statusTextId = UUID().uuidString
                        vpnState = .error(error.localizedDescription)
                        ReviewPrompt.recordConnectionFailure()
                    }
                    return
                }
                self.startTunnel(manager)
            }
        }
    }

    private func startTunnel(_ manager: NETunnelProviderManager) {
        DispatchQueue.main.async {
            self.vpnLog("Starting tunnel...")

            self.vpnState = .connecting
            do {
                try (manager.connection as? NETunnelProviderSession)?.startTunnel()
                self.vpnLog("startTunnel() OK")
                self.activeManager = manager
                self.tunnelStarted = true
                let gen = self.connectionGeneration

                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    guard self.connectionGeneration == gen else { return }
                    if case .connecting = self.vpnState, self.tunnelStarted {
                        self.vpnLog("Connect timeout")
                        self.errorHaptic()
                        self.shakeButton()
                        self.statusTextId = UUID().uuidString
                        self.vpnState = .error("Connection timeout")
                        ReviewPrompt.recordConnectionFailure()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            guard self.connectionGeneration == gen else { return }
                            if case .error = self.vpnState {
                                self.statusTextId = UUID().uuidString
                                self.vpnState = .disconnected
                            }
                        }
                    }
                }
            } catch {
                self.vpnLog("Start error: \(error.localizedDescription)")
                self.errorHaptic()
                self.shakeButton()
                self.statusTextId = UUID().uuidString
                self.vpnState = .error(error.localizedDescription)
                ReviewPrompt.recordConnectionFailure()
            }
        }
    }

    private func isActiveConnection(_ conn: NEVPNConnection?) -> Bool {
        guard let conn, let active = activeManager?.connection else { return true }
        return conn === active
    }

    private func handleVPNStatusChange(_ status: NEVPNStatus, from conn: NEVPNConnection? = nil) {
        if status == .connected { CashierApi.tunnelProfileExists = true }
        CashierApi.tunnelConnected = (status == .connected)

        switch status {
        case .connected:

            guard tunnelStarted else { return }
            guard isActiveConnection(conn) else { return }
            guard case .connecting = vpnState else { return }
            vpnLog("VPN CONNECTED!")
            successHaptic()
            celebratoryPulse()
            statusTextId = UUID().uuidString
            vpnState = .connected

            Task { await Store.shared.reconcileEntitlementAtLaunch() }
            CashierApi.usage { u in
                DispatchQueue.main.async { usage = u }
            }

        case .disconnected:
            if case .disconnecting = vpnState {
                vpnLog("VPN fully disconnected")
                vpnState = .disconnected
            } else if tunnelStarted, case .connecting = vpnState, isActiveConnection(conn) {
                vpnLog("VPN failed to connect")
                errorHaptic()
                shakeButton()
                statusTextId = UUID().uuidString
                vpnState = .error("Connection failed")
                ReviewPrompt.recordConnectionFailure()
                let gen = connectionGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard self.connectionGeneration == gen else { return }
                    if case .error = self.vpnState {
                        self.statusTextId = UUID().uuidString
                        self.vpnState = .disconnected
                    }
                }
            } else if case .connected = vpnState, isActiveConnection(conn) {
                vpnLog("VPN disconnected unexpectedly")

                ReviewPrompt.recordConnectionFailure()
                lightHaptic()
                statusTextId = UUID().uuidString
                vpnState = .disconnected
            }

        case .connecting:
            break

        case .disconnecting:
            if case .disconnecting = vpnState { break }
            vpnState = .disconnecting

        default:
            break
        }
    }

    private func disconnect() {
        vpnLog("disconnect()")
        connectionGeneration += 1
        let gen = connectionGeneration
        tunnelStarted = false
        vpnState = .disconnecting

        if let mgr = activeManager {
            mgr.connection.stopVPNTunnel()
            vpnLog("stopVPNTunnel() called on cached manager")
            activeManager = nil
        } else {
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                guard let conn = (managers ?? [])
                    .first(where: { TunnelProfile.isOurs($0) })?.connection else {
                    DispatchQueue.main.async { self.vpnState = .disconnected }
                    return
                }
                conn.stopVPNTunnel()
                self.vpnLog("stopVPNTunnel() called via loadAll")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            guard self.connectionGeneration == gen else { return }
            if case .disconnecting = self.vpnState {
                self.vpnLog("Disconnect timeout — forcing state")
                self.vpnState = .disconnected
            }
        }
    }

    /// Reads the saved profile into `CashierApi`, then runs `then` on the main
    /// queue: cashier calls made before this answers are deferred.
    private func loadStatus(_ then: @escaping () -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in

            let ours = (managers ?? []).first(where: { TunnelProfile.isOurs($0) })

            CashierApi.tunnelConnected = (ours?.connection.status == .connected)
            CashierApi.tunnelProfileExists = (ours != nil)
            guard let mgr = ours else {
                DispatchQueue.main.async(execute: then)
                return
            }
            let conn = mgr.connection
            DispatchQueue.main.async {
                switch conn.status {
                case .connected:
                    vpnState = .connected
                    tunnelStarted = true
                    activeManager = mgr
                case .connecting:
                    vpnState = .connecting
                    tunnelStarted = true
                    activeManager = mgr
                case .disconnecting: vpnState = .disconnecting
                default: vpnState = .disconnected
                }
                then()
            }
        }
    }

    /// Private in the unified log: region inputs and connect history stay out
    /// of sysdiagnose.
    private func vpnLog(_ msg: String) {
        os_log("%{private}@", msg)
    }
}

struct SidebarMenuView: View {
    @State private var showPaywall = false

    /// Premium has to be VISIBLE, not merely in effect.
    @AppStorage("isPaid", store: Store.entitlementDefaults) private var isPaidNow = false
    var sessionRx: String = ""
    var sessionTx: String = ""

    static func lifetimeBytes() -> Int64 {
        Int64(BrandRuntime.defaults?
            .string(forKey: "lifetimeBytes") ?? "0") ?? 0
    }

    /// Same store the app and the extension read.
    @AppStorage("selectedRegion", store: BrandRuntime.defaults)
    private var selectedRegion: String = "auto"
    var onRate: () -> Void = {}

    @Binding var probeEnabled: Bool
    @Binding var animatedBackground: Bool
    @Binding var themeSetting: String
    @Binding var languageSetting: String

    /// Mirrors `SettingsSheet.kt`'s list exactly -- same codes, same order, and
    /// each name written in its own script. "auto" is the only translated entry
    /// because it is the only one that is a WORD rather than a name.
    static let languages: [(String, String)] = [
        ("auto", ""),
        ("en", "English"), ("zh", "\u{4E2D}\u{6587}"), ("fa", "\u{0641}\u{0627}\u{0631}\u{0633}\u{06CC}"),
        ("ar", "\u{0627}\u{0644}\u{0639}\u{0631}\u{0628}\u{064A}\u{0629}"), ("ru", "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439}"),
    ]

    @ViewBuilder
    static func languageText(_ code: String) -> some View {
        let label = languages.first { $0.0 == code }?.1 ?? code
        if label.isEmpty { Text("language_auto") } else { Text(label) }
    }
    let onProbeToggle: (Bool) -> Void
    let onAnimatedBgToggle: (Bool) -> Void
    /// Region is read when the tunnel STARTS, so picking one mid-session did
    /// nothing until the user reconnected by hand -- they chose Frankfurt and
    /// stayed on whatever they had. The picker now applies it.
    let onRegionPicked: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [.sidebarTop, .sidebarBot],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                if isPaidNow || !RegionPolicy.isFreedomRegion {
                                    Button(action: { showPaywall = true }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: isPaidNow ? "checkmark.seal.fill" : "crown.fill")
                                            .font(.body)
                                            .frame(width: 24)
                                            .foregroundColor(isPaidNow ? BrandTheme.warning : nil)
                                        Text(isPaidNow ? "premium_active_menu" : "Premium")
                                            .font(.body)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .opacity(0.5)
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 24)
                                    .contentShape(Rectangle())
                                    }
                                }

                                menuLink(icon: "qrcode.viewfinder", label: "Scan config code") {
                                    QrConfigView()
                                }

                                if !ConfigPolicy.paidOnly {
                                    menuLink(icon: "list.bullet", label: "Usage stats") {
                                        UsageStatsView(sessionRx: sessionRx,
                                                       sessionTx: sessionTx,
                                                       lifetimeBytes: Self.lifetimeBytes())
                                    }
                                }

                                menuAction(icon: "star", label: "Rate \(BrandRuntime.displayName)") {
                                    onRate()
                                }
                                menuLink(icon: "info.circle", label: "About \(BrandRuntime.displayName)") {
                                    AboutView()
                                }
                                menuLink(icon: "hand.raised", label: "Privacy Policy") {
                                    PrivacyPolicyView()
                                }

                                .padding(.bottom, 4)

                                Divider()
                                    .background(Color.white.opacity(0.2))
                                    .padding(.vertical, 12)

                                HStack(spacing: 14) {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.body)
                                        .frame(width: 24)
                                    Toggle(isOn: Binding(
                                        get: { probeEnabled },
                                        set: { onProbeToggle($0) }
                                    )) {
                                        Text("Help Improve")
                                            .font(.body)
                                    }
                                    .tint(.accentOnSheet)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 24)

                                Divider()
                                    .background(Color.white.opacity(0.2))
                                    .padding(.vertical, 12)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "moon.fill")
                                            .font(.body)
                                            .frame(width: 24)
                                        Text("Appearance")
                                            .font(.body)
                                    }
                                    .foregroundColor(.white.opacity(0.9))

                                    Picker("", selection: $themeSetting) {
                                        Text("Auto").tag("auto")
                                        Text("Light").tag("light")
                                        Text("Dark").tag("dark")
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 24)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "globe")
                                            .font(.body)
                                            .frame(width: 24)
                                        Text("Language")
                                            .font(.body)
                                        Spacer()
                                        Menu {
                                            ForEach(Self.languages, id: \.0) { code, _ in
                                                Button {
                                                    languageSetting = code
                                                } label: {
                                                    HStack {
                                                        Self.languageText(code)
                                                        if languageSetting == code {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Self.languageText(languageSetting)
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 24)
                            }
                            .padding(.top, 20)

                            Spacer()

                            HStack {
                                Spacer()
                                Image("BrandMascot")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .opacity(0.6)
                                Spacer()
                            }
                            .padding(.bottom, 30)

                            HStack {
                                Spacer()
                                VStack(spacing: 2) {
                                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.6.0")"
                                         + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.4))

                                    Text(RegionPolicy.isFreedomRegion
                                         ? "Region \(RegionPolicy.country.isEmpty ? "?" : RegionPolicy.country) · free — no Premium"
                                         : "Region \(RegionPolicy.country.isEmpty ? "?" : RegionPolicy.country)")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.35))
                                }
                                Spacer()
                            }
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height,
                               alignment: .leading)
                    }
                }
            }
            .navigationTitle(BrandRuntime.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)

            .sheet(isPresented: $showPaywall) { PaywallView() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    /// No `usage` in this view, so this reads the last answer RegionGate
    /// remembered. See RegionGate.
    private var mayPickRegion: Bool { RegionGate.allows(nil) }

    /// `label` is a LocalizedStringKey, NOT a String, and the difference is the
    /// whole feature. A `String` parameter swallows the literal before `Text` ever
    /// sees it.
    private func menuAction(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                Text(label)
                    .font(.body)
                Spacer()
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
    }

    private func menuLink<Destination: View>(icon: String, label: LocalizedStringKey, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                Text(label)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .opacity(0.5)
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Image("BrandMascot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                    Spacer()
                }
                .padding(.top, 16)

                HStack {
                    Spacer()

                    Text("Private, secure internet for everyone")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.brandOnBg)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.top, 24)

                Text("\(BrandRuntime.displayName) provides fast, secure, and private internet access using multiple advanced encryption protocols and a global network of high-performance servers.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 24)

                Text("\(BrandRuntime.displayName) is developed and managed by a team of US-based network and cybersecurity experts. The team has been working for more than a decade to increase digital security and protect user privacy online.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 16)

                Divider()
                    .padding(.vertical, 24)

                Text("Open source")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.brandOnBg)

                Text("\(BrandRuntime.displayName) is built on work shared freely by others. Their licences are reproduced in full inside the app bundle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)

                ForEach(Self.credits, id: \.0) { name, license, what in
                    aboutCredit(name: name, license: license, what: what)
                }

                Divider()
                    .padding(.vertical, 24)

                if !BrandRuntime.supportEmail.isEmpty || !BrandRuntime.siteURL.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            if !BrandRuntime.supportEmail.isEmpty {
                                Text(BrandRuntime.supportEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if !BrandRuntime.siteURL.isEmpty {
                                Text(BrandRuntime.siteHost)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.adaptiveBg)
        .navigationTitle("About \(BrandRuntime.displayName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Every third-party package the app links, with its licence. Read off
    /// LocalPackages/ rather than remembered, so it cannot drift from what actually
    /// ships.
    static let credits: [(String, String, String)] = [
        ("hev-socks5-tunnel", "Apache-2.0", "Turns the tunnel interface into a SOCKS5 client"),
        ("libyaml",           "MIT",        "Reads the SOCKS5 tunnel's configuration"),
    ]

    private func aboutCredit(name: String, license: String, what: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.body).fontWeight(.semibold).foregroundColor(.primary)
                Spacer()
                Text(license).font(.caption2).foregroundColor(.secondary)
            }
            Text(what).font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }

}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Effective date: February 5, 2026")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                policyText("\(BrandRuntime.legalOperator) (\u{201C}us\u{201D}, \u{201C}we\u{201D}, or \u{201C}our\u{201D}) operates the \(BrandRuntime.displayName) mobile application (hereinafter referred to as the \u{201C}Service\u{201D}).\n\nThis page informs you of our policies regarding the collection, use and disclosure of unidentifiable personal data when you use our Service and the choices you have associated with that data.\n\nWe use this data to provide and improve the Service. By using the Service, you agree to the collection and use of information in accordance with this policy. Unless otherwise defined in this Privacy Policy, the terms used in this Privacy Policy have the same meanings as in our Terms and Conditions.")

                sectionHeader("Definitions")

                subSectionHeader("Service")
                policyText("Service is the \(BrandRuntime.displayName) mobile application operated by \(BrandRuntime.legalOperator).")

                subSectionHeader("Unidentifiable Personal Data")
                policyText("Unidentifiable Personal Data means data about a living individual who cannot be identified from those data (or from those and other information either in our possession or likely to come into our possession).")

                subSectionHeader("Usage Data")
                policyText("Usage Data is data collected automatically either generated by the use of the Service or from the Service infrastructure itself (for example, the duration of a page visit).")

                sectionHeader("Information Collection and Use")
                policyText("We collect below information for various purposes to provide and improve our Service to you.")

                subSectionHeader("Types of Data Collected")
                policyText("When you access the Service with a mobile device, we may collect certain information automatically, including, but not limited to, the type of mobile device you use, your mobile device unique ID, your mobile operating system, unique device identifiers, your mobile carrier, country, and other diagnostic data (\u{201C}Usage Data\u{201D}).")

                sectionHeader("Use of Data")
                policyText("\(BrandRuntime.legalOperator) uses the collected data for various purposes:\n\n\u{2022} To provide and maintain our Service\n\u{2022} To notify you about changes to our Service\n\u{2022} To allow you to participate in interactive features of our Service when you choose to do so\n\u{2022} To gather analysis or valuable information so that we can improve our Service\n\u{2022} To monitor the usage of our Service\n\u{2022} To detect, prevent and address technical issues")

                sectionHeader("Transfer of Data")
                policyText("Your information, including Personal Data, may be transferred to \u{2014} and maintained on \u{2014} computers located outside of your state, province, country or other governmental jurisdiction where the data protection laws may differ from those of your jurisdiction.\n\nYour consent to this Privacy Policy followed by your submission of such information represents your agreement to that transfer.\n\n\(BrandRuntime.legalOperator) will take all the steps reasonably necessary to ensure that your data is treated securely and in accordance with this Privacy Policy and no transfer of your Personal Data will take place to an organisation or a country unless there are adequate controls in place including the security of your data and other personal information.")

                sectionHeader("Disclosure of Data")

                subSectionHeader("Disclosure for Law Enforcement")
                policyText("Under certain circumstances, \(BrandRuntime.legalOperator) may be required to disclose your Personal Data if required to do so by law or in response to valid requests by public authorities (e.g. a court or a government agency).")

                subSectionHeader("Legal Requirements")
                policyText("\(BrandRuntime.legalOperator) may disclose your Personal Data in the good faith belief that such action is necessary to:\n\n\u{2022} To comply with a legal obligation\n\u{2022} To protect and defend the rights or property of \(BrandRuntime.legalOperator)\n\u{2022} To prevent or investigate possible wrongdoing in connection with the Service\n\u{2022} To protect the personal safety of users of the Service or the public\n\u{2022} To protect against legal liability")

                sectionHeader("Security of Data")
                policyText("The security of your data is important to us but remember that no method of transmission over the Internet or method of electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your Personal Data, we cannot guarantee its absolute security.")

                sectionHeader("Service Providers")
                policyText("We may employ third party companies and individuals to facilitate our Service (\u{201C}Service Providers\u{201D}), provide the Service on our behalf, perform Service-related services or assist us in analysing how our Service is used.\n\nThese third parties have access to your Personal Data only to perform these tasks on our behalf and are obligated not to disclose or use it for any other purpose.")

                sectionHeader("Analytics")
                policyText("We may use third-party Service Providers to monitor and analyze the use of our Service.")

                sectionHeader("Changes to This Privacy Policy")
                policyText("We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page.\n\nWe will let you know via email and/or a prominent notice on our Service, prior to the change becoming effective and update the \u{201C}effective date\u{201D} at the top of this Privacy Policy.\n\nYou are advised to review this Privacy Policy periodically for any changes. Changes to this Privacy Policy are effective when they are posted on this page.")

                if !BrandRuntime.contactLines.isEmpty {
                    sectionHeader("Contact Us")
                    policyText("If you have any questions about this Privacy Policy, please contact us:\n\n" + BrandRuntime.contactLines)
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.adaptiveBg)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.brandOnBg)
            .padding(.top, 20)
    }

    private func subSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.top, 12)
    }

    private func policyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.primary)
            .padding(.top, 8)
    }
}
