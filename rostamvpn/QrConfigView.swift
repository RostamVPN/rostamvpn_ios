// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AVFoundation
import UIKit
import RostamKit

/// Scan a server bootstrap from a QR code.
struct QrConfigView: View {
    @StateObject private var scanner = QrScanner()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch scanner.phase {
                case .checking:
                    message("Checking the camera…", detail: nil)

                case .noCamera:
                    message(
                        "No camera on this device",
                        detail: "QR scanning needs a camera. On the Simulator there "
                              + "isn't one, so this can only be tested on hardware."
                    )

                case .denied:
                    message(
                        "Camera access is off",
                        detail: "\(BrandRuntime.displayName) needs the camera to read a server code. "
                              + "Turn it on in Settings › Privacy & Security › Camera, "
                              + "or in this app's own Settings page."
                    )
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { UIApplication.shared.open(url) }
                    }

                case .unavailable(let reason):
                    message("The camera could not be opened", detail: reason)

                case .scanning:
                    CameraPreview(session: scanner.session)
                        .frame(height: 320)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                        )
                        .accessibilityLabel(Text("Camera viewfinder"))
                    Text("Point the camera at a \(BrandRuntime.displayName) server code.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                case .verifying:
                    ProgressView()
                    Text("Checking the code's signature…")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                case .rejected(let headline, let detail):
                    message(headline, detail: detail, alert: true)
                    Button("Scan again") { scanner.rescan() }

                case .applied(let version, let count):
                    message(
                        "Servers added",
                        detail: "\(count) server\(count == 1 ? "" : "s") from config "
                              + "\(version.isEmpty ? "(unversioned)" : version). "
                              + "They are tried first on the next connect."
                    )
                    Button("Scan another") { scanner.rescan() }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Scan a server code")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { scanner.begin() }
        .onDisappear { scanner.end() }
    }

    private func message(_ headline: String, detail: String?, alert: Bool = false) -> some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.headline)
                .foregroundColor(alert ? .dangerRed : .primary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.adaptiveCard)
        .cornerRadius(16)
    }
}

/// `AVCaptureVideoPreviewLayer` in a `UIView` whose `layoutSubviews` resizes
/// it. A plain `UIView` plus a layer set once gets a preview that is the wrong
/// size on rotation and on the first layout pass.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        if let c = v.previewLayer.connection, c.isVideoOrientationSupported {
            c.videoOrientation = .portrait
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Camera lifecycle, permission, and the verify-then-apply decision.
final class QrScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    enum Phase: Equatable {
        case checking
        case noCamera
        case denied
        case unavailable(String)
        case scanning
        case verifying
        case rejected(String, String)
        case applied(String, Int)
    }

    @Published private(set) var phase: Phase = .checking

    let session = AVCaptureSession()
    /// `startRunning()` blocks; it must never be called on main.
    private let queue = DispatchQueue(label: "com.rostamvpn.qr.session")
    private var configured = false
    private var handling = false

    func begin() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:

            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if ok { self.start() } else { self.phase = .denied }
                }
            }
        case .denied, .restricted:
            phase = .denied
        @unknown default:
            phase = .denied
        }
    }

    func end() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func rescan() {
        handling = false
        phase = .scanning
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    private func start() {
        guard !configured else { rescan(); return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            phase = .noCamera
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                phase = .unavailable("Another app may be using the camera. Close it and try again.")
                return
            }
            session.addInput(input)
            session.addOutput(output)

            output.setMetadataObjectsDelegate(self, queue: .main)

            output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr)
                ? [.qr] : []
            session.commitConfiguration()
            configured = true
            phase = .scanning
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
        } catch {
            phase = .unavailable("The camera reported: \(error.localizedDescription)")
        }
    }

    /// Delivered on `.main` — the queue this object handed to the output.
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handling,
              let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let raw = obj.stringValue, !raw.isEmpty
        else { return }
        handling = true
        end()
        phase = .verifying
        apply(raw)
    }

    /// The prefix the publisher mints (`publish-config.rs`: `rostam://c/{b64}`).
    private static let scheme = "rostam://c/"

    /// SHA-256 of the signing certificate the seal is bound to.
    private static let signingCertSHA256 = FleetConstants.configSealCertSHA256

    private func apply(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.hasPrefix(Self.scheme) else {
            phase = .rejected(
                "That isn't a \(BrandRuntime.displayName) code",
                "It scanned fine, but it's some other kind of QR code."
            )
            return
        }
        let sealed = String(text.dropFirst(Self.scheme.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sealed.isEmpty else {
            phase = .rejected(
                "That code is incomplete",
                "It's a \(BrandRuntime.displayName) code, but there's nothing in it. Ask for a fresh one."
            )
            return
        }

        let opened = RedSocketClient.shared.unsealConfig(
            sealed, certSHA256Hex: Self.signingCertSHA256
        )
        guard !opened.hasPrefix("err:") else {
            let reason = String(opened.dropFirst(4))
            NSLog("[QR] refused: \(reason)")

            let damaged = reason.contains("base64")
                || reason.contains("too short")
                || reason.contains("UTF-8")
            phase = damaged
                ? .rejected(
                    "That code didn't read cleanly",
                    "Part of it is missing or damaged. Move closer, avoid glare, "
                    + "and try again — or ask for a fresh code."
                  )
                : .rejected(
                    "This code is not from \(BrandRuntime.displayName)",
                    "It failed its signature check, so it was NOT applied. Either it "
                    + "was tampered with, or whoever made it isn't us. Only use codes "
                    + "from a source you trust."
                  )
            return
        }

        guard
            let data = opened.data(using: .utf8),
            let scanned = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transport = scanned["transport"] as? [String: Any],
            let redsocket = transport["redsocket"] as? [String: Any],
            let entries = redsocket["entries"] as? [Any], !entries.isEmpty
        else {
            phase = .rejected(
                "That code carries no servers",
                "It's signed by \(BrandRuntime.displayName) but there's nothing in it to connect to. "
                + "Nothing was changed."
            )
            return
        }
        let version = (scanned["version"] as? String)
            ?? (scanned["version"] as? Int).map(String.init)
            ?? ""

        let defaults = UserDefaults(suiteName: Self.suite)
        let merged: String
        if
            let existing = defaults?.string(forKey: Self.configKey),
            let base = existing.data(using: .utf8),
            var obj = try? JSONSerialization.jsonObject(with: base) as? [String: Any],
            var t = obj["transport"] as? [String: Any],
            var rs = t["redsocket"] as? [String: Any] {
            let old = rs["entries"] as? [Any] ?? []
            rs["entries"] = entries + old
            t["redsocket"] = rs
            obj["transport"] = t
            guard
                let out = try? JSONSerialization.data(withJSONObject: obj),
                let s = String(data: out, encoding: .utf8)
            else {
                phase = .rejected(
                    "Couldn't save the new servers",
                    "The stored config could not be rewritten. Nothing was changed."
                )
                return
            }
            merged = s
        } else {
            merged = opened
            defaults?.set(version, forKey: Self.versionKey)
        }

        defaults?.set(merged, forKey: Self.configKey)
        NSLog("[QR] bootstrap applied (+\(entries.count) endpoints, version \(version))")
        phase = .applied(version, entries.count)
    }

    /// The App Group and keys `RemoteConfig` owns. They are `private` there, so
    /// they are restated here and MUST match: a typo does not fail, it writes a
    /// config nothing ever reads.
    private static let suite = BrandRuntime.appGroup
    private static let configKey = "config"
    private static let versionKey = "configVersion"
}
