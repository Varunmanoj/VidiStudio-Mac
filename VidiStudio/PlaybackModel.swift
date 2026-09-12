import SwiftUI
import AVKit
import WebKit

@MainActor protocol FullScreenVideoSizing: AnyObject { var fullScreenFrame: NSRect? { get set } }
final class VideoWebView: WKWebView, FullScreenVideoSizing {
    var fullScreenFrame: NSRect?
    override var frame: NSRect { get { super.frame } set { super.frame = fullScreenFrame ?? newValue } }
}

/// Full-screen host that exits on Escape even if the key event monitor misses,
/// e.g. while player controls hold focus.
final class FullScreenContainerView: NSView {
    var onEscape: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
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
    /// Superview constraints positioning the surface. Removing the surface from
    /// its parent drops these, so they must be saved and re-added on exit or
    /// the preview restores collapsed.
    private var normalVideoConstraints: [NSLayoutConstraint] = []
    func exitVideoFullScreen() {
        if let container = fullScreenContainer, let surface = videoSurface {
            (surface as? FullScreenVideoSizing)?.fullScreenFrame = nil
            container.exitFullScreenMode(options: nil)
            surface.removeFromSuperview()
            if let parent = originalVideoParent {
                parent.addSubview(surface)
                surface.translatesAutoresizingMaskIntoConstraints = normalTranslatesConstraints
                surface.autoresizingMask = normalAutoresizing
                if !normalVideoConstraints.isEmpty {
                    parent.addConstraints(normalVideoConstraints)
                }
                surface.frame = normalVideoFrame
                surface.needsLayout = true
                parent.updateConstraintsForSubtreeIfNeeded()
                parent.layoutSubtreeIfNeeded()
            }
        }
        fullScreenContainer = nil; originalVideoParent = nil
        normalVideoConstraints = []
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
        if let parent = originalVideoParent {
            normalVideoConstraints = parent.constraints.filter {
                ($0.firstItem as? NSView) === surface || ($0.secondItem as? NSView) === surface
            }
        } else {
            normalVideoConstraints = []
        }
        let container = FullScreenContainerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
        container.onEscape = { [weak self] in
            Task { @MainActor [weak self] in self?.exitVideoFullScreen() }
        }
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
    var playing = false {
        didSet { if !playing { stopNarration() } }
    }
    var narrationEnabled = false {
        didSet { if !narrationEnabled { stopNarration() } }
    }
    var speechError: String?
    private var narration: AVAudioPlayer?
    private var narrationID: String?
    private var indicationSound: AVAudioPlayer?
    private var indicatedSegment: String?

    private func syncIndication(_ project: StudioProject, settings: StudioSettings) {
        guard let cue = project.cues.first(where: { time >= $0.start && time < $0.end }) else {
            indicatedSegment = nil
            indicationSound?.stop()
            setIndicationDucking(false)
            return
        }
        let sound: String?
        if !narrationEnabled {
            sound = settings.soundWhenNarrationOff ? "Boink3" : nil
        } else if settings.narrationPlayback == "generated",
                  settings.soundWhenNarrationMissing,
                  SynchronizedAudioStatus.resolve(cue: cue, project: project) != .generated {
            sound = "ascend"
        } else {
            sound = nil
        }
        guard playing else { indicationSound?.stop(); setIndicationDucking(false); return }
        // Track entries even when disabled, so toggling a setting mid-segment
        // does not produce a delayed cue or repeat a cue on pause/resume.
        let entering = indicatedSegment != cue.id
        indicatedSegment = cue.id
        guard let sound else { indicationSound?.stop(); setIndicationDucking(false); return }
        guard entering else {
            setIndicationDucking(indicationSound?.isPlaying == true)
            return
        }
        indicationSound?.stop()
        guard let url = Bundle.main.url(forResource: sound, withExtension: "wav") else { setIndicationDucking(false); return }
        indicationSound = try? AVAudioPlayer(contentsOf: url)
        indicationSound?.volume = 1
        indicationSound?.play()
        setIndicationDucking(indicationSound?.isPlaying == true)
    }
    private let deviceSpeech = AVSpeechSynthesizer()
    private var deviceCue: String?
    private var deviceTime = 0.0
    private var unduckedVolume: Float?
    private var appliedDuckedVolume: Float?
    private var webVolumeDucked = false
    private var narrationDuckingRequested = false
    private var indicationDuckingRequested = false

    // Attenuate the soundtrack relative to the user's volume, never narration
    // or the short AD indication sounds.
    private func applyDucking() {
        let active = narrationDuckingRequested || indicationDuckingRequested
        if let webView {
            if active != webVolumeDucked {
                webVolumeDucked = active
                webView.evaluateJavaScript("setNarrationDucking(\(active ? "true" : "false"))", completionHandler: nil)
            }
            return
        }
        if active {
            if unduckedVolume == nil || player.volume != appliedDuckedVolume {
                unduckedVolume = player.volume
                appliedDuckedVolume = player.volume * 0.2
                player.volume = appliedDuckedVolume ?? 0
            }
        } else if let original = unduckedVolume {
            // Respect a volume change made in the player while narration was active.
            if player.volume == appliedDuckedVolume { player.volume = original }
            unduckedVolume = nil
            appliedDuckedVolume = nil
        }
    }

    private func setNarrationDucking(_ active: Bool) {
        narrationDuckingRequested = active
        applyDucking()
    }

    private func setIndicationDucking(_ active: Bool) {
        indicationDuckingRequested = active
        applyDucking()
    }

    private func stopNarration() {
        indicationSound?.stop()
        setIndicationDucking(false)
        stopDeviceSpeech()
        narration?.stop(); narrationID = nil
        setNarrationDucking(false)
    }
    func stopNarrationPlayback() {
        stopNarration()
    }
    private func stopDeviceSpeech() {
        deviceSpeech.stopSpeaking(at: .immediate); deviceCue = nil
    }
    var webView: WKWebView?
    private var observer: Any?
    func observe() {
        guard observer == nil else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, time.seconds.isFinite, self.webView == nil else { return }
                self.time = time.seconds
                self.playing = self.player.timeControlStatus == .playing
            }
        }
    }
    func syncNarration(_ project: StudioProject, settings: StudioSettings) {
        syncIndication(project, settings: settings)
        if settings.narrationPlayback == "device" {
            narration?.stop(); narrationID = nil
            guard narrationEnabled, playing, let cue = project.cues.first(where: { time >= $0.start && time < $0.end }) else { stopDeviceSpeech(); setNarrationDucking(false); return }
            let identity = cue.id + cue.text + settings.systemSpeechSignature
            if deviceCue != identity || abs(time - deviceTime) > 0.8 {
                stopDeviceSpeech()
                deviceCue = identity
                do {
                    deviceSpeech.speak(try SystemSpeechUtterance.make(text: cue.text, settings: settings))
                    speechError = nil
                } catch {
                    speechError = error.localizedDescription
                    setNarrationDucking(false)
                }
            }
            deviceTime = time
            setNarrationDucking(deviceSpeech.isSpeaking)
            return
        }
        stopDeviceSpeech()
        guard narrationEnabled, playing,
              let cue = project.cues.first(where: { time >= $0.start && time < $0.end }),
              cue.audioText == cue.text,
              let path = cue.audio, let url = project.url(path) else {
            narration?.stop(); narrationID = nil; setNarrationDucking(false); return
        }
        let offset = max(0, time - cue.start)
        if narrationID != cue.id {
            narration?.stop(); narration = try? AVAudioPlayer(contentsOf: url); narrationID = cue.id
            narration?.currentTime = offset
            if offset < narration?.duration ?? 0 { narration?.play() }
        } else if let narration, abs(narration.currentTime - offset) > 0.4, offset < narration.duration {
            narration.currentTime = offset; narration.play()
        }
        setNarrationDucking(narration?.isPlaying == true)
    }
    func stop() {
        indicatedSegment = nil
        exitVideoFullScreen()
        stopNarration()
        player.pause()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
        webView?.evaluateJavaScript("player?.pauseVideo()", completionHandler: nil)
    }
    func togglePlayback() {
        if playing || player.timeControlStatus == .playing { stopNarration() }
        if let webView { webView.evaluateJavaScript("player && (player.getPlayerState() === 1 ? player.pauseVideo() : player.playVideo())", completionHandler: nil) }
        else if player.timeControlStatus == .playing { player.pause() }
        else { player.play() }
    }
    func pauseAndCaptureTime(_ completion: @escaping (Double) -> Void) {
        stopNarration()
        playing = false
        if let webView {
            webView.evaluateJavaScript("player ? (player.pauseVideo(), player.getCurrentTime()) : null") { [weak self] result, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let captured = (result as? NSNumber)?.doubleValue ?? self.time
                    if captured.isFinite { self.time = max(0, captured) }
                    completion(self.time)
                }
            }
        } else {
            let current = player.currentTime().seconds
            player.pause()
            if current.isFinite { time = max(0, current) }
            completion(time)
        }
    }
    func play(from seconds: Double) {
        guard seconds.isFinite else { return }
        indicatedSegment = nil
        stopNarration()
        time = max(0, seconds)
        if let webView {
            webView.evaluateJavaScript("player && (player.seekTo(\(time), true), player.playVideo())", completionHandler: nil)
        } else {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard finished, let self else { return }
                    self.player.play()
                }
            }
        }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        indicatedSegment = nil
        stopNarration()
        time = max(0, seconds)
        if let webView { webView.evaluateJavaScript("player?.seekTo(\(time),true)", completionHandler: nil) }
        else { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
    }
    /// Pause video playback and stop narration without moving the playhead.
    func pausePlayback() {
        stopNarration()
        playing = false
        if let webView { webView.evaluateJavaScript("player?.pauseVideo()", completionHandler: nil) }
        else { player.pause() }
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
        var narrationDucked=false, originalVolume=null, duckedVolume=null;
        function setNarrationDucking(active){
            narrationDucked=active;
            if(!player || !player.getVolume)return;
            if(active){updateNarrationVolume();}
            else if(originalVolume!==null){
                if(Math.abs(player.getVolume()-duckedVolume)<1)player.setVolume(originalVolume);
                originalVolume=null;duckedVolume=null;
            }
        }
        function updateNarrationVolume(){
            if(!narrationDucked || !player || !player.getVolume)return;
            var current=player.getVolume();
            if(originalVolume===null || Math.abs(current-duckedVolume)>=1){
                originalVolume=current;duckedVolume=Math.round(current*0.2);player.setVolume(duckedVolume);
            }
        }
        setInterval(updateNarrationVolume,150);
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
