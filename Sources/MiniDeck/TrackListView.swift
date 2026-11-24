import SwiftUI

struct QueueTrack: Identifiable {
    let id: Int          // position in the playlist (0-based); unique even if a song repeats
    let trackID: String  // Music persistent ID
    let name: String
    let artist: String
}

/// The current playlist's songs, with the playing one highlighted and kept in view.
struct TrackListView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        if model.tracks.isEmpty {
            Text(model.info.playlistID.isEmpty ? "Not playing from a playlist" : "Loading songs…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.tracks) { t in row(t).id(t.id) }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    DispatchQueue.main.async { scroll(proxy, animated: false) }
                }
                .onChange(of: model.currentTrackIndex) { scroll(proxy, animated: true) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let i = model.currentTrackIndex else { return }
        withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
            proxy.scrollTo(i, anchor: .center)
        }
    }

    private func row(_ t: QueueTrack) -> some View {
        let current = t.id == model.currentTrackIndex
        return HStack(spacing: 8) {
            Group {
                if current {
                    Image(systemName: model.info.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                } else {
                    Text("\(t.id + 1)").monospacedDigit()
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(current ? Color.accentColor : Color.secondary)
            .frame(width: 26, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(t.name)
                    .font(.system(size: 11, weight: current ? .semibold : .regular))
                    .lineLimit(1)
                if !t.artist.isEmpty {
                    Text(t.artist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(current ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.playTrack(t) }
    }
}
