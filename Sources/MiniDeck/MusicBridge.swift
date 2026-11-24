import AppKit

struct TrackInfo: Equatable {
    var state = "stopped"
    var name = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var trackID = ""
    var playlist = ""
    var playlistID = ""
    var shuffle = false
    var isPlaying: Bool { state == "playing" }
}

struct Playlist: Identifiable, Hashable {
    let id: String   // Music.app persistent ID
    let name: String
}

/// Talks to Music.app through AppleScript. All scripts run on one serial queue
/// (NSAppleScript is not safe to run concurrently).
final class MusicBridge {
    static let bundleID = "com.apple.Music"
    private let queue = DispatchQueue(label: "minideck.applescript")
    private var cache: [String: NSAppleScript] = [:]

    var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let s = cache[source] { script = s } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            var err: NSDictionary?
            s.compileAndReturnError(&err)
            cache[source] = s
            script = s
        }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err { Log.write("AppleScript error: \(err)"); return nil }
        return result
    }

    func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            let r = self.execute(source)
            if let completion { DispatchQueue.main.async { completion(r) } }
        }
    }

    // MARK: - Queries

    private static let statusScript = """
    with timeout of 5 seconds
    tell application "Music"
        set mdSep to character id 31
        set mdState to player state as string
        set mdShuffle to "false"
        try
            set mdShuffle to shuffle enabled as string
        end try
        if mdState is "stopped" then return mdState & mdSep & mdShuffle
        set mdOut to mdState & mdSep & mdShuffle
        try
            set mdTrack to current track
            set mdOut to mdOut & mdSep & (name of mdTrack) & mdSep & (artist of mdTrack) & mdSep & (album of mdTrack) & mdSep & ((round ((duration of mdTrack) * 1000)) as integer as string) & mdSep & ((round ((player position) * 1000)) as integer as string) & mdSep & (persistent ID of mdTrack)
        on error
            set mdOut to mdOut & mdSep & "" & mdSep & "" & mdSep & "" & mdSep & "0" & mdSep & "0" & mdSep & ""
        end try
        try
            set mdOut to mdOut & mdSep & (name of current playlist) & mdSep & (persistent ID of current playlist)
        on error
            set mdOut to mdOut & mdSep & "" & mdSep & ""
        end try
        return mdOut
    end tell
    end timeout
    """

    private static var lastRawLog = Date.distantPast
    static func logRawOccasionally(_ raw: String) {
        guard Date().timeIntervalSince(lastRawLog) > 60 else { return }
        lastRawLog = Date()
        Log.write("status raw: " + raw.replacingOccurrences(of: "\u{1F}", with: " | "))
    }

    /// nil means the script failed (see the log); keep the last known state then.
    func status(_ done: @escaping (TrackInfo?) -> Void) {
        run(Self.statusScript) { d in
            var info = TrackInfo()
            guard let s = d?.stringValue else { done(nil); return }
            MusicBridge.logRawOccasionally(s)
            let f = s.components(separatedBy: "\u{1F}")
            func num(_ i: Int) -> Double { i < f.count ? Double(f[i].replacingOccurrences(of: ",", with: ".")) ?? 0 : 0 }
            func str(_ i: Int) -> String { i < f.count ? f[i] : "" }
            info.state = str(0)
            info.shuffle = str(1) == "true"
            info.name = str(2); info.artist = str(3); info.album = str(4)
            info.duration = num(5) / 1000; info.position = num(6) / 1000
            info.trackID = str(7); info.playlist = str(8); info.playlistID = str(9)
            done(info)
        }
    }

    func artwork(_ done: @escaping (NSImage?) -> Void) {
        run("""
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            end try
            try
                return data of artwork 1 of current track
            end try
        end tell
        """) { d in
            guard let data = d?.data, !data.isEmpty else { done(nil); return }
            done(NSImage(data: data))
        }
    }

    func playlists(_ done: @escaping ([Playlist]) -> Void) {
        run("""
        tell application "Music"
            set mdOut to ""
            repeat with mdList in (every user playlist whose special kind is none)
                set mdOut to mdOut & (persistent ID of mdList) & (character id 31) & (name of mdList) & (character id 30)
            end repeat
            return mdOut
        end tell
        """) { d in
            let rows = (d?.stringValue ?? "").components(separatedBy: "\u{1E}")
            done(rows.compactMap { row in
                let parts = row.components(separatedBy: "\u{1F}")
                guard parts.count == 2, !parts[0].isEmpty else { return nil }
                return Playlist(id: parts[0], name: parts[1])
            })
        }
    }

    /// Every song in the current playlist, in playlist order: one request per field.
    func tracks(_ done: @escaping ((playlistID: String, tracks: [QueueTrack])?) -> Void) {
        run("""
        with timeout of 20 seconds
        tell application "Music"
            set mdPl to current playlist
            set mdPid to persistent ID of mdPl
            set AppleScript's text item delimiters to (character id 30)
            set mdIds to (persistent ID of every track of mdPl) as text
            set mdNames to (name of every track of mdPl) as text
            set mdArtists to (artist of every track of mdPl) as text
            set AppleScript's text item delimiters to ""
            return mdPid & (character id 29) & mdIds & (character id 29) & mdNames & (character id 29) & mdArtists
        end tell
        end timeout
        """) { d in
            guard let s = d?.stringValue else { done(nil); return }
            let parts = s.components(separatedBy: "\u{1D}")
            guard parts.count == 4 else { done(nil); return }
            let ids = parts[1].components(separatedBy: "\u{1E}")
            let names = parts[2].components(separatedBy: "\u{1E}")
            let artists = parts[3].components(separatedBy: "\u{1E}")
            guard !parts[1].isEmpty, ids.count == names.count, ids.count == artists.count else {
                done((parts[0], [])); return
            }
            done((parts[0], ids.indices.map {
                QueueTrack(id: $0, trackID: ids[$0], name: names[$0], artist: artists[$0])
            }))
        }
    }

    /// Load a song paused at `position` (seconds): Music can't load without playing,
    /// so mute, play, pause, seek, unmute. Optionally start playing at the end.
    func cue(trackID: String, playlistID: String, position: Double, thenPlay: Bool,
             done: @escaping (Bool) -> Void) {
        let t = trackID.filter { $0.isHexDigit }, p = playlistID.filter { $0.isHexDigit }
        let pos = position.isFinite ? max(0, Int(position)) : 0
        let startLine = p.isEmpty
            ? "play (first track of library playlist 1 whose persistent ID is \"\(t)\")"
            : """
              try
                  tell (first playlist whose persistent ID is "\(p)") to play (first track whose persistent ID is "\(t)")
              on error
                  play (first track of library playlist 1 whose persistent ID is "\(t)")
              end try
              """
        run("""
        with timeout of 20 seconds
        tell application "Music"
            set mdVol to sound volume
            set mdOK to false
            try
                set sound volume to 0
                \(startLine)
                delay 0.6
                pause
                set player position to \(pos)
                set mdOK to true
            end try
            set sound volume to mdVol
            \(thenPlay ? "play" : "")
            return mdOK
        end tell
        end timeout
        """) { d in done(d?.booleanValue ?? false) }
    }

    // MARK: - Commands

    /// Fire-and-forget: don't wait for Music to finish (starting a playlist can
    /// take seconds, and waiting would stall every status update behind it).
    private func command(_ cmd: String) {
        run("""
        tell application "Music"
            ignoring application responses
                \(cmd)
            end ignoring
        end tell
        """)
    }

    // Transport buttons skip the AppleScript queue entirely: they send Music's raw
    // Apple Events (suite 'hook') without waiting for a reply, so a slow status
    // poll or playlist load can never delay a button press.
    private static func code(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
    private let eventQueue = DispatchQueue(label: "minideck.events", qos: .userInteractive)

    private func send(_ eventID: String, fallback: String) {
        eventQueue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
            let event = NSAppleEventDescriptor(eventClass: Self.code("hook"), eventID: Self.code(eventID),
                                               targetDescriptor: target, returnID: -1, transactionID: 0)
            // AppleScript always adds an empty "subject"; some commands need it.
            event.setAttribute(.null(), forKeyword: Self.code("subj"))
            do {
                // Wait for Music's answer (on this queue only) so a refusal isn't silent.
                let reply = try event.sendEvent(options: [.waitForReply], timeout: 3)
                if let errn = reply.paramDescriptor(forKeyword: Self.code("errn")), errn.int32Value != 0 {
                    let msg = reply.paramDescriptor(forKeyword: Self.code("errs"))?.stringValue ?? ""
                    Log.write("Music refused direct \(eventID): \(errn.int32Value) \(msg); using AppleScript")
                    self.command(fallback)
                }
            } catch {
                Log.write("direct \(eventID) failed (\(error)); using AppleScript")
                self.command(fallback)
            }
        }
    }

    func playPause() { send("PlPs", fallback: "playpause") }
    func next() { send("Next", fallback: "next track") }
    func setShuffle(_ on: Bool) { command("set shuffle enabled to \(on)") }
    func previous() { send("Prev", fallback: "previous track") }
    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        command("set player position to \(Int(seconds))")
    }

    /// Play one song inside its playlist, so playback continues through that playlist.
    func playTrack(_ trackID: String, inPlaylist playlistID: String) {
        let t = trackID.filter { $0.isHexDigit }, p = playlistID.filter { $0.isHexDigit }
        command("tell (first playlist whose persistent ID is \"\(p)\") to play (first track whose persistent ID is \"\(t)\")")
    }

    func play(_ p: Playlist) {
        // Persistent IDs are hex, so they are safe to embed.
        let id = p.id.filter { $0.isHexDigit }
        command("play (first user playlist whose persistent ID is \"\(id)\")")
    }
}
