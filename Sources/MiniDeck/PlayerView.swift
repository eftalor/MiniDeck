import SwiftUI

/// The window's background: Liquid Glass (macOS 26+) when `glass` is on,
/// otherwise the original dark blur. Rebuilt only when the settings change.
struct WindowBackground: NSViewRepresentable {
    var glass: Bool
    var clear: Bool
    static let radius: CGFloat = 16

    final class Holder: NSView { var key = "" }

    func makeNSView(context: Context) -> Holder { let v = Holder(); apply(v); return v }
    func updateNSView(_ v: Holder, context: Context) { apply(v) }

    private func apply(_ v: Holder) {
        let key = "\(glass)-\(clear)"
        guard key != v.key else { return }
        v.key = key
        v.subviews.forEach { $0.removeFromSuperview() }
        let bg: NSView
        if glass, #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.style = clear ? .clear : .regular
            g.cornerRadius = Self.radius
            bg = g
        } else {
            let e = NSVisualEffectView()
            e.material = .hudWindow
            e.blendingMode = .behindWindow
            e.state = .active
            e.wantsLayer = true
            e.layer?.cornerRadius = Self.radius
            e.layer?.masksToBounds = true
            if glass { e.alphaValue = 0.7 }   // older macOS: a lighter blur instead of glass
            bg = e
        }
        bg.frame = v.bounds
        bg.autoresizingMask = [.width, .height]
        v.addSubview(bg)
    }
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    var onClose: () -> Void
    var onMinimize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            player
            if model.showQueue {
                Divider().padding(.horizontal, 12)
                TrackListView(model: model).frame(height: 220)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 360)
        .background(WindowBackground(glass: model.glass, clear: model.glassClear))
    }

    private var player: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                // Always laid out (hidden when empty) so the window height stays fixed.
                if let loading = model.loadingText {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                        Text(loading).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                } else {
                    let showList = !model.info.playlist.isEmpty && model.info.state != "stopped"
                    Label(showList ? model.info.playlist : "—", systemImage: "music.note.list")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .opacity(showList ? 1 : 0)
                        .help("Playing from this playlist")
                }
                progress
                HStack(spacing: 10) {
                    control("backward.fill", size: 14, action: model.previous)
                    control(model.info.isPlaying ? "pause.fill" : "play.fill", size: 20, action: model.playPause)
                    control("forward.fill", size: 14, action: model.next)
                    Button(action: model.toggleShuffle) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 12, weight: model.info.shuffle ? .bold : .regular))
                            .foregroundStyle(model.info.shuffle ? Color.accentColor : Color.secondary)
                            .frame(width: 24, height: 24)
                            .background(model.info.shuffle ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help(model.info.shuffle ? "Shuffle is on" : "Shuffle is off")
                    Button(action: { model.showQueue.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: model.showQueue ? .bold : .regular))
                            .foregroundStyle(model.showQueue ? Color.accentColor : Color.secondary)
                            .frame(width: 24, height: 24)
                            .background(model.showQueue ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help(model.showQueue ? "Hide the song list" : "Show the playlist's songs")
                    volumeButton
                    Spacer(minLength: 4)
                    playlistMenu
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 28)   // room for the close and minimize buttons
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                windowButton(color: Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark",
                             help: model.quitMusicOnExit ? "Quit MiniDeck and Music" : "Quit MiniDeck", action: onClose)
                windowButton(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus",
                             help: "Minimize to the Dock", action: onMinimize)
            }
            .padding(.top, 9)
            .padding(.leading, 12)
            .onHover { model.hoverWindowButtons = $0 }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                Button(action: { model.floating.toggle() }) {
                    Image(systemName: model.floating ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .rotationEffect(.degrees(model.floating ? 0 : 45))
                        .foregroundStyle(model.floating ? Color.accentColor : Color.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(model.floating ? "Always on top (click to turn off)" : "Not on top (click to keep above other windows)")
                Button(action: { model.glass.toggle() }) {
                    Image(systemName: model.glass ? "drop.fill" : "drop")
                        .font(.system(size: 11))
                        .foregroundStyle(model.glass ? Color.accentColor : Color.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(model.glass ? "Glass is on (click to turn off)" : "Glass is off (click to turn on)")
            }
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
        .contextMenu {
            Button(model.showQueue ? "Hide song list" : "Show song list") { model.showQueue.toggle() }
            Toggle("Always on top", isOn: Binding(get: { model.floating }, set: { model.floating = $0 }))
            Button(model.glass ? "Turn glass off" : "Turn glass on") { model.glass.toggle() }
            Button(model.glassClear ? "Glass style: frosted" : "Glass style: clear") { model.glassClear.toggle() }
            Divider()
            Button("Refresh playlists", action: model.refreshPlaylists)
            Toggle("Start Music hidden with MiniDeck", isOn: Binding(
                get: { model.autoStartMusic }, set: { model.autoStartMusic = $0 }))
            Toggle("Quit Music when MiniDeck quits", isOn: Binding(
                get: { model.quitMusicOnExit }, set: { model.quitMusicOnExit = $0 }))
            Divider()
            Button("Quit MiniDeck") { NSApp.terminate(nil) }
        }
    }

    private var title: String {
        // A saved song (waiting to resume) is shown even before Music is up.
        if !model.running, model.info.name.isEmpty { return "Music isn't running" }
        if model.info.state == "stopped" { return "Not playing" }
        return model.info.name.isEmpty ? "—" : model.info.name
    }

    private var subtitle: String {
        if !model.running, model.info.name.isEmpty { return "Press play to start it in the background" }
        if !model.errorText.isEmpty { return model.errorText }
        return [model.info.artist, model.info.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let img = model.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var progress: some View {
        // Ticks once a second only while playing and on screen; otherwise it's idle.
        TimelineView(.animation(minimumInterval: 1,
                                paused: !(model.info.isPlaying && model.windowVisible))) { ctx in
            let d = model.info.duration
            let pos = model.dragFraction.map { $0 * d } ?? model.livePosition(at: ctx.date)
            let frac = d > 0 ? max(0, min(1, pos / d)) : 0
            HStack(spacing: 6) {
                Text(fmt(pos)).monospacedDigit()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(model.dragFraction == nil ? Color.secondary : Color.accentColor)
                            .frame(width: g.size.width * frac)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard g.size.width > 0 else { return }
                                model.dragFraction = max(0, min(1, v.location.x / g.size.width))
                            }
                            .onEnded { _ in
                                if let f = model.dragFraction { model.seek(fraction: f) }
                                model.dragFraction = nil
                            }
                    )
                }
                .frame(height: 12)
                Text(fmt(d)).monospacedDigit()
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }

    private var volumeSymbol: String {
        switch model.volume {
        case ..<1: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Music's own volume: click for a slider, scroll over the icon to adjust, Option-click to mute.
    private var volumeButton: some View {
        Button(action: {
            if NSEvent.modifierFlags.contains(.option) { model.toggleMute() } else { model.showVolume.toggle() }
        }) {
            Image(systemName: volumeSymbol)
                .font(.system(size: 12))
                .foregroundStyle(model.volume < 1 ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24, alignment: .center)
        }
        .buttonStyle(.plain)
        .overlay(ScrollCatcher { dy in model.setVolume(model.volume + dy) })
        .help("Music volume \(Int(model.volume))% (only Music, not the Mac). Scroll to adjust, Option-click to mute")
        .popover(isPresented: Binding(get: { model.showVolume }, set: { model.showVolume = $0 }),
                 arrowEdge: .bottom) {
            HStack(spacing: 8) {
                Button(action: model.toggleMute) {
                    Image(systemName: volumeSymbol).frame(width: 18)
                }
                .buttonStyle(.plain)
                .help(model.volume < 1 ? "Unmute" : "Mute")
                Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...100)
                    .frame(width: 140)
                Text("\(Int(model.volume))%").monospacedDigit()
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(10)
        }
    }

    private var playlistMenu: some View {
        Button(action: { model.showPlaylists.toggle() }) {
            HStack(spacing: 2) {
                Image(systemName: "music.note.list").font(.system(size: 13))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(model.showPlaylists ? Color.accentColor : Color.primary)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose a playlist to play")
        .popover(isPresented: Binding(get: { model.showPlaylists }, set: { model.showPlaylists = $0 }),
                 arrowEdge: .bottom) {
            playlistPicker
        }
    }

    private var playlistPicker: some View {
        let list = model.filteredPlaylists
        return VStack(spacing: 6) {
            SearchField(text: Binding(get: { model.playlistQuery }, set: { model.playlistQuery = $0 }),
                        placeholder: "Search \(model.playlists.count) playlists",
                        onMove: model.movePlaylistSelection,
                        onSubmit: { model.choosePlaylist() },
                        onCancel: { model.showPlaylists = false })
                .frame(width: 244, height: 22)
            // Fixed height: resizing a popover while typing crashes AppKit.
            ZStack {
                if list.isEmpty {
                    Text(model.playlists.isEmpty
                         ? (model.running ? "No playlists found" : "Start Music to load playlists")
                         : "No match")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(list.indices, id: \.self) { i in
                                    let item = list[i]
                                    playlistRow(item.playlist, hits: item.hits, selected: i == model.playlistSelection)
                                        .onTapGesture { model.choosePlaylist(item.playlist) }
                                        .onHover { if $0 { model.playlistSelection = i } }
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo(model.playlistSelection, anchor: .center) }
                        .onChange(of: model.playlistSelection) { _, i in proxy.scrollTo(i) }
                    }
                }
            }
            .frame(width: 244, height: 288, alignment: .top)
            HStack {
                Text(model.playlistQuery.isEmpty ? "↑↓ to pick, Return to play"
                                                 : "\(list.count) of \(model.playlists.count)")
                Spacer()
                Button("Refresh", action: model.refreshPlaylists).buttonStyle(.link)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .frame(width: 244)
        }
        .padding(8)
        .fixedSize()
    }

    private func playlistRow(_ p: Playlist, hits: [Int], selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .opacity(model.isCurrent(p) ? 1 : 0)
            highlighted(p.name, hits)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    /// The name with the letters the search matched in bold.
    private func highlighted(_ name: String, _ hits: [Int]) -> Text {
        let chars = Array(name)
        guard !hits.isEmpty, hits.allSatisfy({ $0 < chars.count }) else { return Text(name) }
        let set = Set(hits)
        var out = Text("")
        var run = "", runBold = false
        for (i, c) in chars.enumerated() {
            let b = set.contains(i)
            if b != runBold, !run.isEmpty {
                out = out + (runBold ? Text(run).bold() : Text(run)); run = ""
            }
            runBold = b; run.append(c)
        }
        return out + (runBold ? Text(run).bold() : Text(run))
    }

    /// Mac-style traffic light; the symbol shows while the pointer is over the pair.
    private func windowButton(color: Color, symbol: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(model.hoverWindowButtons ? 1 : 0)
            }
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Receives scroll-wheel and trackpad scrolls over a view, and lets clicks pass through.
struct ScrollCatcher: NSViewRepresentable {
    var onScroll: (Double) -> Void

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }
        override func scrollWheel(with e: NSEvent) {
            // Trackpads report fine-grained deltas; mouse wheels coarse lines.
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 4 : e.scrollingDeltaY * 4
            // Rolling or swiping up means louder, whatever the "natural scrolling" setting.
            onScroll?(e.isDirectionInvertedFromDevice ? -dy : dy)
        }
    }

    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.onScroll = onScroll }
}


/// A search field that keeps the keyboard: arrows move the selection, Return picks, Esc clears or closes.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.delegate = context.coordinator
        f.placeholderString = placeholder
        f.focusRingType = .none
        f.sendsSearchStringImmediately = true
        // The player is a non-activating panel, so make MiniDeck active to receive typing.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            f.window?.makeKey()
            f.window?.makeFirstResponder(f)
        }
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        f.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ p: SearchField) { parent = p }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): parent.onMove(-10)
            case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): parent.onMove(10)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.text.isEmpty { parent.onCancel() } else { parent.text = "" }
            default: return false
            }
            return true
        }
    }
}
