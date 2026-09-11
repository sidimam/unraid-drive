import SwiftUI
import Libmpv
#if canImport(UIKit)
import UIKit
public typealias MPVPlatformViewController = UIViewController
#else
import AppKit
public typealias MPVPlatformViewController = NSViewController
#endif

// Playback of formats AVFoundation does not handle (MKV, AVI, WebM, FLAC, …) through libmpv
// and FFmpeg — the engine behind IINA and mpv — shipped as the LGPL build of MPVKit.
// Rendering: mpv's gpu-next output on a CAMetalLayer through MoltenVK, hardware decoding via
// VideoToolbox. Adapted from the MPVKit demo (LGPL 3).

/// MoltenVK briefly sets the drawable size to 1×1 when it forces a presentation; ignore it.
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if Int(newValue.width) > 1 && Int(newValue.height) > 1 { super.drawableSize = newValue } }
    }
}

@MainActor
protocol MPVPlayerEvents: AnyObject {
    func mpvBuffering(_ buffering: Bool)
    func mpvProgress(position: Double, duration: Double)
    func mpvEnded()
    func mpvFailed(_ message: String)
}

final class MPVViewController: MPVPlatformViewController {
    let url: URL
    let headers: [String: String]
    weak var events: MPVPlayerEvents?
    private let metalLayer = MPVMetalLayer()
    private var mpv: OpaquePointer?
    private let queue = DispatchQueue(label: "mpv.events", qos: .userInitiated)

    init(url: URL, headers: [String: String] = [:]) { self.url = url; self.headers = headers; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("not supported") }

