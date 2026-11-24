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
    var onToggleFloat: () -> Void
    var isFloating: () -> Bool
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
                HStack(spacing: 12) {
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
            Button(action: { model.glass.toggle() }) {
                Image(systemName: model.glass ? "drop.fill" : "drop")
                    .font(.system(size: 11))
                    .foregroundStyle(model.glass ? Color.accentColor : Color.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(model.glass ? "Glass is on (click to turn off)" : "Glass is off (click to turn on)")
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
        .contextMenu {
            Button(model.showQueue ? "Hide song list" : "Show song list") { model.showQueue.toggle() }
            Button(isFloating() ? "Stop floating on top" : "Float on top", action: onToggleFloat)
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

    private var playlistMenu: some View {
        Menu {
            if model.playlists.isEmpty {
                Text(model.running ? "No playlists found" : "Start Music to load playlists")
            }
            ForEach(model.playlists) { p in
                // A toggle shows a checkmark next to the playlist that's playing now.
                Toggle(p.name, isOn: Binding(get: { model.isCurrent(p) }, set: { _ in model.play(p) }))
            }
            Divider()
            Button("Refresh list", action: model.refreshPlaylists)
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Choose a playlist to play")
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
