// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RostamKit

/// This device's WireGuard identity.
enum WgtcpIdentity {
    private static let privKey = "wgtcp_private_key"
    private static let pubKey = "wgtcp_public_key"

    struct Keypair {
        let privateKey: String
        let publicKey: String
    }

    /// Load the keypair, generating it on first use.
    static func ensure() -> Keypair? {
        if let p = KeychainService.getString(for: privKey),
           let u = KeychainService.getString(for: pubKey),
           !p.isEmpty, !u.isEmpty {
            return Keypair(privateKey: p, publicKey: u)
        }
        guard let kp = WgtcpClient.shared.generateKeypair(),
              !kp.privateKey.isEmpty, !kp.publicKey.isEmpty else {
            NSLog("[wgtcp] keypair generation failed")
            return nil
        }
        do {
            try KeychainService.setString(kp.privateKey, for: privKey)
            try KeychainService.setString(kp.publicKey, for: pubKey)
        } catch {
            NSLog("[wgtcp] could not persist keypair: \(error)")
            return nil
        }
        return Keypair(privateKey: kp.privateKey, publicKey: kp.publicKey)
    }
}

/// Fetches this device's WGTCP profile: the tunnel address and the endpoints
/// that will accept its key.
enum WgtcpProvisioner {
    private static let suite = BrandRuntime.appGroup
    private static let kProfile = "wgtcp_profile_json"
    private static let kFetched = "wgtcp_profile_fetched_at"
    private static let kProfileFor = "wgtcp_profile_for_pubkey"

    /// Re-fetch this often, to pick up new POPs and a moved endpoint.
    private static let refreshAfter: TimeInterval = 12 * 60 * 60

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    /// Fetch and cache a profile. BLOCKS on the network — never call from main.
    static func config(socksPort: Int? = nil) -> String? {
        guard let keys = WgtcpIdentity.ensure(), let d = defaults else { return nil }

        let cached = d.string(forKey: kProfile) ?? ""
        let age = Date().timeIntervalSince1970 - d.double(forKey: kFetched)
        let issuedFor = d.string(forKey: kProfileFor) ?? ""

        let wrongKey = !issuedFor.isEmpty && issuedFor != keys.publicKey
        if wrongKey { NSLog("[wgtcp] cached profile was issued for another key; re-provisioning") }
        let stale = cached.isEmpty || wrongKey || age > refreshAfter

        if stale {
            if let fresh = fetch(publicKey: keys.publicKey, socksPort: socksPort) {
                d.set(fresh, forKey: kProfile)
                d.set(keys.publicKey, forKey: kProfileFor)
                d.set(Date().timeIntervalSince1970, forKey: kFetched)
                return build(privateKey: keys.privateKey, profileJSON: fresh)
            }

            if cached.isEmpty || wrongKey {
                NSLog("[wgtcp] no usable profile and provisioning failed; WGTCP unavailable")
                return nil
            }
            NSLog("[wgtcp] provisioning failed; using the cached profile")
        }
        return build(privateKey: keys.privateKey, profileJSON: cached)
    }

    /// Drop the cached profile, forcing a fetch on the next connect.
    static func invalidate() {
        defaults?.removeObject(forKey: kProfile)
        defaults?.removeObject(forKey: kFetched)
    }

    /// Merge the server's answer with the private key that never left the device.
    private static func build(privateKey: String, profileJSON: String) -> String? {
        guard
            let data = profileJSON.data(using: .utf8),
            let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let serverPub = p["server_public_key"] as? String,
            let address = p["address"] as? String,
            let gateway = p["gateway"] as? String,
            let endpoints = p["endpoints"] as? [String], !endpoints.isEmpty
        else {
            NSLog("[wgtcp] cached profile is unusable")
            return nil
        }
        let out: [String: Any] = [
            "private_key": privateKey,
            "peer_public_key": serverPub,

            "endpoint": endpoints.randomElement() ?? endpoints[0],
            "address": address,
            "gateway": gateway,
            "prefix_len": p["prefix_len"] as? Int ?? 24,
            "mtu": p["mtu"] as? Int ?? 1380,
            "persistent_keepalive": p["persistent_keepalive"] as? Int ?? 25,
        ]
        guard let j = try? JSONSerialization.data(withJSONObject: out) else { return nil }
        return String(data: j, encoding: .utf8)
    }

    private static func fetch(publicKey: String, socksPort: Int?) -> String? {
        let cid = CashierIdentity.current
        guard !cid.isEmpty else {
            NSLog("[wgtcp] no cid; cannot provision")
            return nil
        }

        guard let url = URL(string: BrandRuntime.cashierBase + "/api/v1/wgtcp/profile") else { return nil }

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 10
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(BrandRuntime.wgtcpAPIKey, forHTTPHeaderField: "X-Api-Key")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["pubkey": publicKey, "cid": cid])

        let cfg = URLSessionConfiguration.ephemeral
        if let port = socksPort {
            cfg.connectionProxyDictionary = [
                "SOCKSEnable": 1,
                "SOCKSProxy": "127.0.0.1",
                "SOCKSPort": port,
            ]
        }
        let session = URLSession(configuration: cfg)

        var out: String?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: r) { data, resp, err in
            defer { sem.signal() }
            if let err {
                NSLog("[wgtcp] provisioning request failed: \(err.localizedDescription)")
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data else {
                NSLog("[wgtcp] provisioning returned \(code)")
                return
            }
            out = String(data: data, encoding: .utf8)
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        return out
    }
}
