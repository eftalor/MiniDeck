import AppKit
import Combine

final class PlayerModel: ObservableObject {
    @Published var info = TrackInfo()
    @Published var artwork: NSImage?
    @Published var playlists: [Playlist] = []
    @Published var running = false
    @Published var errorText = ""
    @Published var hoverWindowButtons = false
    /// Non-nil while starting Music or restoring the last song; the view shows a spinner.
    @Published var loadingText: String?

    /// Song list below the player.
    @Published var showQueue = UserDefaults.standard.bool(forKey: "showQueue") {
        didSet {
            UserDefaults.standard.set(showQueue, forKey: "showQueue")
            if showQueue { loadTracks(force: true) }
            onLayoutChange?()
        }
    }
    @Published var tracks: [QueueTrack] = []
    private var tracksFor = ""          // playlist ID the list was loaded for
    /// Called when the window should resize to fit (list shown or hidden).
    var onLayoutChange: (() -> Void)?

    var currentTrackIndex: Int? {
        info.trackID.isEmpty ? nil : tracks.firstIndex { $0.trackID == info.trackID }
    }
    /// Liquid Glass window background, remembered between launches.
    @Published var glass = UserDefaults.standard.bool(forKey: "glass") {
        didSet {
            UserDefaults.standard.set(glass, forKey: "glass")
            // The window shadow follows the background's shape; redraw it.
            DispatchQueue.main.async { NSApp.windows.forEach { $0.invalidateShadow() } }
        }
    }
    /// Keep the player above other windows (remembered between launches).
    @Published var floating = UserDefaults.standard.object(forKey: "floating") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(floating, forKey: "floating")
            onFloatingChange?(floating)
        }
    }
    var onFloatingChange: ((Bool) -> Void)?

    // MARK: - Volume (Music's own, not the Mac's)
    @Published var volume: Double = 50
    @Published var showVolume = false
    private var volumeKnown = false
    private var volumeHoldUntil = Date.distantPast
    private var volumeSendScheduled = false
    private var volumeBeforeMute: Double = 50

    /// Change Music's volume; slider drags and scrolls are sent at most ~12 times a second.
    func setVolume(_ v: Double) {
        volume = max(0, min(100, v.rounded()))
        volumeHoldUntil = Date().addingTimeInterval(2)   // don't let a poll undo the change
        guard !volumeSendScheduled, running else { return }
        volumeSendScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.volumeSendScheduled = false
            self.bridge.setVolume(Int(self.volume))
        }
    }
    func toggleMute() {
        if volume > 0 { volumeBeforeMute = volume; setVolume(0) }
        else { setVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 50) }
    }
    /// Clear (most see-through) or regular (frosted) glass.
    @Published var glassClear = UserDefaults.standard.object(forKey: "glassClear") as? Bool ?? true {
        didSet { UserDefaults.standard.set(glassClear, forKey: "glassClear") }
    }
    /// When `info.position` was last read, so the bar can move smoothly between polls.
    @Published var positionStamp = Date()
    /// Set while the user drags the progress bar (0...1).
    @Published var dragFraction: Double?

    /// Position now, counting time played since the last poll.
    func livePosition(at now: Date) -> Double {
        var p = info.position
        if info.isPlaying { p += now.timeIntervalSince(positionStamp) }
        return info.duration > 0 ? min(p, info.duration) : p
    }

    private let bridge = MusicBridge()
    private var timer: Timer?
    private var artTrackID = ""
    private var polling = false
    /// After a play/pause press, ignore polled play state until this time.
    private var holdStateUntil = Date.distantPast

    // MARK: - Polling budget
    // Music announces track and play/pause changes itself, and the progress bar
    // is computed locally, so asking Music for its status is only a safety net.
    /// True while the window is on screen (not minimized, hidden or covered).
    @Published var windowVisible = true {
        didSet { if windowVisible && !oldValue { pollSoon() } }
    }
    private var nextPollAt = Date.distantPast
    private var pollInterval: TimeInterval {
        if loadingText != nil { return 1 }
        if info.isPlaying { return windowVisible ? 5 : 15 }
        return 15
    }
    /// Check Music's status within about a second (after a button press, say).
    func pollSoon(in seconds: TimeInterval = 0.8) {
        nextPollAt = min(nextPollAt, Date().addingTimeInterval(seconds))
    }
    private func tick() {
        // Cheap local check; also keeps "Music isn't running" up to date.
        let isUp = bridge.isMusicRunning
        if isUp != running || Date() >= nextPollAt { poll() }
    }

    /// Start Music hidden in the background when MiniDeck opens.
    @Published var autoStartMusic = UserDefaults.standard.object(forKey: "autoStartMusic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStartMusic, forKey: "autoStartMusic") }
    }
    private var launching = false

    /// Quit Music (and so stop playback) when MiniDeck quits.
    @Published var quitMusicOnExit = UserDefaults.standard.object(forKey: "quitMusicOnExit") as? Bool ?? true {
        didSet { UserDefaults.standard.set(quitMusicOnExit, forKey: "quitMusicOnExit") }
    }

    // MARK: - Resume where you left off

    private var resumePending = UserDefaults.standard.dictionary(forKey: "resume") != nil
    private var lastResumeSave = Date.distantPast

    /// Remember the playlist, song and position (also saved every 10 s while playing,
    /// in case MiniDeck doesn't quit cleanly).
    func saveResumePoint() {
        guard running, !info.trackID.isEmpty, info.state != "stopped", !resumePending else { return }
        lastResumeSave = Date()
        UserDefaults.standard.set(["track": info.trackID, "playlist": info.playlistID,
                                   "playlistName": info.playlist,
                                   "position": livePosition(at: Date()), "duration": info.duration,
                                   "name": info.name, "artist": info.artist, "album": info.album],
                                  forKey: "resume")
    }

    /// Load the saved song paused (or playing, if `thenPlay`). Used once per launch.
    func resume(thenPlay: Bool, completion: (() -> Void)? = nil) {
        guard resumePending, let r = UserDefaults.standard.dictionary(forKey: "resume"),
              let track = r["track"] as? String else { resumePending = false; completion?(); return }
        resumePending = false
        loadingText = "Picking up where you left off…"
        Log.write("resuming \(r["name"] ?? "") at \(Int(r["position"] as? Double ?? 0)) s")
        bridge.cue(trackID: track, playlistID: r["playlist"] as? String ?? "",
                   position: r["position"] as? Double ?? 0, thenPlay: thenPlay) { [weak self] ok in
            Log.write(ok ? "resumed" : "couldn't resume the saved song")
            self?.loadingText = nil
            self?.poll()
            completion?()
        }
    }

    /// At launch: resume unless Music is actually playing something, so it never
    /// interrupts. (Music often reopens with its own last song paused; that counts as idle.)
    private func resumeIfIdle() {
        guard resumePending, bridge.isMusicRunning else { loadingText = nil; return }
        bridge.status { [weak self] st in
            guard let self else { return }
            if let st, st.isPlaying {
                Log.write("Music is already playing; not resuming")
                self.resumePending = false
                self.loadingText = nil
                return
            }
            // Music usually reopens with its own last song paused, queue intact. Re-playing
            // the song ourselves would lose that queue (next does nothing, previous only
            // restarts the song), so if it's the same song just move to the saved spot.
            if let st, let r = UserDefaults.standard.dictionary(forKey: "resume"),
               let saved = r["track"] as? String, st.trackID == saved {
                self.resumePending = false
                let pos = r["position"] as? Double ?? 0
                Log.write("Music restored the same song; seeking to \(Int(pos)) s")
                if abs(st.position - pos) > 2 { self.bridge.seek(to: pos) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadingText = nil
                    self.poll()
                }
                return
            }
            Log.write("Music has a different song (\(st?.trackID ?? "none")); cueing the saved one")
            self.resume(thenPlay: false)
        }
    }

    /// Show the saved song straight away, before Music is ready.
    private func showSavedSong() {
        guard let r = UserDefaults.standard.dictionary(forKey: "resume") else { return }
        var t = TrackInfo()
        t.state = "paused"
        t.trackID = r["track"] as? String ?? ""
        t.playlistID = r["playlist"] as? String ?? ""
        t.playlist = r["playlistName"] as? String ?? ""
        t.name = r["name"] as? String ?? ""
        t.artist = r["artist"] as? String ?? ""
        t.album = r["album"] as? String ?? ""
        t.position = r["position"] as? Double ?? 0
        t.duration = r["duration"] as? Double ?? 0
        info = t
        artTrackID = artKey(t)
        fetchOnlineArtwork(for: t)   // Music isn't up yet, so use the catalog art
    }

    func quitMusicIfWanted() {
        guard quitMusicOnExit else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: MusicBridge.bundleID)
        if !apps.isEmpty { Log.write("quitting Music") }
        apps.forEach { $0.terminate() }   // a normal quit, as if you chose Music > Quit
    }

    /// Run `action` once Music is running, starting Music hidden first if needed.
    /// (A plain AppleScript command would start Music with its window in front.)
    func withMusic(_ action: @escaping () -> Void) {
        if bridge.isMusicRunning { action(); return }
        launchMusicHidden(then: action)
    }

    func launchMusicHidden(then action: (() -> Void)? = nil) {
        guard !launching,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) else { return }
        launching = true
        Log.write("starting Music hidden")
        let c = NSWorkspace.OpenConfiguration()
        c.activates = false
        c.hides = true
        c.addsToRecentItems = false
        if loadingText == nil { loadingText = "Starting Music…" }
        NSWorkspace.shared.openApplication(at: url, configuration: c) { _, error in
            DispatchQueue.main.async { [weak self] in
                if let error { Log.write("couldn't start Music: \(error)") }
                self?.waitUntilMusicAnswers(tries: 30) {
                    self?.launching = false
                    if self?.loadingText == "Starting Music…" { self?.loadingText = nil }
                    self?.poll()
                    action?()
                }
            }
        }
    }

    /// Ask Music for its status until it replies (it can't answer while still starting).
    private func waitUntilMusicAnswers(tries: Int, then done: @escaping () -> Void) {
        bridge.status { [weak self] st in
            if st != nil || tries <= 0 {
                Log.write(st != nil ? "Music is ready" : "Music didn't answer in time")
                done(); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.waitUntilMusicAnswers(tries: tries - 1, then: done)
            }
        }
    }

    func start() {
        if resumePending {
            showSavedSong()
            loadingText = "Starting Music…"
        }
        // Never leave the spinner up if Music doesn't respond.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.loadingText != nil else { return }
            Log.write("gave up waiting for Music")
            self.loadingText = nil
            self.poll()
        }
        if autoStartMusic, !bridge.isMusicRunning {
            launchMusicHidden(then: { [weak self] in self?.resumeIfIdle() })
        } else if bridge.isMusicRunning {
            resumeIfIdle()
        } else {
            loadingText = nil   // Music stays closed until you press play
        }
        poll()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5   // let macOS batch the wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Music.app announces play/pause/track changes; refresh right away on those.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] note in
            self?.apply(note.userInfo ?? [:])
            self?.poll()
        }
    }

    /// Music.app's own broadcast carries the track details, so the display
    /// updates even when AppleScript is slow or failing.
    private func apply(_ u: [AnyHashable: Any]) {
        var new = info
        if let st = u["Player State"] as? String { new.state = st.lowercased() }
        if new.state == "stopped" { new = TrackInfo(); new.shuffle = info.shuffle }
        else {
            if let v = u["Name"] as? String, v != new.name { new.name = v; new.position = 0 }
            if let v = u["Artist"] as? String { new.artist = v }
            if let v = u["Album"] as? String { new.album = v }
            if let ms = u["Total Time"] as? Double { new.duration = ms / 1000 }
            else if let ms = u["Total Time"] as? Int { new.duration = Double(ms) / 1000 }
        }
        Log.write("notification: \(new.state) \(new.name)")
        update(with: new)
    }

    /// Track artwork by song identity rather than Music's ID, which the
    /// broadcast doesn't share in the same form.
    private func artKey(_ t: TrackInfo) -> String {
        t.name.isEmpty && t.artist.isEmpty ? "" : "\(t.artist)|\(t.album)|\(t.name)"
    }

    private func update(with new: TrackInfo) {
        var merged = new
        if Date() < holdStateUntil, merged.trackID == info.trackID {
            merged.state = info.state; merged.position = info.position
        }
        if merged.playlist.isEmpty, merged.state != "stopped" {
            merged.playlist = info.playlist; merged.playlistID = info.playlistID
        }
        if info != merged { info = merged; positionStamp = Date() }
        if showQueue, merged.playlistID != tracksFor { loadTracks() }
        let key = artKey(merged)
        guard key != artTrackID else { return }
        artTrackID = key
        artwork = nil
        guard !key.isEmpty else { return }
        bridge.artwork { [weak self] img in
            guard let self, self.artTrackID == key else { return }
            if let img { self.artwork = img } else { self.fetchOnlineArtwork(for: merged) }
        }
    }

    func poll() {
        nextPollAt = Date().addingTimeInterval(pollInterval)
        running = bridge.isMusicRunning
        guard running else {
            // Keep showing the saved song while it's waiting to be resumed.
            if !resumePending, loadingText == nil, info != TrackInfo() {
                info = TrackInfo(); artwork = nil; artTrackID = ""
            }
            return
        }
        if playlists.isEmpty { refreshPlaylists() }
        guard !polling else { return }
        polling = true
        bridge.status { [weak self] new in
            guard let self else { return }
            self.polling = false
            guard let new else {
                self.errorText = "Can't read Music's status (see ~/Library/Logs/MiniDeck.log)"
                return
            }
            self.errorText = ""
            // While starting or resuming, Music's half-ready state would flash "Not playing".
            guard self.loadingText == nil else { return }
            self.update(with: new)
            if new.volume >= 0, Date() >= self.volumeHoldUntil, Double(new.volume) != self.volume {
                self.volume = Double(new.volume)
            }
            self.nextPollAt = Date().addingTimeInterval(self.pollInterval)
            if new.isPlaying, Date().timeIntervalSince(self.lastResumeSave) > 10 { self.saveResumePoint() }
        }
    }

    /// Apple Music streaming tracks often have no artwork in AppleScript,
    /// so look the album up in Apple's public iTunes Search API instead.
    private func fetchOnlineArtwork(for t: TrackInfo) {
        guard !t.artist.isEmpty else { return }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        let useAlbum = !t.album.isEmpty
        c.queryItems = [
            .init(name: "term", value: "\(t.artist) \(useAlbum ? t.album : t.name)"),
            .init(name: "entity", value: useAlbum ? "album" : "song"),
            .init(name: "limit", value: "1"),
            .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let url = c.url else { return }
        let id = artKey(t)
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (obj["results"] as? [[String: Any]])?.first,
                  let small = first["artworkUrl100"] as? String,
                  let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            else { Log.write("online artwork: no match for \(t.artist) / \(t.album) \(error.map { "\($0)" } ?? "")"); return }
            URLSession.shared.dataTask(with: big) { d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { [weak self] in
                    if self?.artTrackID == id { self?.artwork = img }
                }
            }.resume()
        }.resume()
    }

    func loadTracks(force: Bool = false) {
        guard showQueue, running else { return }
        let pid = info.playlistID
        if !force, pid == tracksFor { return }
        tracksFor = pid                       // don't re-request on every poll
        guard !pid.isEmpty else { tracks = []; return }
        bridge.tracks { [weak self] result in
            guard let self else { return }
            self.tracks = result?.tracks ?? []
            if let r = result { self.tracksFor = r.playlistID }
            Log.write("loaded \(self.tracks.count) songs for the list")
        }
    }

    func playTrack(_ t: QueueTrack) {
        guard !tracksFor.isEmpty else { return }
        resumePending = false
        bridge.playTrack(t.trackID, inPlaylist: tracksFor)
        pollSoon(in: 1.5)
    }

    func isCurrent(_ p: Playlist) -> Bool {
        info.playlistID.isEmpty ? p.name == info.playlist : p.id == info.playlistID
    }

    func refreshPlaylists() {
        bridge.playlists { [weak self] list in self?.playlists = list }
    }

    func playPause() {
        info.position = livePosition(at: Date()); positionStamp = Date()
        info.state = info.isPlaying ? "paused" : "playing"   // instant feedback
        holdStateUntil = Date().addingTimeInterval(1.5)
        withMusic { [weak self] in
            guard let self else { return }
            if self.resumePending { self.resume(thenPlay: true) } else { self.bridge.playPause() }
        }
        pollSoon(in: 1.6)   // after the 1.5 s hold, confirm the real state
    }
    func next() {
        let before = info.trackID
        withMusic { [weak self] in self?.bridge.next() }
        pollSoon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.info.trackID == before, !before.isEmpty else { return }
            Log.write("next: song didn't change (still \(self.info.name), playlist '\(self.info.playlist)')")
        }
    }
    func toggleShuffle() {
        info.shuffle.toggle()   // instant feedback; the next status poll confirms it
        bridge.setShuffle(info.shuffle)
        pollSoon()
    }
    func previous() { withMusic { [weak self] in self?.bridge.previous() }; pollSoon() }
    func play(_ p: Playlist) {
        Log.write("play playlist \(p.name)")
        resumePending = false
        // Let the menu finish closing before changing state that resizes the view.
        info.playlist = p.name; info.playlistID = p.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.withMusic { self?.bridge.play(p) }
        }
    }
    func seek(fraction: Double) {
        guard info.duration > 0, fraction.isFinite else { return }
        let t = max(0, min(1, fraction)) * info.duration
        info.position = t
        positionStamp = Date()
        bridge.seek(to: t)
        pollSoon(in: 1.5)
    }
}
