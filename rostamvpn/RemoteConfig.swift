// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RostamKit

/// The app's configuration, fetched from the server.
enum RemoteConfig {
    private static let suite = BrandRuntime.appGroup
    /// The key the tunnel reads. Changing it silently strands the extension on
    /// whatever it cached last, so it is defined once, here.
    private static let key = "config"
    private static let versionKey = "configVersion"
    private static let publishedKey = "configPublishedAt"

    /// The config the tunnel will use, or nil if none has ever been stored. Free-
    /// tier speed limit in kbps, from the config. 0 = unlimited.
    static var freeKbps: Int {
        guard
            let raw = current,
            let d = raw.data(using: .utf8),
            let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let th = o["throttle"] as? [String: Any],
            (th["enabled"] as? Bool) ?? false,
            let kbps = th["free_kbps"] as? Int
        else { return 0 }
        return max(0, kbps)
    }

    static var current: String? {
        UserDefaults(suiteName: suite)?.string(forKey: key)
    }

    /// Publish version and publish DATE, for display. The server is the authority
    /// on the date: one derived from when the device fetched would read "just now"
    /// for a config published months ago.
    static var stamp: (version: String, publishedAt: Date?) {
        let d = UserDefaults(suiteName: suite)
        let v = d?.string(forKey: versionKey) ?? ""
        let ts = d?.double(forKey: publishedKey) ?? 0
        return (v, ts > 0 ? Date(timeIntervalSince1970: ts) : nil)
    }

    private static let noV2Key = "config_no_v2"
    private static let pathV2 = "/api/v2/config"
    private static let pathV1 = "/api/v1/config"

    /// Fetch, verify and cache.
    static func refresh(completion: ((Bool) -> Void)? = nil) {
        let d = UserDefaults(suiteName: suite)
        if d?.bool(forKey: noV2Key) == true {
            refresh(path: pathV1, completion: completion)
            return
        }
        refresh(path: pathV2) { ok, absent in
            guard absent else { completion?(ok); return }

            NSLog("[Config] no v2 endpoint here; using v1")
            d?.set(true, forKey: noV2Key)
            refresh(path: pathV1, completion: completion)
        }
    }

    private static func refresh(path: String, completion: ((Bool) -> Void)? = nil) {
        refresh(path: path) { ok, _ in completion?(ok) }
    }

    /// `absent` is true only for a 404, which is the one status that means "ask
    /// somewhere else" rather than "this failed".
    private static func refresh(path: String, done: @escaping (Bool, Bool) -> Void) {
        var request = URLRequest(url: URL(string: "\(BrandRuntime.cashierBase)\(path)")!)
        request.timeoutInterval = 10
        request.setValue(BrandRuntime.wgtcpAPIKey, forHTTPHeaderField: "X-Api-Key")

        request.setValue(BrandRuntime.cashierKey, forHTTPHeaderField: "X-App-Key")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            guard
                let http, http.statusCode == 200,
                let data, let body = String(data: data, encoding: .utf8)
            else {
                done(false, http?.statusCode == 404)
                return
            }

            let opened = RedSocketClient.shared.unsealConfig(
                body.trimmingCharacters(in: .whitespacesAndNewlines),
                certSHA256Hex: signingCertSHA256()
            )
            guard !opened.hasPrefix("err:") else {
                NSLog("[Config] did not verify (\(opened)); keeping what we have")
                done(false, false)
                return
            }
            guard looksUsable(opened) else {
                NSLog("[Config] failed validation; keeping what we have")
                done(false, false)
                return
            }

            let d = UserDefaults(suiteName: suite)
            d?.set(opened, forKey: key)
            if let v = http.value(forHTTPHeaderField: "X-Config-Version") {
                d?.set(v, forKey: versionKey)
            }
            if let p = http.value(forHTTPHeaderField: "X-Config-Published"),
               let ts = Double(p), ts > 0 {
                d?.set(ts, forKey: publishedKey)
            }
            NSLog("[Config] updated (\(opened.count) bytes)")
            done(true, false)
        }.resume()
    }

    /// Enough of a check that a client cannot be talked into a config it cannot
    /// use. Deliberately shallow: validating individual fields here would reject
    /// anything added server-side before the app knew about it.
    private static func looksUsable(_ json: String) -> Bool {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["version"] != nil,
            let transport = obj["transport"] as? [String: Any],
            let redsocket = transport["redsocket"] as? [String: Any],
            let entries = redsocket["entries"] as? [Any]
        else { return false }
        return !entries.isEmpty
    }

    /// SHA-256 of this build's signing certificate, hex.
    private static func signingCertSHA256() -> String {
        FleetConstants.configSealCertSHA256
    }
}
