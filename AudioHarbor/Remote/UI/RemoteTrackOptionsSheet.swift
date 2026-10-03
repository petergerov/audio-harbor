import SwiftUI

/// Which part of a track the sheet edits — the remote's two long-press entries.
enum RemoteTrackOptionsKind: String, Sendable {
    case playlists
    case labels

    var title: String {
        switch self {
        case .playlists: "Add to Playlist"
        case .labels: "Labels"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: "text.badge.plus"
        case .labels: "tag"
        }
    }
}

/// One track, and whether its playlists or its labels are being edited.
struct RemoteTrackOptionsRequest: Identifiable, Equatable {
    var track: TrackDTO
    var kind: RemoteTrackOptionsKind
    var id: String { "\(kind.rawValue):\(track.cataloguePath)" }
}

/// Files one track on the Mac from the remote: tap a manual playlist or a label to put the track
/// in or take it out — a checkmark shows where it is.
/// Each change goes to the Mac, which answers with the track's playlists and labels as they now stand.
struct RemoteTrackOptionsSheet: View {
    let controller: RemoteController
    let track: TrackDTO
    let kind: RemoteTrackOptionsKind
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var newLabel = ""

    private var options: TrackOptionsDTO? {
        guard let options = controller.trackOptions, options.cataloguePath == track.cataloguePath else {
            return nil
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Group {
                if let options {
                    optionsList(options)
                } else {
                    ProgressView()
                        .tint(HarborColor.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(HarborColor.chassis)
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(HarborColor.amber)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: track.cataloguePath) {
            controller.loadTrackOptions(cataloguePath: track.cataloguePath)
        }
    }

    private func optionsList(_ options: TrackOptionsDTO) -> some View {
        List {
            Section {
                switch kind {
                case .playlists:
                    playlistRows(options)
                case .labels:
                    labelRows(options)
                }
            } header: {
                Text("\(track.title) — \(track.artist)")
                    .lineLimit(1)
            }
            .listRowBackground(HarborColor.faceplateLift)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func playlistRows(_ options: TrackOptionsDTO) -> some View {
        ForEach(options.playlists) { playlist in
            Button {
                edit(playlist.containsTrack
                    ? .removeFromPlaylist(id: playlist.id)
                    : .addToPlaylist(id: playlist.id))
            } label: {
                choiceRow(playlist.name, isOn: playlist.containsTrack)
            }
        }
        newEntryRow("New Playlist", text: $newPlaylistName) { .addToNewPlaylist(name: $0) }
    }

    @ViewBuilder
    private func labelRows(_ options: TrackOptionsDTO) -> some View {
        ForEach(options.labels, id: \.self) { label in
            let isOn = options.trackLabels.contains {
                $0.caseInsensitiveCompare(label) == .orderedSame
            }
            Button {
                edit(isOn ? .removeLabel(name: label) : .addLabel(name: label))
            } label: {
                choiceRow(label, isOn: isOn)
            }
        }
        newEntryRow("New Label", text: $newLabel) { .addLabel(name: $0) }
    }

    private func choiceRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(HarborColor.ivory)
                .lineLimit(1)
            Spacer()
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HarborColor.amber)
            }
        }
        .font(HarborFont.body(14))
        .contentShape(Rectangle())
    }

    private func newEntryRow(
        _ prompt: String,
        text: Binding<String>,
        edit makeEdit: @escaping (String) -> TrackEdit
    ) -> some View {
        let name = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(HarborFont.body(14))
                .foregroundStyle(HarborColor.ivory)
                .onSubmit { submit(name, into: text, makeEdit) }
            Button("Add") { submit(name, into: text, makeEdit) }
                .buttonStyle(.plain)
                .font(HarborFont.body(14))
                .foregroundStyle(name.isEmpty ? HarborColor.ivoryDim : HarborColor.amber)
                .disabled(name.isEmpty)
        }
    }

    private func submit(_ name: String, into text: Binding<String>, _ makeEdit: (String) -> TrackEdit) {
        guard !name.isEmpty else { return }
        edit(makeEdit(name))
        text.wrappedValue = ""
    }

    private func edit(_ edit: TrackEdit) {
        controller.editTrack(cataloguePath: track.cataloguePath, edit)
    }
}