    #if canImport(UIKit)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.traitCollection.displayScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)
        setupMpv()
        command("loadfile", [url.absoluteString, "replace"])
        #if os(tvOS)
        installRemoteHandlers()
        #else
        let tap = UITapGestureRecognizer(target: self, action: #selector(onPlayPause))
        view.addGestureRecognizer(tap)
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shutdown()
    }
    #else
    override func loadView() { view = NSView(); view.wantsLayer = true }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer?.backgroundColor = NSColor.black.cgColor
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(metalLayer)
        setupMpv()
        command("loadfile", [url.absoluteString, "replace"])
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.backingScaleFactor ?? 2
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        shutdown()
    }
    #endif

    deinit { shutdown() }

    // MARK: mpv

    private func setupMpv() {
        guard let handle = mpv_create() else { events?.mpvFailed("mpv could not start"); return }
        mpv = handle
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid))
        for (k, v) in [
            // No Lua: mpv's built-in scripts (stats, console, ytdl_hook, auto profiles) run on LuaJIT,
            // whose generated code is killed by the hardened runtime on macOS ("Code Signature Invalid"
            // in load_builtin) — the notarized app crashed as soon as a file was loaded. The app draws
            // its own controls, so nothing is lost.
            ("load-scripts", "no"), ("load-stats-overlay", "no"), ("load-osd-console", "no"),
            ("load-auto-profiles", "no"), ("osc", "no"), ("ytdl", "no"),
            ("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"), ("video-rotate", "no"),
            ("keep-open", "no"), ("idle", "yes"),
            ("cache", "yes"), ("demuxer-max-bytes", "150MiB"), ("demuxer-readahead-secs", "20"),
            ("network-timeout", "30"), ("user-agent", "UnraidDrive"),
            ("subs-match-os-language", "yes"), ("subs-fallback", "yes"),
            ("audio-channels", "auto-safe"), ("volume-max", "100"),
        ] { check(mpv_set_option_string(handle, k, v)) }
        if !headers.isEmpty {
            // Same headers as URLSession: Authorization bearer and, if any, the Cloudflare Access token.
            let fields = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
            check(mpv_set_option_string(handle, "http-header-fields", fields))
        }
        #if DEBUG
        check(mpv_request_log_messages(handle, "warn"))
        #else
        check(mpv_request_log_messages(handle, "no"))
        #endif
        check(mpv_initialize(handle))
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVViewController>.fromOpaque(ctx).takeUnretainedValue().readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        queue.async { mpv_terminate_destroy(handle) }
    }

    private var duration: Double = 0

    private func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let handle = self.mpv {
                guard let ev = mpv_wait_event(handle, 0), ev.pointee.event_id != MPV_EVENT_NONE else { break }
                switch ev.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    guard let prop = UnsafePointer<mpv_event_property>(OpaquePointer(ev.pointee.data))?.pointee, let data = prop.data else { continue }
                    let name = String(cString: prop.name)
                    switch name {
                    case "paused-for-cache":
                        let b = data.load(as: Int32.self) != 0
                        Task { @MainActor in self.events?.mpvBuffering(b) }
                    case "duration":
                        self.duration = data.load(as: Double.self)
                    case "time-pos":
                        let pos = data.load(as: Double.self), dur = self.duration
                        Task { @MainActor in self.events?.mpvProgress(position: pos, duration: dur) }
                    default: break
                    }
                case MPV_EVENT_END_FILE:
                    let end = UnsafePointer<mpv_event_end_file>(OpaquePointer(ev.pointee.data))?.pointee
                    if let end, end.reason == MPV_END_FILE_REASON_ERROR {
                        let msg = String(cString: mpv_error_string(end.error))
                        Task { @MainActor in self.events?.mpvFailed(msg) }
                    } else if let end, end.reason == MPV_END_FILE_REASON_EOF {
                        Task { @MainActor in self.events?.mpvEnded() }
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    #if DEBUG
                    if let m = UnsafePointer<mpv_event_log_message>(OpaquePointer(ev.pointee.data))?.pointee {
                        print("[mpv \(String(cString: m.prefix))] \(String(cString: m.text))", terminator: "")
                    }
                    #endif
                default: break
                }
            }
        }
    }

    private func command(_ name: String, _ args: [String]) {
        guard let handle = mpv else { return }
        var cargs: [UnsafePointer<CChar>?] = ([name] + args).map { UnsafePointer(strdup($0)) } + [nil]
        defer { for p in cargs where p != nil { free(UnsafeMutablePointer(mutating: p)) } }
        check(mpv_command(handle, &cargs))
    }

    private func check(_ status: CInt) {
        #if DEBUG
        if status < 0 { print("mpv: \(String(cString: mpv_error_string(status)))") }
        #endif
    }

    // MARK: Controls

    func togglePause() { command("cycle", ["pause"]) }
    func seek(_ seconds: Double) { command("seek", [String(seconds), "relative"]) }
    var isPaused: Bool {
        guard let handle = mpv else { return true }
        var flag: Int32 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
        return flag != 0
    }

    #if canImport(UIKit)
    @objc private func onPlayPause() { togglePause() }
    #endif
    #if os(tvOS)
    private func installRemoteHandlers() {
        let playPause = UITapGestureRecognizer(target: self, action: #selector(onPlayPause))
        playPause.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue), NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(playPause)
        let left = UITapGestureRecognizer(target: self, action: #selector(onLeft))
        left.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        view.addGestureRecognizer(left)
        let right = UITapGestureRecognizer(target: self, action: #selector(onRight))
        right.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        view.addGestureRecognizer(right)
    }
    @objc private func onLeft() { seek(-10) }
    @objc private func onRight() { seek(10) }
    #endif
}

/// Lets SwiftUI overlays drive the player (play/pause, seek).
@MainActor final class MPVHandle: ObservableObject {
    weak var controller: MPVViewController?
    func togglePause() { controller?.togglePause() }
    func seek(_ s: Double) { controller?.seek(s) }
}

/// SwiftUI wrapper; reports buffering, progress, end and errors.
#if canImport(UIKit)
struct MPVPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL
    var headers: [String: String] = [:]
    var handle: MPVHandle? = nil
    var onBuffering: (Bool) -> Void = { _ in }
    var onProgress: (Double, Double) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> MPVViewController {
        let vc = MPVViewController(url: url, headers: headers)
        vc.events = context.coordinator
        handle?.controller = vc
        return vc
    }
    func updateUIViewController(_ vc: MPVViewController, context: Context) { context.coordinator.parent = self }
    typealias Coordinator = MPVCoordinator
}
#else
struct MPVPlayerRepresentable: NSViewControllerRepresentable {
    let url: URL
    var headers: [String: String] = [:]
    var handle: MPVHandle? = nil
    var onBuffering: (Bool) -> Void = { _ in }
    var onProgress: (Double, Double) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSViewController(context: Context) -> MPVViewController {
        let vc = MPVViewController(url: url, headers: headers)
        vc.events = context.coordinator
        handle?.controller = vc
        return vc
    }
    func updateNSViewController(_ vc: MPVViewController, context: Context) { context.coordinator.parent = self }
    typealias Coordinator = MPVCoordinator
}
#endif

@MainActor final class MPVCoordinator: MPVPlayerEvents {
    var parent: MPVPlayerRepresentable
    init(_ p: MPVPlayerRepresentable) { parent = p }
    func mpvBuffering(_ b: Bool) { parent.onBuffering(b) }
    func mpvProgress(position: Double, duration: Double) { parent.onProgress(position, duration) }
    func mpvEnded() { parent.onEnd() }
    func mpvFailed(_ m: String) { parent.onError(m) }
}
