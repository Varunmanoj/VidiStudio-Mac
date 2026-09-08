import SwiftUI
import AVKit
import WebKit

@MainActor protocol FullScreenVideoSizing: AnyObject { var fullScreenFrame: NSRect? { get set } }
final class VideoWebView: WKWebView, FullScreenVideoSizing {
    var fullScreenFrame: NSRect?
    override var frame: NSRect { get { super.frame } set { super.frame = fullScreenFrame ?? newValue } }
}

@MainActor @Observable
final class PlaybackModel {
    let player = AVPlayer()
    var time = 0.0
    var duration = 0.0
    var videoTitle = ""
    @ObservationIgnored weak var videoSurface: NSView?
    private var fullScreenKeyMonitor: Any?
    private var normalVideoFrame = NSRect.zero
    private var normalAutoresizing: NSView.AutoresizingMask = []
    private var normalTranslatesConstraints = false
    private var fullScreenContainer: NSView?
    private var originalVideoParent: NSView?
    func exitVideoFullScreen() {
        if let container = fullScreenContainer, let surface = videoSurface {
            (surface as? FullScreenVideoSizing)?.fullScreenFrame = nil
            container.exitFullScreenMode(options: nil)
            surface.removeFromSuperview()
            originalVideoParent?.addSubview(surface)
            surface.translatesAutoresizingMaskIntoConstraints = normalTranslatesConstraints
            surface.autoresizingMask = normalAutoresizing
            surface.frame = normalVideoFrame
        }
        fullScreenContainer = nil; originalVideoParent = nil
        if let monitor = fullScreenKeyMonitor { NSEvent.removeMonitor(monitor); fullScreenKeyMonitor = nil }
    }
    func toggleVideoFullScreen() {
        guard let surface = videoSurface else { return }
        if fullScreenContainer != nil { exitVideoFullScreen(); return }
        guard let screen = surface.window?.screen ?? NSScreen.main else { return }
        normalVideoFrame = surface.frame
        normalAutoresizing = surface.autoresizingMask
        normalTranslatesConstraints = surface.translatesAutoresizingMaskIntoConstraints
        originalVideoParent = surface.superview
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
        fullScreenContainer = container
        surface.removeFromSuperview()
        container.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        surface.frame = container.bounds
        (surface as? FullScreenVideoSizing)?.fullScreenFrame = container.bounds
        guard container.enterFullScreenMode(screen, withOptions: [.fullScreenModeAllScreens: false]) else { exitVideoFullScreen(); return }
        (surface as? FullScreenVideoSizing)?.fullScreenFrame = container.bounds
        surface.frame = container.bounds
        fullScreenKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.exitVideoFullScreen(); return nil }; return event
        }
    }
    var playing = false
    var narrationEnabled = false
    var speechError: String?
    private var narration: AVAudioPlayer?
    private var narrationID: String?
    private let deviceSpeech = AVSpeechSynthesizer()
    private var deviceCue: String?
    private var deviceTime = 0.0
    private func stopDeviceSpeech() {
        deviceSpeech.stopSpeaking(at: .immediate); deviceCue = nil
    }
    var webView: WKWebView?
    private var observer: Any?
    func observe() {
        guard observer == nil else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in if time.seconds.isFinite, self?.webView == nil { self?.time = time.seconds; self?.playing = self?.player.timeControlStatus == .playing } }
        }
    }
    func syncNarration(_ project: StudioProject, settings: StudioSettings) {
        if settings.narrationPlayback == "device" {
            narration?.stop(); narrationID = nil
            guard narrationEnabled, playing, let cue = project.cues.first(where: { time >= $0.start && time < $0.end }) else { stopDeviceSpeech(); return }
            let identity = cue.id + cue.text + settings.narrationSignature
            if deviceCue != identity || abs(time - deviceTime) > 0.8 {
                stopDeviceSpeech()
                deviceSpeech.speak(SystemSpeechUtterance.make(text: cue.text, settings: settings))
                deviceCue = identity
                speechError = nil
            }
            deviceTime = time
            return
        }
        stopDeviceSpeech()
        guard narrationEnabled, playing,
              let cue = project.cues.first(where: { time >= $0.start && time < $0.end }),
              cue.audioText == cue.text, cue.audioSettings == settings.narrationSignature,
              let path = cue.audio, let url = project.url(path) else {
            narration?.stop(); narrationID = nil; return
        }
        let offset = max(0, time - cue.start)
        if narrationID != cue.id {
            narration?.stop(); narration = try? AVAudioPlayer(contentsOf: url); narrationID = cue.id
            narration?.currentTime = offset
            if offset < narration?.duration ?? 0 { narration?.play() }
        } else if let narration, abs(narration.currentTime - offset) > 0.4, offset < narration.duration {
            narration.currentTime = offset; narration.play()
        }
    }
    func stop() {
        exitVideoFullScreen()
        stopDeviceSpeech()
        narration?.stop(); narrationID = nil
        player.pause()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
        webView?.evaluateJavaScript("player?.pauseVideo()", completionHandler: nil)
    }
    func togglePlayback() {
        if let webView { webView.evaluateJavaScript("player && (player.getPlayerState() === 1 ? player.pauseVideo() : player.playVideo())", completionHandler: nil) }
        else if player.timeControlStatus == .playing { player.pause() }
        else { player.play() }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = max(0, seconds)
        if let webView { webView.evaluateJavaScript("player?.seekTo(\(time),true)", completionHandler: nil) }
        else { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
    }
}

struct YouTubePlayer: NSViewRepresentable {
    let url: String
    let playback: PlaybackModel
    func makeCoordinator() -> Coordinator { Coordinator(playback) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "playback")
        let view = VideoWebView(frame: .zero, configuration: config)
        playback.webView = view
        playback.videoSurface = view
        let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
        guard id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return view }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body,#player{width:100%;height:100%;margin:0;background:#000}</style></head><body><div id="player"></div><script src="https://www.youtube.com/iframe_api"></script><script>
        var player; function onYouTubeIframeAPIReady(){player=new YT.Player('player',{videoId:'\(id)',playerVars:{playsinline:1,origin:'https://accessivideo.pages.dev'},events:{onReady:function(){setInterval(function(){window.webkit.messageHandlers.playback.postMessage({time:player.getCurrentTime(),duration:player.getDuration(),state:player.getPlayerState(),title:player.getVideoData().title || ''});},150);}}});}
        </script></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://accessivideo.pages.dev"))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "playback")
        coordinator.playback.webView = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let playback: PlaybackModel
        init(_ playback: PlaybackModel) { self.playback = playback }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: Any] else { return }
            if let time = data["time"] as? Double, time.isFinite { playback.time = time }
            if let title = data["title"] as? String, !title.isEmpty { playback.videoTitle = title }
            playback.playing = (data["state"] as? Int) == 1
            if let duration = data["duration"] as? Double, duration.isFinite { playback.duration = duration }
        }
    }
}
